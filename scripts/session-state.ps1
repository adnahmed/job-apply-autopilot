[CmdletBinding()]
param([string]$Workspace = (Get-Location).Path)

$ErrorActionPreference = 'Stop'
$Workspace = (Resolve-Path -LiteralPath $Workspace).Path
$root = Join-Path $Workspace '.job-apply-autopilot'
if (-not (Test-Path -LiteralPath $root)) {
    throw "No job-apply-autopilot runtime at $root"
}

function Read-JsonSafe([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json) } catch { return $null }
}

$ledgerPath = Join-Path $root 'applications.jsonl'
$ledgerCount = 0
$submittedCount = 0
$ledgerIds = @{}
if (Test-Path -LiteralPath $ledgerPath) {
    foreach ($line in Get-Content -LiteralPath $ledgerPath) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $row = $line | ConvertFrom-Json
            $ledgerCount++
            if ($row.status -eq 'submitted' -or $row.submitted -eq $true) { $submittedCount++ }
            if ($null -ne $row.job_id) { $ledgerIds[[string]$row.job_id] = $true }
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
        $id = if ($job -and $job.job_id) { [string]$job.job_id } else { $dir.Name.Split('-')[0] }
        $status = if ($assessment -and $assessment.status) { [string]$assessment.status } else { 'unassessed' }
        $already = $ledgerIds.ContainsKey($id)
        $actionable = (-not $already -and $status -notin @('failed','rejected','skipped','submitted','blocked'))
        $queue += [ordered]@{
            job_id = $id
            company = if ($job) { $job.company } else { $null }
            title = if ($job) { $job.title } else { $null }
            assessment_status = $status
            score = if ($fit) { $fit.score } else { $null }
            already_in_ledger = $already
            actionable = $actionable
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
        $already = $ledgerIds.ContainsKey($id)
        $resultStatus = if ($result -and $result.status) { [string]$result.status } else { $null }
        $needsReconcile = (($null -ne $result) -and -not $already)
        $terminalResult = $resultStatus -in @('submitted','handoff-easy-apply','blocked-auth','blocked-security','blocked-automation','blocked-domain-circuit-breaker','blocked-identity-mismatch','blocked-work-auth','blocked-unknown-fact','blocked-technical','skipped-ineligible','failed')
        $resumeReady = ($null -ne $artifact)
        $resumeActionable = (-not $already -and -not $needsReconcile -and -not $terminalResult -and ($resumeReady -or $null -ne $progress))
        $generated += [ordered]@{
            job_id = $id
            company = if ($job) { $job.company } else { $null }
            title = if ($job) { $job.title } else { $null }
            resume_ready = $resumeReady
            application_status = $resultStatus
            progress_stage = if ($progress -and $progress.stage) { [string]$progress.stage } elseif ($progress -and $progress.last_confirmed_stage) { [string]$progress.last_confirmed_stage } else { $null }
            already_in_ledger = $already
            needs_reconcile = $needsReconcile
            actionable = $resumeActionable
            path = $dir.FullName
        }
    }
}

$reconcile = @($generated | Where-Object { $_.needs_reconcile })
$generatedActionable = @($generated | Where-Object { $_.actionable })
$queueActionable = @($queue | Where-Object { $_.actionable })

if ($reconcile.Count -gt 0) {
    $nextAction = 'reconcile'
    $actionPaths = @($reconcile | ForEach-Object { $_.path })
} elseif ($generatedActionable.Count -gt 0) {
    $nextAction = 'resume-generated'
    $actionPaths = @($generatedActionable | ForEach-Object { $_.path })
} elseif ($queueActionable.Count -gt 0) {
    $nextAction = 'process-queue'
    $actionPaths = @($queueActionable | ForEach-Object { $_.path })
} else {
    $nextAction = 'discover'
    $actionPaths = @()
}

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

$out = [ordered]@{
    workspace = $Workspace
    runtime_root = $root
    next_action = $nextAction
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
    active_domain_markers = $activeMarkers
    campaign_stats = $stats
    snapshot_authoritative = $true
    instruction = if ($nextAction -eq 'discover') { 'No existing actionable work. Begin discovery immediately; do not rescan queue/generated/ledger.' } else { 'Operate only on action_paths for existing-work continuation; do not rescan campaign state.' }
}
$out | ConvertTo-Json -Depth 8
