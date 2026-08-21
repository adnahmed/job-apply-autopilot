[CmdletBinding()]
param([string]$Workspace = (Get-Location).Path)

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
    $titleKey = (($Title.ToLowerInvariant() -replace '[^a-z0-9]+', ' ').Trim() -replace '\s+', ' ')
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
            }
            if ($null -ne $row.job_id) {
                $jid = [string]$row.job_id
                $ledgerIds[$jid] = $true
                $ledgerLastStatus[$jid] = [string]$row.status
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
        $sourceReady = Test-SourceReady (Join-Path $dir.FullName 'source.md')
        $assessmentMalformed = Test-AssessmentMalformed $assessment $fit $assessmentFileExists
        $recoverable = Read-JsonSafe (Join-Path $dir.FullName 'recoverable-error.json')
        $retryAfter = if ($recoverable -and $recoverable.retry_after) { Parse-Utc $recoverable.retry_after } else { $null }
        $recoverableDeferred = ($null -ne $retryAfter -and $retryAfter -gt [DateTimeOffset]::UtcNow)
        $id = if ($job -and $job.job_id) { [string]$job.job_id } else { $dir.Name.Split('-')[0] }
        $status = if ($assessmentMalformed) { 'malformed' } elseif ($assessment -and $assessment.status) { [string]$assessment.status } else { 'unassessed' }
        $already = $ledgerIds.ContainsKey($id)
        $priorLedgerStatus = if ($ledgerLastStatus.ContainsKey($id)) { [string]$ledgerLastStatus[$id] } else { $null }
        $policyVersion = if ($assessment -and ($assessment.PSObject.Properties.Name -contains 'policy_version')) { [string]$assessment.policy_version } else { '' }
        $technicalPriorSkips = @('skipped-low-fit','skipped-mandatory-gate','skipped-stack-mismatch','skipped-role-family')
        # Do not reopen an old failed skip just because policy changed. But if a reassessment was already
        # explicitly started under 5.10/5.11, allow that in-progress/passed item to finish after restart.
        $explicitReassessment = ($job -and (Has-Property $job 'allow_after_prior_skip') -and [bool]$job.allow_after_prior_skip)
        $reassessmentInProgress = ($explicitReassessment -and $priorLedgerStatus -in $technicalPriorSkips -and $policyVersion -in @('5.10','5.11','5.12','5.13','5.14') -and $status -in @('needs-evidence','needs-research','passed'))
        $ledgerBlocks = ($already -and -not $reassessmentInProgress)
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
                $candidateEvidencePath = Join-Path $dir.FullName 'candidate-evidence-research.json'
                if (Test-Path -LiteralPath $candidateEvidencePath) { $stage = 'reassessment_pending'; $speed = 'fast' }
                else { $stage = 'candidate_evidence_pending'; $speed = 'slow' }
            } elseif ($status -eq 'needs-research') {
                $eligibilityPath = Join-Path $dir.FullName 'eligibility-research.json'
                if (Test-Path -LiteralPath $eligibilityPath) { $stage = 'reassessment_pending'; $speed = 'fast' }
                else { $stage = 'eligibility_research_pending'; $speed = 'slow' }
            } elseif ($status -eq 'passed') {
                $stage = 'coordinator_adjudication_pending'; $speed = 'fast'
            } else {
                $stage = 'assessment_pending'; $speed = 'fast'
            }
        }
        $queue += [ordered]@{
            job_id = $id
            company = if ($job) { $job.company } else { $null }
            title = if ($job) { $job.title } else { $null }
            score = if ($fit) { $fit.score } elseif ($assessment) { $assessment.score } else { $null }
            actionable = $actionable
            stage = $stage
            speed = $speed
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
        $artifact = Read-JsonSafe (Join-Path $dir.FullName 'resume-artifact.json')
        $recoverable = Read-JsonSafe (Join-Path $dir.FullName 'recoverable-error.json')
        $retryAfter = if ($recoverable -and $recoverable.retry_after) { Parse-Utc $recoverable.retry_after } else { $null }
        $recoverableDeferred = ($null -ne $retryAfter -and $retryAfter -gt [DateTimeOffset]::UtcNow)
        $id = if ($job -and $job.job_id) { [string]$job.job_id } else { $dir.Name.Split('-')[0] }
        $priorLedgerStatus = if ($ledgerLastStatus.ContainsKey($id)) { [string]$ledgerLastStatus[$id] } else { $null }
        $allowAfterPriorSkip = ($job -and ($job.PSObject.Properties.Name -contains 'allow_after_prior_skip') -and [bool]$job.allow_after_prior_skip -and $priorLedgerStatus -in @('skipped-low-fit','skipped-mandatory-gate','skipped-stack-mismatch','skipped-role-family'))
        $already = ($ledgerIds.ContainsKey($id) -and -not $allowAfterPriorSkip)
        $resultStatus = if ($result -and $result.status) { [string]$result.status } else { $null }
        $needsReconcile = (($null -ne $result) -and -not $already)
        $terminalResult = $resultStatus -in @('submitted','handoff-easy-apply','blocked-auth','blocked-security','blocked-automation','blocked-domain-circuit-breaker','blocked-identity-mismatch','blocked-work-auth','blocked-unknown-fact','blocked-technical','skipped-ineligible','failed')
        $resumeReady = ($null -ne $artifact)
        $jobDomain = Get-JobDomain $job
        $domainCircuit = Get-ActiveCircuitForDomain $jobDomain
        $circuitBlocked = ($null -ne $domainCircuit)
        $sendStatus = if ($sendState -and $sendState.status) { [string]$sendState.status } else { $null }
        $needsSendVerification = $sendStatus -in @('reserved','verification-required','submitted')
        $emailRoute = ($route -and [string]$route.route -eq 'email' -and $route.target)
        $actionable = (-not $already -and -not $needsReconcile -and -not $terminalResult -and -not $recoverableDeferred -and -not $circuitBlocked)
        $stage = if ($circuitBlocked) { 'domain_circuit_breaker' } elseif ($recoverableDeferred) { 'recoverable_cooldown' } else { $null }
        if ($needsReconcile) { $stage = 'reconcile_result' }
        elseif ($actionable -and -not $resumeReady) { $stage = 'resume_pending' }
        elseif ($actionable -and $needsSendVerification) { $stage = 'application_verification' }
        elseif ($actionable -and $emailRoute) { $stage = 'email_application_ready' }
        elseif ($actionable -and $null -ne $progress) { $stage = 'application_resume' }
        elseif ($actionable -and $resumeReady) { $stage = 'application_ready' }
        $generated += [ordered]@{
            job_id = $id
            company = if ($job) { $job.company } else { $null }
            title = if ($job) { $job.title } else { $null }
            source = if ($job) { $job.source } else { $null }
            domain = $jobDomain
            actionable = $actionable
            needs_reconcile = $needsReconcile
            stage = $stage
            speed = if ($recoverableDeferred -or $circuitBlocked) { 'deferred' } else { 'fast' }
            path = $dir.FullName
            retry_after = if ($circuitBlocked) { $domainCircuit.expires_at } elseif ($recoverableDeferred) { $retryAfter.ToString('o') } else { $null }
        }
    }
}

$reconcile = @($generated | Where-Object { $_.needs_reconcile })
$generatedActionable = @($generated | Where-Object { $_.actionable })
$queueActionable = @($queue | Where-Object { $_.actionable } | Sort-Object @{Expression={ if ($_.speed -eq 'fast') {0} else {1} }}, @{Expression={ $_.job_id }})

if ($reconcile.Count -gt 0) {
    $nextAction = 'reconcile'; $selected = $reconcile
} elseif ($generatedActionable.Count -gt 0) {
    $nextAction = 'resume-generated'; $selected = $generatedActionable
} elseif ($queueActionable.Count -gt 0) {
    $nextAction = 'process-queue'; $selected = $queueActionable
} else {
    $nextAction = 'discover'; $selected = @()
}

$actions = @($selected | ForEach-Object {
    [ordered]@{
        job_id = $_.job_id
        company = $_.company
        title = $_.title
        stage = $_.stage
        speed = $_.speed
        path = $_.path
    }
})

$circuitPath = Join-Path $root 'domain-circuit-breakers.jsonl'
$circuitCount = 0
if (Test-Path -LiteralPath $circuitPath) {
    foreach ($line in Get-Content -LiteralPath $circuitPath) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $line | ConvertFrom-Json | Out-Null; $circuitCount++ } catch {}
    }
}
$linkedinStatus = Get-LinkedInGovernorStatus

$out = [ordered]@{
    workspace = $Workspace
    next_action = $nextAction
    actions = $actions
    summary = [ordered]@{
        decisions = $ledgerCount
        submitted = $submittedUnique.Count
        submitted_unique = $submittedUnique.Count
        submitted_rows = $submittedCount
        queue_actionable = $queueActionable.Count
        queue_fast = @($queueActionable | Where-Object { $_.speed -eq 'fast' }).Count
        queue_slow = @($queueActionable | Where-Object { $_.speed -eq 'slow' }).Count
        queue_deferred = @($queue | Where-Object { $_.stage -eq 'recoverable_cooldown' }).Count
        queue_source_pending = @($queue | Where-Object { $_.stage -eq 'source_pending' }).Count
        generated_actionable = $generatedActionable.Count
        generated_deferred = @($generated | Where-Object { $_.stage -eq 'recoverable_cooldown' }).Count
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
    instruction = if ($nextAction -eq 'discover') {
        'Discover now.'
    } elseif (@($queueActionable | Where-Object { $_.stage -eq 'source_pending' }).Count -gt 0) {
        'Capture source_pending JDs before assessment. Do other ready work while BrowserOS is unavailable.'
    } else {
        'Do fast actions first. Do not batch slow research with ready/fast work.'
    }
}
$out | ConvertTo-Json -Depth 6
