[CmdletBinding()]
param(
    [string]$Workspace = (Get-Location).Path,
    [switch]$Compact
)

$ErrorActionPreference = 'Stop'

# Treat an explicitly empty -Workspace exactly like an omitted one.
# This matters when callers pass an unset PowerShell variable such as -Workspace "$workspace".
if ([string]::IsNullOrWhiteSpace($Workspace)) {
    $Workspace = (Get-Location).Path
}

$Workspace = (Resolve-Path -LiteralPath $Workspace).Path
$root = Join-Path $Workspace '.job-apply-autopilot'
if (-not (Test-Path -LiteralPath $root)) {
    throw "No job-apply-autopilot runtime at $root"
}

function Read-JsonSafe([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json) } catch { return $null }
}

function Has-Property($Object, [string]$Name) {
    return ($null -ne $Object -and $Object.PSObject.Properties.Name -contains $Name)
}

function Test-SourceReady([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    try { $text = Get-Content -LiteralPath $Path -Raw } catch { return $false }
    if ([string]::IsNullOrWhiteSpace($text)) { return $false }
    if ($text -match 'Coordinator:\s*replace this placeholder') { return $false }
    return $text.Trim().Length -ge 80
}

function Get-SubmissionIdentity([string]$Company, [string]$Title, [string]$JobId) {
    $companyKey = (($Company.ToLowerInvariant() -replace '&', ' and ' -replace '[^a-z0-9]+', ' ').Trim() -replace '\s+', ' ')
    do {
        $priorCompanyKey = $companyKey
        $companyKey = ($companyKey -replace '\s+(private limited|pvt ltd|pvt limited|limited|ltd|llc|incorporated|inc|corporation|corp|gmbh|plc|company|co)$', '').Trim()
    } while ($companyKey -ne $priorCompanyKey)
    $titleNormalized = (($Title.ToLowerInvariant() -replace '[^a-z0-9]+', ' ').Trim() -replace '\s+', ' ')
    $titleKey = (($titleNormalized.Split(' ', [StringSplitOptions]::RemoveEmptyEntries) | Sort-Object) -join ' ')
    if ($companyKey -and $titleKey) { return "$companyKey|$titleKey" }
    return "job:$JobId"
}

function Test-AssessmentMalformed($Assessment, $Fit, [bool]$AssessmentFileExists) {
    if ($AssessmentFileExists -and $null -eq $Assessment) { return $true }
    if ($null -eq $Assessment) { return $false }
    if (-not (Has-Property $Assessment 'status')) { return $true }
    if ([string]$Assessment.status -notin @('pending','passed','needs-research','needs-evidence','failed')) { return $true }
    if ([string]$Assessment.status -ne 'pending') {
        foreach ($required in @('score','trust_class','role_family','eligibility_state','hard_gates','needs_external_research','needs_candidate_evidence')) {
            if (-not (Has-Property $Assessment $required)) { return $true }
        }
        foreach ($gate in @('integrity','eligibility','role_family','mandatory_requirements','truth_feasibility')) {
            if (-not (Has-Property $Assessment.hard_gates $gate) -or $Assessment.hard_gates.$gate -isnot [bool]) { return $true }
        }
        if ($Assessment.needs_external_research -isnot [bool] -or $Assessment.needs_candidate_evidence -isnot [bool]) { return $true }
    }
    if ([string]$Assessment.status -eq 'passed') {
        if (-not (Has-Property $Assessment 'hard_gates')) { return $true }
        foreach ($gate in @('integrity','eligibility','role_family','mandatory_requirements','truth_feasibility')) {
            if (-not (Has-Property $Assessment.hard_gates $gate)) { return $true }
            if ($Assessment.hard_gates.$gate -isnot [bool]) { return $true }
            if (-not [bool]$Assessment.hard_gates.$gate) { return $true }
        }
        if ($null -eq $Fit -or -not (Has-Property $Fit 'status') -or [string]$Fit.status -notin @('complete','passed') -or -not (Has-Property $Fit 'score')) { return $true }
    }
    return $false
}

function Parse-Utc($Value) {
    if ($null -eq $Value) { return $null }
    try {
        if ($Value -is [DateTimeOffset]) { return $Value.ToUniversalTime() }
        if ($Value -is [DateTime]) { return ([DateTimeOffset]$Value).ToUniversalTime() }
        $text = [string]$Value
        if ([string]::IsNullOrWhiteSpace($text)) { return $null }
        return [DateTimeOffset]::Parse($text, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
    } catch { return $null }
}

function Get-ActiveClaim([string]$Directory, [string]$Stage) {
    if ([string]::IsNullOrWhiteSpace($Stage)) { return $null }
    $claim = Read-JsonSafe (Join-Path $Directory 'action-claim.json')
    if (-not $claim -or [string]$claim.stage -ne $Stage) { return $null }
    $expiresAt = Parse-Utc $claim.expires_at
    if ($null -eq $expiresAt -or $expiresAt -le [DateTimeOffset]::UtcNow) { return $null }
    return [ordered]@{
        stage = [string]$claim.stage
        owner_id = [string]$claim.owner_id
        acquired_at = $claim.acquired_at
        expires_at = $claim.expires_at
    }
}

function Test-TerminalProgress($Progress) {
    if ($null -eq $Progress) { return $false }
    if ((Has-Property $Progress 'terminal') -and [bool]$Progress.terminal) { return $true }
    foreach ($name in @('stage','status')) {
        if (-not (Has-Property $Progress $name)) { continue }
        $value = ([string]$Progress.$name).ToLowerInvariant()
        if ($value -match '^(terminal|complete|completed|blocked|failed|cancelled|abandoned|skipped)(-|$)') { return $true }
    }
    return $false
}

function Test-LedgerStatusBlocks([string]$Status) {
    if ([string]::IsNullOrWhiteSpace($Status) -or $Status -eq 'reopened-application') { return $false }
    return ($Status -eq 'submitted' -or $Status -eq 'failed' -or $Status -like 'skipped-*' -or $Status -like 'rejected*' -or $Status -like 'duplicate*' -or $Status -match 'blocked')
}

function Get-JobDomain($Job) {
    if ($null -eq $Job) { return '' }
    $url = if (Has-Property $Job 'job_url') { [string]$Job.job_url } else { '' }
    if (-not [string]::IsNullOrWhiteSpace($url)) {
        try {
            $hostName = ([Uri]$url).Host.ToLowerInvariant() -replace '^www\.', ''
            if ($hostName) { return $hostName }
        } catch {}
    }
    $source = if (Has-Property $Job 'source') { ([string]$Job.source).ToLowerInvariant() } else { '' }
    if ($source -match 'indeed') { return 'indeed.com' }
    if ($source -match 'linkedin') { return 'linkedin.com' }
    return ''
}

function Get-ActiveCircuitForDomain([string]$Domain) {
    if ([string]::IsNullOrWhiteSpace($Domain)) { return $null }
    if ($activeCircuitByDomain.ContainsKey($Domain)) { return $activeCircuitByDomain[$Domain] }
    foreach ($key in $activeCircuitByDomain.Keys) {
        if ($Domain.EndsWith(".$key", [StringComparison]::OrdinalIgnoreCase)) { return $activeCircuitByDomain[$key] }
    }
    return $null
}

function Get-LinkedInGovernorStatus {
    $script = Join-Path $PSScriptRoot 'linkedin-governor.ps1'
    try {
        return ((& $script -Action Status -Workspace $Workspace | Select-Object -Last 1) | ConvertFrom-Json)
    } catch {
        return [pscustomobject]@{
            easy_apply_allowed = $false
            easy_apply_submissions_last_hour = 0
            easy_apply_submissions_last_24h = 0
            next_easy_apply_at = $null
            block_reasons = @('governor-unavailable')
        }
    }
}

$activeCircuitByDomain = @{}
$circuitStatus = $null
try {
    $circuitScript = Join-Path $PSScriptRoot 'domain-circuit-breaker.ps1'
    $circuitStatus = ((& $circuitScript -Action Status -Workspace $Workspace | Select-Object -Last 1) | ConvertFrom-Json)
    foreach ($circuit in @($circuitStatus.circuits)) {
        if ($circuit.domain) { $activeCircuitByDomain[[string]$circuit.domain] = $circuit }
    }
} catch {
    $circuitStatus = [pscustomobject]@{ active=$false; circuits=@() }
}

$ledgerPath = Join-Path $root 'applications.jsonl'
$ledgerCount = 0
$submittedCount = 0
$submittedUnique = @{}
$submittedIds = @{}
$ledgerIds = @{}
$ledgerLastStatus = @{}
if (Test-Path -LiteralPath $ledgerPath) {
    foreach ($line in Get-Content -LiteralPath $ledgerPath) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $row = $line | ConvertFrom-Json
            $ledgerCount++
            $isSubmitted = ($row.status -eq 'submitted' -or $row.submitted -eq $true)
            if ($isSubmitted) {
                $submittedCount++
                $submissionKey = Get-SubmissionIdentity ([string]$row.company) ([string]$row.title) ([string]$row.job_id)
                $submittedUnique[$submissionKey] = $true
                if ($null -ne $row.job_id) { $submittedIds[[string]$row.job_id] = $true }
            }
            if ($null -ne $row.job_id) {
                $jid = [string]$row.job_id
                $ledgerLastStatus[$jid] = [string]$row.status
                if (Test-LedgerStatusBlocks ([string]$row.status)) { $ledgerIds[$jid] = $true } else { $ledgerIds.Remove($jid) | Out-Null }
            }
        } catch {}
    }
}

$generatedIds = @{}
$generatedRoot = Join-Path $root 'generated'
if (Test-Path -LiteralPath $generatedRoot) {
    foreach ($generatedDir in Get-ChildItem -LiteralPath $generatedRoot -Directory) {
        $generatedJob = Read-JsonSafe (Join-Path $generatedDir.FullName 'job.json')
        $generatedId = if ($generatedJob -and $generatedJob.job_id) { [string]$generatedJob.job_id } else { $generatedDir.Name.Split('-')[0] }
        if ($generatedId) { $generatedIds[$generatedId] = $true }
    }
}

$queue = @()
$queueRoot = Join-Path $root 'queue'
if (Test-Path -LiteralPath $queueRoot) {
    foreach ($dir in Get-ChildItem -LiteralPath $queueRoot -Directory) {
        $job = Read-JsonSafe (Join-Path $dir.FullName 'job.json')
        $assessmentPath = Join-Path $dir.FullName 'assessment.json'
        $assessmentFileExists = Test-Path -LiteralPath $assessmentPath
        $assessment = Read-JsonSafe $assessmentPath
        $fit = Read-JsonSafe (Join-Path $dir.FullName 'fit-map.json')
        $sourceMetadata = Read-JsonSafe (Join-Path $dir.FullName 'source-metadata.json')
        $sourceReady = Test-SourceReady (Join-Path $dir.FullName 'source.md')
        $assessmentMalformed = Test-AssessmentMalformed $assessment $fit $assessmentFileExists
        $recoverable = Read-JsonSafe (Join-Path $dir.FullName 'recoverable-error.json')
        $retryAfter = if ($recoverable -and $recoverable.retry_after) { Parse-Utc $recoverable.retry_after } else { $null }
        $recoverableDeferred = ($null -ne $retryAfter -and $retryAfter -gt [DateTimeOffset]::UtcNow)
        $id = if ($job -and $job.job_id) { [string]$job.job_id } else { $dir.Name.Split('-')[0] }
        $status = if ($assessmentMalformed) { 'malformed' } elseif ($assessment -and $assessment.status) { [string]$assessment.status } else { 'unassessed' }
        $already = ($submittedIds.ContainsKey($id) -or $ledgerIds.ContainsKey($id))
        $priorLedgerStatus = if ($ledgerLastStatus.ContainsKey($id)) { [string]$ledgerLastStatus[$id] } else { $null }
        $policyVersion = if ($assessment -and ($assessment.PSObject.Properties.Name -contains 'policy_version')) { [string]$assessment.policy_version } else { '' }
        $technicalPriorSkips = @('skipped-low-fit','skipped-mandatory-gate','skipped-stack-mismatch','skipped-role-family')
        # Do not reopen an old failed skip just because policy changed. But if a reassessment was already
        # Explicitly reopened technical skips may finish after restart.
        $explicitReassessment = ($job -and (Has-Property $job 'allow_after_prior_skip') -and [bool]$job.allow_after_prior_skip)
        $reassessmentInProgress = ($explicitReassessment -and $priorLedgerStatus -in $technicalPriorSkips -and $policyVersion -in @('5.10','5.11','5.12','5.13','5.14','5.15','6.0','6.1','6.2','6.3') -and $status -in @('needs-evidence','needs-research','passed'))
        $ledgerBlocks = ($submittedIds.ContainsKey($id) -or ($already -and -not $reassessmentInProgress))
        $shadowedByGenerated = $generatedIds.ContainsKey($id)
        $terminal = $status -in @('failed','rejected','skipped','submitted','blocked')
        $actionable = (-not $shadowedByGenerated -and -not $ledgerBlocks -and -not $terminal -and -not $recoverableDeferred)
        $stage = if ($shadowedByGenerated) { 'promoted_to_generated' } elseif ($recoverableDeferred) { 'recoverable_cooldown' } else { $null }
        $speed = if ($shadowedByGenerated -or $recoverableDeferred) { 'deferred' } else { $null }
        if ($actionable) {
            if (-not $sourceReady) {
                $stage = 'source_pending'; $speed = 'fast'
            } elseif ($status -eq 'malformed') {
                $stage = 'assessment_repair'; $speed = 'fast'
            } elseif ($status -in @('pending','unassessed','captured-awaiting-source-and-assessment')) {
                $stage = 'assessment_pending'; $speed = 'fast'
            } elseif ($status -eq 'needs-evidence') {
                $stage = 'candidate_evidence_pending'; $speed = 'slow'
            } elseif ($status -eq 'needs-research') {
                $stage = 'eligibility_research_pending'; $speed = 'slow'
            } elseif ($status -eq 'passed') {
                $stage = 'coordinator_adjudication_pending'; $speed = 'fast'
            } else {
                $stage = 'assessment_pending'; $speed = 'fast'
            }
        }
        $claim = if ($actionable) { Get-ActiveClaim $dir.FullName $stage } else { $null }
        $claimed = ($null -ne $claim)
        if ($claimed) { $actionable = $false; $speed = 'deferred' }
        $queue += [ordered]@{
            job_id = $id
            company = if ($job) { $job.company } else { $null }
            title = if ($job) { $job.title } else { $null }
            score = if ($fit) { $fit.score } elseif ($assessment) { $assessment.score } else { $null }
            quality_classification = if ($sourceMetadata -and $sourceMetadata.quality) { [string]$sourceMetadata.quality.classification } else { $null }
            reality_signal = [bool]($sourceMetadata -and $sourceMetadata.quality -and $sourceMetadata.quality.reality_signal)
            reality_evidence = if ($sourceMetadata -and $sourceMetadata.quality) { [string]$sourceMetadata.quality.evidence } else { $null }
            freehire_match_percent = if ($sourceMetadata -and $sourceMetadata.freehire -and $null -ne $sourceMetadata.freehire.match_percent) { [int]$sourceMetadata.freehire.match_percent } else { $null }
            actionable = $actionable
            stage = $stage
            speed = $speed
            claimed = $claimed
            claim = $claim
            path = $dir.FullName
            retry_after = if ($recoverableDeferred) { $retryAfter.ToString('o') } else { $null }
        }
    }
}

$generated = @()
if (Test-Path -LiteralPath $generatedRoot) {
    foreach ($dir in Get-ChildItem -LiteralPath $generatedRoot -Directory) {
        $job = Read-JsonSafe (Join-Path $dir.FullName 'job.json')
        $result = Read-JsonSafe (Join-Path $dir.FullName 'application-result.json')
        $progress = Read-JsonSafe (Join-Path $dir.FullName 'application-progress.json')
        $sendState = Read-JsonSafe (Join-Path $dir.FullName 'application-send-state.json')
        $route = Read-JsonSafe (Join-Path $dir.FullName 'application-route.json')
        $sourceMetadata = Read-JsonSafe (Join-Path $dir.FullName 'source-metadata.json')
        $artifact = Read-JsonSafe (Join-Path $dir.FullName 'resume-artifact.json')
        $recoverable = Read-JsonSafe (Join-Path $dir.FullName 'recoverable-error.json')
        $retryAfter = if ($recoverable -and $recoverable.retry_after) { Parse-Utc $recoverable.retry_after } else { $null }
        $recoverableDeferred = ($null -ne $retryAfter -and $retryAfter -gt [DateTimeOffset]::UtcNow)
        $id = if ($job -and $job.job_id) { [string]$job.job_id } else { $dir.Name.Split('-')[0] }
        $priorLedgerStatus = if ($ledgerLastStatus.ContainsKey($id)) { [string]$ledgerLastStatus[$id] } else { $null }
        $allowAfterPriorSkip = ($job -and ($job.PSObject.Properties.Name -contains 'allow_after_prior_skip') -and [bool]$job.allow_after_prior_skip -and $priorLedgerStatus -in @('skipped-low-fit','skipped-mandatory-gate','skipped-stack-mismatch','skipped-role-family'))
        $already = ($submittedIds.ContainsKey($id) -or ($ledgerIds.ContainsKey($id) -and -not $allowAfterPriorSkip))
        $resultStatus = if ($result -and $result.status) { [string]$result.status } else { $null }
        $linkedinHandoff = ($resultStatus -eq 'handoff-easy-apply')
        $needsReconcile = (($null -ne $result) -and -not $linkedinHandoff -and -not $already)
        # blocked-unknown-fact remains terminal for legacy rows only. V6.3 workers never create it.
        $terminalResult = $resultStatus -in @('submitted','blocked-auth','blocked-security','blocked-automation','blocked-domain-circuit-breaker','blocked-identity-mismatch','blocked-work-auth','blocked-protected-fact','blocked-unknown-fact','blocked-technical','blocked-verification-unresolved','skipped-ineligible','skipped-duplicate','skipped-job-quality','failed')
        $resumeReady = ($artifact -and [string]$artifact.status -eq 'ready-for-upload' -and $artifact.path -and (Test-Path -LiteralPath ([string]$artifact.path)))
        $jobDomain = Get-JobDomain $job
        $domainCircuit = Get-ActiveCircuitForDomain $jobDomain
        $circuitBlocked = ($null -ne $domainCircuit)
        $sendStatus = if ($sendState -and $sendState.status) { [string]$sendState.status } else { $null }
        $needsSendVerification = $sendStatus -in @('reserved','verification-required')
        $verificationQuarantined = ($sendStatus -eq 'verification-quarantined')
        $terminalProgressWithoutResult = ($null -eq $result -and (Test-TerminalProgress $progress))
        $needsOutcomeRepair = ($null -eq $result -and ($terminalProgressWithoutResult -or $sendStatus -in @('submitted','abandoned-unknown-outcome')))
        $verificationRetryAfter = if ($sendState -and $sendState.verification_retry_after) { Parse-Utc $sendState.verification_retry_after } else { $null }
        $verificationGraceDeferred = ($needsSendVerification -and $null -ne $verificationRetryAfter -and $verificationRetryAfter -gt [DateTimeOffset]::UtcNow)
        $routeName = if ($route -and $route.route) { [string]$route.route } elseif ($sendState -and $sendState.channel) { if ([string]$sendState.channel -eq 'external-ats') { 'external' } else { [string]$sendState.channel } } else { '' }
        $emailRoute = ($routeName -eq 'email' -and (($route -and $route.target) -or ($sendState -and $sendState.target)))
        $linkedinRoute = ($routeName -eq 'linkedin-easy-apply')
        $knownRoute = ($routeName -in @('external','linkedin-easy-apply','email'))
        $actionable = (-not $already -and -not $needsReconcile -and -not $terminalResult -and -not $verificationQuarantined -and -not $recoverableDeferred -and -not $verificationGraceDeferred -and -not $circuitBlocked)
        $stage = if ($verificationQuarantined) { 'application_verification_quarantined' } elseif ($circuitBlocked) { 'domain_circuit_breaker' } elseif ($recoverableDeferred) { 'recoverable_cooldown' } elseif ($verificationGraceDeferred) { 'verification_grace' } else { $null }
        if ($needsReconcile) { $stage = 'reconcile_result' }
        elseif ($verificationQuarantined) { $stage = 'application_verification_quarantined' }
        elseif ($actionable -and $needsOutcomeRepair) { $stage = 'application_outcome_repair' }
        elseif ($actionable -and $needsSendVerification) { $stage = 'application_verification' }
        elseif ($actionable -and -not $knownRoute) { $stage = 'route_pending' }
        elseif ($actionable -and -not $resumeReady) { $stage = 'resume_pending' }
        elseif ($actionable -and ($linkedinHandoff -or $linkedinRoute)) { $stage = 'linkedin_application_ready' }
        elseif ($actionable -and $emailRoute) { $stage = 'email_application_ready' }
        elseif ($actionable -and $null -ne $progress) { $stage = 'application_resume' }
        elseif ($actionable -and $resumeReady) { $stage = 'application_ready' }
        $claim = if ($actionable -or $needsReconcile) { Get-ActiveClaim $dir.FullName $stage } else { $null }
        $claimed = ($null -ne $claim)
        if ($claimed) { $actionable = $false }
        $generated += [ordered]@{
            job_id = $id
            company = if ($job) { $job.company } else { $null }
            title = if ($job) { $job.title } else { $null }
            source = if ($job) { $job.source } else { $null }
            domain = $jobDomain
            route = if ($knownRoute) { $routeName } else { 'pending' }
            quality_classification = if ($sourceMetadata -and $sourceMetadata.quality) { [string]$sourceMetadata.quality.classification } else { $null }
            reality_signal = [bool]($sourceMetadata -and $sourceMetadata.quality -and $sourceMetadata.quality.reality_signal)
            reality_evidence = if ($sourceMetadata -and $sourceMetadata.quality) { [string]$sourceMetadata.quality.evidence } else { $null }
            freehire_match_percent = if ($sourceMetadata -and $sourceMetadata.freehire -and $null -ne $sourceMetadata.freehire.match_percent) { [int]$sourceMetadata.freehire.match_percent } else { $null }
            actionable = $actionable
            needs_reconcile = $needsReconcile
            reconcile_actionable = ($needsReconcile -and -not $claimed)
            stage = $stage
            speed = if ($recoverableDeferred -or $verificationGraceDeferred -or $circuitBlocked -or $verificationQuarantined -or $claimed) { 'deferred' } else { 'fast' }
            claimed = $claimed
            claim = $claim
            quarantine_reason = if ($verificationQuarantined) { [string]$sendState.quarantine_reason } else { $null }
            path = $dir.FullName
            retry_after = if ($circuitBlocked) { $domainCircuit.expires_at } elseif ($recoverableDeferred) { $retryAfter.ToString('o') } elseif ($verificationGraceDeferred) { $verificationRetryAfter.ToString('o') } else { $null }
        }
    }
}

$reconcile = @($generated | Where-Object { $_.reconcile_actionable })
$generatedActionable = @($generated | Where-Object { $_.actionable })
$queueActionable = @($queue | Where-Object { $_.actionable })
$discoveryClaimRaw = Read-JsonSafe (Join-Path $root 'discovery-action-claim.json')
$discoveryClaimExpires = if ($discoveryClaimRaw -and $discoveryClaimRaw.expires_at) { Parse-Utc $discoveryClaimRaw.expires_at } else { $null }
$discoveryClaim = if ($discoveryClaimRaw -and [string]$discoveryClaimRaw.stage -eq 'discovery' -and $null -ne $discoveryClaimExpires -and $discoveryClaimExpires -gt [DateTimeOffset]::UtcNow) {
    [ordered]@{ stage='discovery'; owner_id=[string]$discoveryClaimRaw.owner_id; acquired_at=$discoveryClaimRaw.acquired_at; expires_at=$discoveryClaimRaw.expires_at }
} else { $null }
$claimedWorkCount = @($queue | Where-Object { $_.claimed }).Count + @($generated | Where-Object { $_.claimed }).Count

# V6 throughput contract: expose the whole runnable pipeline, not only the first
# non-empty bucket.  The coordinator cannot dispatch concurrent workers for work it
# cannot see, and the former generated > queue > discover selection starved both
# assessment batches and discovery whenever one generated job existed.
$stagePriority = @{
    reconcile_result = 10
    application_outcome_repair = 15
    application_verification = 20
    linkedin_application_ready = 25
    email_application_ready = 30
    application_resume = 40
    application_ready = 40
    resume_pending = 50
    coordinator_adjudication_pending = 60
    assessment_repair = 60
    reassessment_pending = 70
    assessment_pending = 70
    source_pending = 80
    route_pending = 35
    eligibility_research_pending = 90
    candidate_evidence_pending = 90
}

$selected = @($reconcile) + @($generatedActionable) + @($queueActionable)
$selected = @($selected | Sort-Object `
    @{Expression={ if ($stagePriority.ContainsKey([string]$_.stage)) { $stagePriority[[string]$_.stage] } else { 999 } }}, `
    @{Expression={ if ($_.speed -eq 'fast') { 0 } elseif ($_.speed -eq 'slow') { 1 } else { 2 } }}, `
    @{Expression={ if ($null -ne $_.freehire_match_percent) { -[int]$_.freehire_match_percent } else { 1 } }}, `
    @{Expression={ $_.job_id }})
$nextAction = if ($reconcile.Count -gt 0) {
    'reconcile'
} elseif ($generatedActionable.Count -gt 0) {
    'resume-generated'
} elseif ($queueActionable.Count -gt 0) {
    'process-queue'
} else {
    $null
}

function Get-DispatchTarget($Item) {
    $stage = [string]$Item.stage
    if ($stage -eq 'reconcile_result' -or $stage -in @('coordinator_adjudication_pending','assessment_repair')) { return 'coordinator-local' }
    if ($stage -eq 'resume_pending') { return 'job-autopilot-resume' }
    if ($stage -in @('assessment_pending','reassessment_pending')) { return 'job-autopilot-assessor' }
    if ($stage -in @('eligibility_research_pending','candidate_evidence_pending')) { return 'job-autopilot-research' }
    if ($stage -in @('source_pending','route_pending')) { return 'coordinator-browser' }
    if ($stage -eq 'email_application_ready') { return 'job-autopilot-email-apply' }
    if ($stage -eq 'linkedin_application_ready') { return 'coordinator-linkedin' }
    if ($stage -in @('application_ready','application_resume','application_verification','application_outcome_repair')) {
        if ([string]$Item.route -eq 'email') { return 'job-autopilot-email-apply' }
        if ([string]$Item.route -eq 'linkedin-easy-apply') { return 'coordinator-linkedin' }
        if ([string]$Item.route -eq 'pending') { return 'coordinator-browser' }
        return 'job-autopilot-external-apply'
    }
    return 'coordinator'
}

$actions = @($selected | ForEach-Object {
    $dispatch = Get-DispatchTarget $_
    $action = [ordered]@{
        job_id = $_.job_id
        company = $_.company
        title = $_.title
        stage = $_.stage
        speed = $_.speed
        wave = if ($_.speed -eq 'slow') { 'research' } else { 'fast' }
        quality_classification = $_.quality_classification
        reality_signal = [bool]$_.reality_signal
        reality_evidence = $_.reality_evidence
        freehire_match_percent = $_.freehire_match_percent
        dispatch = $dispatch
        priority = if ($stagePriority.ContainsKey([string]$_.stage)) { $stagePriority[[string]$_.stage] } else { 999 }
        path = $_.path
    }
    if ($dispatch -like 'job-autopilot-*') {
        $action['worker_prompt'] = "Work item directory: $($_.path)`nAction: $($_.stage)"
    }
    $action
})

$pipelineBufferTarget = 8
$pipelineDepth = @($generated | Where-Object { ($_.actionable -or $_.claimed -or $_.needs_reconcile) -and $_.stage -ne 'application_verification_quarantined' }).Count + @($queue | Where-Object { ($_.actionable -or $_.claimed) -and $_.stage -ne 'source_pending' }).Count
$discoverySlots = [Math]::Max(0, $pipelineBufferTarget - $pipelineDepth)
if ($null -eq $nextAction) {
    $nextAction = if ($discoverySlots -gt 0 -and $null -eq $discoveryClaim) { 'discover' } else { 'await-active-claims' }
}
$concurrency = [ordered]@{
    default = 'unbounded'
    linkedin_easy_apply = 1
}
$activeWave = if (@($actions | Where-Object { $_.wave -eq 'fast' }).Count -gt 0) { 'fast' } elseif (@($actions | Where-Object { $_.wave -eq 'research' }).Count -gt 0) { 'research' } else { 'none' }

$circuitPath = Join-Path $root 'domain-circuit-breakers.jsonl'
$circuitCount = 0
if (Test-Path -LiteralPath $circuitPath) {
    foreach ($line in Get-Content -LiteralPath $circuitPath) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $line | ConvertFrom-Json | Out-Null; $circuitCount++ } catch {}
    }
}
$linkedinStatus = Get-LinkedInGovernorStatus
$claimMetadata = @(
    @($queue | Where-Object { $_.claimed } | ForEach-Object { [ordered]@{ scope='work-item'; job_id=$_.job_id; stage=$_.stage; path=$_.path; owner_id=$_.claim.owner_id; acquired_at=$_.claim.acquired_at; expires_at=$_.claim.expires_at } }) +
    @($generated | Where-Object { $_.claimed } | ForEach-Object { [ordered]@{ scope='work-item'; job_id=$_.job_id; stage=$_.stage; path=$_.path; owner_id=$_.claim.owner_id; acquired_at=$_.claim.acquired_at; expires_at=$_.claim.expires_at } })
)
if ($null -ne $discoveryClaim) {
    $claimMetadata += [ordered]@{ scope='discovery'; job_id=$null; stage='discovery'; path=$root; owner_id=$discoveryClaim.owner_id; acquired_at=$discoveryClaim.acquired_at; expires_at=$discoveryClaim.expires_at }
}
$quarantinedApplications = @($generated | Where-Object { $_.stage -eq 'application_verification_quarantined' } | ForEach-Object {
    [ordered]@{ job_id=$_.job_id; company=$_.company; title=$_.title; route=$_.route; stage=$_.stage; blocker=$_.quarantine_reason; path=$_.path }
})

$out = [ordered]@{
    workspace = $Workspace
    next_action = $nextAction
    actions = $actions
    claims = $claimMetadata
    quarantined_applications = $quarantinedApplications
    scheduler = [ordered]@{
        mode = 'parallel-pipeline'
        active_wave = $activeWave
        pipeline_buffer_target = $pipelineBufferTarget
        pipeline_depth = $pipelineDepth
        discovery_needed = ($discoverySlots -gt 0 -and $null -eq $discoveryClaim)
        discovery_slots = $discoverySlots
        discovery_claim = $discoveryClaim
        concurrency = $concurrency
    }
    summary = [ordered]@{
        decisions = $ledgerCount
        submitted = $submittedUnique.Count
        submitted_unique = $submittedUnique.Count
        submitted_rows = $submittedCount
        fast_actions = @($actions | Where-Object { $_.wave -eq 'fast' }).Count
        research_actions = @($actions | Where-Object { $_.wave -eq 'research' }).Count
        queue_actionable = $queueActionable.Count
        queue_fast = @($queueActionable | Where-Object { $_.speed -eq 'fast' }).Count
        queue_slow = @($queueActionable | Where-Object { $_.speed -eq 'slow' }).Count
        queue_deferred = @($queue | Where-Object { $_.stage -eq 'recoverable_cooldown' }).Count
        queue_source_pending = @($queue | Where-Object { $_.stage -eq 'source_pending' }).Count
        generated_actionable = $generatedActionable.Count
        generated_deferred = @($generated | Where-Object { $_.stage -eq 'recoverable_cooldown' }).Count
        generated_verification_deferred = @($generated | Where-Object { $_.stage -eq 'verification_grace' }).Count
        application_verification_quarantined = @($generated | Where-Object { $_.stage -eq 'application_verification_quarantined' }).Count
        application_outcome_repair = @($generated | Where-Object { $_.stage -eq 'application_outcome_repair' }).Count
        claims_active = $claimedWorkCount + $(if ($null -ne $discoveryClaim) { 1 } else { 0 })
        generated_circuit_blocked = @($generated | Where-Object { $_.stage -eq 'domain_circuit_breaker' }).Count
        reconcile = $reconcile.Count
        circuit_breaker_events = $circuitCount
        circuit_breakers_active = @($circuitStatus.circuits).Count
    }
    linkedin = [ordered]@{
        easy_apply_allowed = $linkedinStatus.easy_apply_allowed
        last_hour = $linkedinStatus.easy_apply_submissions_last_hour
        last_24h = $linkedinStatus.easy_apply_submissions_last_24h
        next_at = $linkedinStatus.next_easy_apply_at
        blocked = @($linkedinStatus.block_reasons).Count -gt 0
    }
    instruction = if ($nextAction -eq 'await-active-claims') {
        'No unclaimed action is currently available. Rerun state after active claims finish or expire.'
    } elseif ($nextAction -eq 'discover') {
        "Discover a batch of $pipelineBufferTarget source-ready plausible jobs before returning to state."
    } elseif ($discoverySlots -gt 0) {
        "Group fast actions by dispatch and emit every non-LinkedIn Task call together up to runtime capacity; then run the separate research wave. Refill $discoverySlots pipeline slot(s) after ready work."
    } else {
        'Group fast actions by dispatch and emit every non-LinkedIn Task call together up to runtime capacity. Run web-heavy research as a separate wave. LinkedIn Easy Apply remains serial.'
    }
}
if ($Compact) {
    $compactActions = @($actions | ForEach-Object {
        $item = [ordered]@{
            job_id = $_.job_id
            company = $_.company
            title = $_.title
            stage = $_.stage
            wave = $_.wave
            dispatch = $_.dispatch
            priority = $_.priority
            freehire_match_percent = $_.freehire_match_percent
        }
        if ($_.worker_prompt) { $item['worker_prompt'] = $_.worker_prompt }
        elseif ($_.path) { $item['path'] = $_.path }
        $item
    })
    [ordered]@{
        workspace = $Workspace
        next_action = $nextAction
        actions = $compactActions
        claims = @($claimMetadata | ForEach-Object { [ordered]@{scope=$_.scope;job_id=$_.job_id;stage=$_.stage;owner_id=$_.owner_id;expires_at=$_.expires_at} })
        quarantined_applications = $quarantinedApplications
        scheduler = $out.scheduler
        summary = [ordered]@{
            submitted_unique = $out.summary.submitted_unique
            fast_actions = $out.summary.fast_actions
            research_actions = $out.summary.research_actions
            claims_active = $out.summary.claims_active
            reconcile = $out.summary.reconcile
            application_verification_quarantined = $out.summary.application_verification_quarantined
        }
        linkedin = $out.linkedin
        instruction = $out.instruction
    } | ConvertTo-Json -Depth 6
} else {
    $out | ConvertTo-Json -Depth 6
}
