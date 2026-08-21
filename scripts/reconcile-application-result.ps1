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
                [ordered]@{ status='already-reconciled'; job_id=$jobId; ledger_status=$existing.status } | ConvertTo-Json -Compress
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
    $timestamp = if ($result.submitted_at) { [string]$result.submitted_at } else { [DateTimeOffset]::UtcNow.ToString('o') }
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
    & (Join-Path $PSScriptRoot 'update-campaign-stats.ps1') -Workspace $Workspace | Out-Null
    [ordered]@{ status='reconciled'; job_id=$jobId; ledger_status=$ledgerStatus; reason_code=$reasonCode } | ConvertTo-Json -Compress
} finally {
    if ($null -ne $lock) { $lock.Dispose() }
}
