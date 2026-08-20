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

function Parse-Utc([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    try { return [DateTimeOffset]::Parse($Value).ToUniversalTime() } catch { return $null }
}

function Get-LinkedInGovernorStatus([array]$BootstrapSubmissions) {
    $maxHour = 4
    $max24 = 20
    $minSpacing = 600
    $now = [DateTimeOffset]::UtcNow
    $state = Read-JsonSafe (Join-Path $root 'linkedin-activity-state.json')
    $submissions = @()
    $manualBlock = $false
    $pauseUntil = $null
    $pauseReason = $null
    $lastSignal = $null
    if ($state) {
        $manualBlock = [bool]$state.manual_block
        $pauseUntil = Parse-Utc ([string]$state.pause_until)
        $pauseReason = $state.pause_reason
        $lastSignal = $state.last_signal_type
        foreach ($x in @($state.easy_apply_submissions)) {
            $dt = Parse-Utc ([string]$x)
            if ($null -ne $dt -and $dt -gt $now.AddHours(-24)) { $submissions += $dt }
        }
    } else {
        foreach ($x in @($BootstrapSubmissions)) {
            $dt = Parse-Utc ([string]$x)
            if ($null -ne $dt -and $dt -gt $now.AddHours(-24)) { $submissions += $dt }
        }
    }
    $lastHour = @($submissions | Sort-Object -Unique | Where-Object { $_ -gt $now.AddHours(-1) })
    $submissions = @($submissions | Sort-Object -Unique)
    $next = $now
    $reasons = @()
    if ($manualBlock) { $reasons += 'manual-block' }
    if ($null -ne $pauseUntil -and $pauseUntil -gt $next) { $next = $pauseUntil; $reasons += 'signal-cooldown' }
    if ($submissions.Count -gt 0) {
        $last = ($submissions | Sort-Object)[-1]
        $candidate = $last.AddSeconds($minSpacing)
        if ($candidate -gt $next) { $next = $candidate }
        if ($candidate -gt $now) { $reasons += 'minimum-spacing' }
    }
    if ($lastHour.Count -ge $maxHour) {
        $candidate = (($lastHour | Sort-Object)[0]).AddHours(1)
        if ($candidate -gt $next) { $next = $candidate }
        $reasons += 'rolling-hour-limit'
    }
    if ($submissions.Count -ge $max24) {
        $candidate = (($submissions | Sort-Object)[0]).AddHours(24)
        if ($candidate -gt $next) { $next = $candidate }
        $reasons += 'rolling-24h-limit'
    }
    $allowed = (-not $manualBlock -and $next -le $now)
    return [ordered]@{
        easy_apply_allowed = $allowed
        submissions_last_hour = $lastHour.Count
        submissions_last_24h = $submissions.Count
        next_easy_apply_at = if ($allowed) { $now.ToString('o') } elseif ($manualBlock) { $null } else { $next.ToString('o') }
        block_reasons = @($reasons | Select-Object -Unique)
        pause_reason = $pauseReason
        last_signal_type = $lastSignal
        external_applications_restricted = $false
    }
}

$ledgerPath = Join-Path $root 'applications.jsonl'
$ledgerCount = 0
$submittedCount = 0
$ledgerIds = @{}
$ledgerLastStatus = @{}
$ledgerEasyApplySubmissions = @()
if (Test-Path -LiteralPath $ledgerPath) {
    foreach ($line in Get-Content -LiteralPath $ledgerPath) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $row = $line | ConvertFrom-Json
            $ledgerCount++
            $isSubmitted = ($row.status -eq 'submitted' -or $row.submitted -eq $true)
            if ($isSubmitted) { $submittedCount++ }
            if ($isSubmitted -and ([string]$row.source) -match 'linkedin.*easy.*apply' -and $row.timestamp) { $ledgerEasyApplySubmissions += [string]$row.timestamp }
            if ($null -ne $row.job_id) { $jid = [string]$row.job_id; $ledgerIds[$jid] = $true; $ledgerLastStatus[$jid] = [string]$row.status }
        } catch {}
    }
}

$queue = @()
$queueRoot = Join-Path $root 'queue'
if (Test-Path -LiteralPath $queueRoot) {
    foreach ($dir in Get-ChildItem -LiteralPath $queueRoot -Directory) {
        $job = Read-JsonSafe (Join-Path $dir.FullName 'job.json')
        $assessment = Read-JsonSafe (Join-Path $dir.FullName 'assessment.json')
        $fit = Read-JsonSafe (Join-Path $dir.FullName 'fit-map.json')
        $eligibilityPath = Join-Path $dir.FullName 'eligibility-research.json'
        $hasEligibilityResearch = Test-Path -LiteralPath $eligibilityPath
        $candidateEvidencePath = Join-Path $dir.FullName 'candidate-evidence-research.json'
        $hasCandidateEvidence = Test-Path -LiteralPath $candidateEvidencePath
        $id = if ($job -and $job.job_id) { [string]$job.job_id } else { $dir.Name.Split('-')[0] }
        $status = if ($assessment -and $assessment.status) { [string]$assessment.status } else { 'unassessed' }
        $already = $ledgerIds.ContainsKey($id)
        $priorLedgerStatus = if ($ledgerLastStatus.ContainsKey($id)) { [string]$ledgerLastStatus[$id] } else { $null }
        $policyVersion = if ($assessment -and ($assessment.PSObject.Properties.Name -contains 'policy_version')) { [string]$assessment.policy_version } else { '' }
        $oldPolicy = ($policyVersion -ne '5.10')
        $integrityPassed = ($assessment -and [bool]$assessment.hard_gates.integrity)
        $eligibilityPassed = ($assessment -and [bool]$assessment.hard_gates.eligibility)
        $technicalGateFailed = ($assessment -and ((-not [bool]$assessment.hard_gates.mandatory_requirements) -or (-not [bool]$assessment.hard_gates.truth_feasibility) -or (-not [bool]$assessment.hard_gates.role_family)))
        $technicalLedgerStatuses = @('skipped-low-fit','skipped-mandatory-gate','skipped-stack-mismatch','skipped-role-family')
        $ledgerAllowsPolicyReassessment = (-not $already -or $priorLedgerStatus -in $technicalLedgerStatuses)
        $policyReassessment = ($status -in @('failed','rejected','skipped') -and $oldPolicy -and $integrityPassed -and $eligibilityPassed -and $technicalGateFailed -and $ledgerAllowsPolicyReassessment)
        $terminal = ($status -in @('failed','rejected','skipped','submitted','blocked') -and -not $policyReassessment)
        $actionable = ($policyReassessment -or (-not $already -and -not $terminal))
        $stage = $null
        if ($actionable) {
            if ($policyReassessment) {
                $stage = 'policy_reassessment_pending'
            } elseif ($status -in @('pending','unassessed','captured-awaiting-source-and-assessment')) {
                $stage = 'assessment_pending'
            } elseif ($status -eq 'needs-evidence') {
                $stage = if ($hasCandidateEvidence) { 'reassessment_pending' } else { 'candidate_evidence_pending' }
            } elseif ($status -eq 'needs-research') {
                $stage = if ($hasEligibilityResearch) { 'reassessment_pending' } else { 'eligibility_research_pending' }
            } elseif ($status -eq 'passed') {
                $stage = 'coordinator_adjudication_pending'
            } else {
                $stage = 'queue_review_pending'
            }
        }
        $queue += [ordered]@{
            job_id = $id
            company = if ($job) { $job.company } else { $null }
            title = if ($job) { $job.title } else { $null }
            assessment_status = $status
            score = if ($fit) { $fit.score } else { $null }
            already_in_ledger = $already
            prior_ledger_status = $priorLedgerStatus
            assessment_policy_version = $policyVersion
            policy_reassessment = $policyReassessment
            actionable = $actionable
            stage = $stage
            has_candidate_evidence = $hasCandidateEvidence
            path = $dir.FullName
        }
    }
}

$generated = @()
$generatedRoot = Join-Path $root 'generated'
if (Test-Path -LiteralPath $generatedRoot) {
    foreach ($dir in Get-ChildItem -LiteralPath $generatedRoot -Directory) {
        $job = Read-JsonSafe (Join-Path $dir.FullName 'job.json')
        $result = Read-JsonSafe (Join-Path $dir.FullName 'application-result.json')
        $progress = Read-JsonSafe (Join-Path $dir.FullName 'application-progress.json')
        $artifact = Read-JsonSafe (Join-Path $dir.FullName 'resume-artifact.json')
        $id = if ($job -and $job.job_id) { [string]$job.job_id } else { $dir.Name.Split('-')[0] }
        $priorLedgerStatus = if ($ledgerLastStatus.ContainsKey($id)) { [string]$ledgerLastStatus[$id] } else { $null }
        $allowAfterPriorSkip = ($job -and ($job.PSObject.Properties.Name -contains 'allow_after_prior_skip') -and [bool]$job.allow_after_prior_skip -and $priorLedgerStatus -in @('skipped-low-fit','skipped-mandatory-gate','skipped-stack-mismatch','skipped-role-family'))
        $already = ($ledgerIds.ContainsKey($id) -and -not $allowAfterPriorSkip)
        $resultStatus = if ($result -and $result.status) { [string]$result.status } else { $null }
        $needsReconcile = (($null -ne $result) -and -not $already)
        $terminalResult = $resultStatus -in @('submitted','handoff-easy-apply','blocked-auth','blocked-security','blocked-automation','blocked-domain-circuit-breaker','blocked-identity-mismatch','blocked-work-auth','blocked-unknown-fact','blocked-technical','skipped-ineligible','failed')
        $resumeReady = ($null -ne $artifact)
        $actionable = (-not $already -and -not $needsReconcile -and -not $terminalResult)
        $stage = $null
        if ($needsReconcile) {
            $stage = 'reconcile_result'
        } elseif ($actionable -and -not $resumeReady) {
            $stage = 'resume_pending'
        } elseif ($actionable -and $null -ne $progress) {
            $stage = 'application_resume'
        } elseif ($actionable -and $resumeReady) {
            $stage = 'application_ready'
        }
        $generated += [ordered]@{
            job_id = $id
            company = if ($job) { $job.company } else { $null }
            title = if ($job) { $job.title } else { $null }
            source = if ($job) { $job.source } else { $null }
            resume_ready = $resumeReady
            application_status = $resultStatus
            progress_stage = if ($progress -and $progress.stage) { [string]$progress.stage } elseif ($progress -and $progress.last_confirmed_stage) { [string]$progress.last_confirmed_stage } else { $null }
            already_in_ledger = $already
            prior_ledger_status = $priorLedgerStatus
            allow_after_prior_skip = $allowAfterPriorSkip
            needs_reconcile = $needsReconcile
            actionable = $actionable
            stage = $stage
            path = $dir.FullName
        }
    }
}

$reconcile = @($generated | Where-Object { $_.needs_reconcile })
$generatedActionable = @($generated | Where-Object { $_.actionable })
$queueActionable = @($queue | Where-Object { $_.actionable })

if ($reconcile.Count -gt 0) {
    $nextAction = 'reconcile'
    $selected = $reconcile
} elseif ($generatedActionable.Count -gt 0) {
    $nextAction = 'resume-generated'
    $selected = $generatedActionable
} elseif ($queueActionable.Count -gt 0) {
    $nextAction = 'process-queue'
    $selected = $queueActionable
} else {
    $nextAction = 'discover'
    $selected = @()
}
$actionPaths = @($selected | ForEach-Object { $_.path })
$actions = @($selected | ForEach-Object { [ordered]@{ job_id=$_.job_id; company=$_.company; title=$_.title; path=$_.path; stage=$_.stage } })

$circuitPath = Join-Path $root 'domain-circuit-breakers.jsonl'
$circuitCount = 0
if (Test-Path -LiteralPath $circuitPath) {
    $circuitCount = @((Get-Content -LiteralPath $circuitPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })).Count
}
$markerRoot = Join-Path $root 'domain-circuit-breakers'
$activeMarkers = @()
if (Test-Path -LiteralPath $markerRoot) {
    $activeMarkers = @(Get-ChildItem -LiteralPath $markerRoot -File | Select-Object -ExpandProperty Name)
}

$stats = Read-JsonSafe (Join-Path $root 'campaign-stats.json')
$linkedinStatus = Get-LinkedInGovernorStatus -BootstrapSubmissions $ledgerEasyApplySubmissions

$out = [ordered]@{
    workspace = $Workspace
    runtime_root = $root
    next_action = $nextAction
    actions = $actions
    action_paths = $actionPaths
    summary = [ordered]@{
        ledger_decisions = $ledgerCount
        ledger_submitted = $submittedCount
        queue_total = $queue.Count
        queue_actionable = $queueActionable.Count
        generated_total = $generated.Count
        generated_actionable = $generatedActionable.Count
        results_needing_reconcile = $reconcile.Count
        domain_circuit_breaker_events = $circuitCount
    }
    linkedin_governor = $linkedinStatus
    active_domain_markers = $activeMarkers
    campaign_stats = $stats
    snapshot_authoritative = $true
    instruction = if ($nextAction -eq 'discover') { 'No existing actionable work. Begin discovery immediately; do not rescan queue/generated/ledger.' } else { 'Follow each actions[].stage directly. Do not inspect directories merely to rediscover their stage; read job files only when the indicated stage requires their contents.' }
}
$out | ConvertTo-Json -Depth 8
