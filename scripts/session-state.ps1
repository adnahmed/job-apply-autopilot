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
$ledger = @()
if (Test-Path -LiteralPath $ledgerPath) {
    foreach ($line in Get-Content -LiteralPath $ledgerPath) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $ledger += ($line | ConvertFrom-Json) } catch {}
    }
}
$ledgerIds = @{}
foreach ($row in $ledger) {
    if ($null -ne $row.job_id) { $ledgerIds[[string]$row.job_id] = $true }
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
        $queue += [ordered]@{
            job_id = $id
            company = if ($job) { $job.company } else { $null }
            title = if ($job) { $job.title } else { $null }
            assessment_status = $status
            score = if ($fit) { $fit.score } else { $null }
            already_in_ledger = $ledgerIds.ContainsKey($id)
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
        $generated += [ordered]@{
            job_id = $id
            company = if ($job) { $job.company } else { $null }
            title = if ($job) { $job.title } else { $null }
            resume_ready = ($null -ne $artifact)
            application_status = if ($result -and $result.status) { [string]$result.status } else { $null }
            progress_stage = if ($progress -and $progress.stage) { [string]$progress.stage } elseif ($progress -and $progress.last_confirmed_stage) { [string]$progress.last_confirmed_stage } else { $null }
            already_in_ledger = $ledgerIds.ContainsKey($id)
            needs_reconcile = (($null -ne $result) -and -not $ledgerIds.ContainsKey($id))
            path = $dir.FullName
        }
    }
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
    generated_root = $generatedRoot
    ledger_decisions = $ledger.Count
    ledger_submitted = @($ledger | Where-Object { $_.status -eq 'submitted' -or $_.submitted -eq $true }).Count
    queue_count = $queue.Count
    generated_count = $generated.Count
    queue_actionable = @($queue | Where-Object { -not $_.already_in_ledger -and $_.assessment_status -notin @('failed','rejected') })
    generated_actionable = @($generated | Where-Object { -not $_.already_in_ledger -or $_.needs_reconcile })
    completed_external_results_needing_reconcile = @($generated | Where-Object { $_.needs_reconcile }).Count
    domain_circuit_breaker_events = $circuitCount
    active_domain_markers = $activeMarkers
    campaign_stats = $stats
}
$out | ConvertTo-Json -Depth 8
