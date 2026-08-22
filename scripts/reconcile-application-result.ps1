[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$WorkItemDir,
    [string]$Workspace = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'
$WorkItemDir = (Resolve-Path -LiteralPath $WorkItemDir).Path
if ([string]::IsNullOrWhiteSpace($Workspace)) { $Workspace = (Get-Location).Path }
$Workspace = (Resolve-Path -LiteralPath $Workspace).Path
$root = Join-Path $Workspace '.job-apply-autopilot'
$ledgerPath = Join-Path $root 'applications.jsonl'
$lockPath = Join-Path $root 'applications.lock'
$resultPath = Join-Path $WorkItemDir 'application-result.json'
$jobPath = Join-Path $WorkItemDir 'job.json'
$assessmentPath = Join-Path $WorkItemDir 'assessment.json'
if (-not (Test-Path -LiteralPath $resultPath)) { throw "Missing application-result.json in $WorkItemDir" }
if (-not (Test-Path -LiteralPath $jobPath)) { throw "Missing job.json in $WorkItemDir" }
$result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
$job = Get-Content -LiteralPath $jobPath -Raw | ConvertFrom-Json
$assessment = if (Test-Path -LiteralPath $assessmentPath) { try { Get-Content -LiteralPath $assessmentPath -Raw | ConvertFrom-Json } catch { $null } } else { $null }
$jobId = [string]$job.job_id
if ([string]::IsNullOrWhiteSpace($jobId)) { throw 'job.json has no job_id.' }
function Clear-ReconcileClaim {
    & (Join-Path $PSScriptRoot 'claim-action.ps1') -Action ClearStage -Scope WorkItem -Stage 'reconcile_result' -WorkItemDir $WorkItemDir -Workspace $Workspace | Out-Null
}
if ([string]$result.status -like 'handoff-*') {
    [ordered]@{ status='handoff-not-reconciled'; job_id=$jobId; result_status=$result.status } | ConvertTo-Json -Compress
    exit 0
}

New-Item -ItemType Directory -Force -Path $root | Out-Null
if (-not (Test-Path -LiteralPath $ledgerPath)) { New-Item -ItemType File -Path $ledgerPath | Out-Null }
$lock = $null
try {
    try { $lock = [IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None') }
    catch {
        [ordered]@{ status='busy'; job_id=$jobId } | ConvertTo-Json -Compress
        exit 0
    }
    foreach ($line in Get-Content -LiteralPath $ledgerPath) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $existing = $line | ConvertFrom-Json
            if ([string]$existing.job_id -eq $jobId -and ([string]$existing.status -eq 'submitted' -or [string]$existing.status -eq [string]$result.status)) {
                if ($null -ne $lock) { $lock.Dispose(); $lock = $null }
                $freehireSync = $null
                if ([string]$existing.status -eq 'submitted') {
                    try { $freehireSync = (& (Join-Path $PSScriptRoot 'sync-freehire-application.ps1') -WorkItemDir $WorkItemDir -Workspace $Workspace | Select-Object -Last 1) | ConvertFrom-Json } catch {}
                }
                Clear-ReconcileClaim
                [ordered]@{ status='already-reconciled'; job_id=$jobId; ledger_status=$existing.status; freehire_sync=if($freehireSync){[string]$freehireSync.status}else{$null} } | ConvertTo-Json -Compress
                exit 0
            }
        } catch {}
    }

    $submitted = ([bool]$result.submitted -or [string]$result.status -eq 'submitted')
    $ledgerStatus = if ($submitted) { 'submitted' } else { [string]$result.status }
    $method = if ($result.apply_method) { [string]$result.apply_method } else { 'external' }
    $reasonCode = if ($submitted) { "$method-submitted" } elseif ($result.blocker) { [string]$result.blocker } else { $ledgerStatus }
    $notes = if ($result.confirmation) { [string]$result.confirmation } elseif ($result.blocker) { [string]$result.blocker } else { '' }
    if ($notes.Length -gt 300) { $notes = $notes.Substring(0,300) }
    $timestamp = [DateTimeOffset]::UtcNow.ToString('o')
    if ($result.submitted_at) {
        try { $timestamp = [DateTimeOffset]::Parse([string]$result.submitted_at, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AllowWhiteSpaces).ToUniversalTime().ToString('o') } catch {}
    } elseif ($result.completed_at) {
        try { $timestamp = [DateTimeOffset]::Parse([string]$result.completed_at, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AllowWhiteSpaces).ToUniversalTime().ToString('o') } catch {}
    }
    $row = [ordered]@{
        timestamp = $timestamp
        status = $ledgerStatus
        reason_code = $reasonCode
        source = if ($job.source) { [string]$job.source } else { $method }
        company = [string]$job.company
        title = [string]$job.title
        location = if ($job.location) { [string]$job.location } else { '' }
        job_url = if ($job.job_url) { [string]$job.job_url } else { '' }
        job_id = $jobId
    }
    if ($assessment -and $null -ne $assessment.score) { $row.score = [int]$assessment.score }
    if ($notes) { $row.notes = $notes }
    $json = $row | ConvertTo-Json -Compress -Depth 6
    $stream = [IO.File]::Open($ledgerPath, 'OpenOrCreate', 'ReadWrite', 'Read')
    try {
        if ($stream.Length -gt 0) {
            $stream.Seek(-1, [IO.SeekOrigin]::End) | Out-Null
            $last = $stream.ReadByte()
            $stream.Seek(0, [IO.SeekOrigin]::End) | Out-Null
            if ($last -notin @(10,13)) {
                $newline = [Text.Encoding]::UTF8.GetBytes([Environment]::NewLine)
                $stream.Write($newline, 0, $newline.Length)
            }
        }
        $bytes = [Text.Encoding]::UTF8.GetBytes($json + [Environment]::NewLine)
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
    } finally { $stream.Dispose() }
    if ($null -ne $lock) { $lock.Dispose(); $lock = $null }
    $freehireSync = $null
    if ($submitted) {
        try { $freehireSync = (& (Join-Path $PSScriptRoot 'sync-freehire-application.ps1') -WorkItemDir $WorkItemDir -Workspace $Workspace | Select-Object -Last 1) | ConvertFrom-Json } catch {}
    }
    & (Join-Path $PSScriptRoot 'update-campaign-stats.ps1') -Workspace $Workspace | Out-Null
    Clear-ReconcileClaim
    [ordered]@{ status='reconciled'; job_id=$jobId; ledger_status=$ledgerStatus; reason_code=$reasonCode; freehire_sync=if($freehireSync){[string]$freehireSync.status}else{$null} } | ConvertTo-Json -Compress
} finally {
    if ($null -ne $lock) { $lock.Dispose() }
    try { Clear-ReconcileClaim } catch {}
}
