[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$JobId,
    [Parameter(Mandatory=$true)][ValidateSet('skipped-obvious','skipped-duplicate','skipped-closed','skipped-ineligible','skipped-low-fit','skipped-mandatory-gate','skipped-stack-mismatch','skipped-role-family','skipped-location-lock','skipped-work-auth-gate','skipped-location-gate','skipped-agency-unknown-client','skipped-agency','skipped-aggregator','skipped-management-only','skipped-license-clearance')][string]$Status,
    [Parameter(Mandatory=$true)][string]$ReasonCode,
    [string]$Company = '',
    [string]$Title = '',
    [string]$Location = '',
    [string]$JobUrl = '',
    [string]$Source = '',
    [Nullable[int]]$Score = $null,
    [string]$Notes = '',
    [string]$Workspace = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Workspace)) { $Workspace = (Get-Location).Path }
$Workspace = (Resolve-Path -LiteralPath $Workspace).Path
$root = Join-Path $Workspace '.job-apply-autopilot'
if (-not (Test-Path -LiteralPath $root)) { throw "No job-apply-autopilot runtime at $root" }
$ledger = Join-Path $root 'applications.jsonl'
$lockPath = Join-Path $root 'applications.lock'

# Discovery/assessment decisions cannot terminate a promoted application.
$generatedRoot = Join-Path $root 'generated'
if (Test-Path -LiteralPath $generatedRoot) {
    foreach ($dir in Get-ChildItem -LiteralPath $generatedRoot -Directory -ErrorAction SilentlyContinue) {
        $jobPath = Join-Path $dir.FullName 'job.json'
        if (-not (Test-Path -LiteralPath $jobPath)) { continue }
        try {
            $job = Get-Content -LiteralPath $jobPath -Raw | ConvertFrom-Json
            if ([string]$job.job_id -eq $JobId) { throw "Job $JobId is promoted; application outcomes must be written through write-application-outcome.ps1 or application-send-guard.ps1." }
        } catch {
            if ($_.Exception.Message -like 'Job * is promoted;*') { throw }
        }
    }
}

if ($Notes.Length -gt 300) { $Notes = $Notes.Substring(0,300) }
$row = [ordered]@{
    timestamp = [DateTimeOffset]::UtcNow.ToString('o')
    status = $Status
    reason_code = $ReasonCode
    source = $Source
    company = $Company
    title = $Title
    location = $Location
    job_url = $JobUrl
    job_id = $JobId
}
if ($null -ne $Score) { $row.score = $Score }
if (-not [string]::IsNullOrWhiteSpace($Notes)) { $row.notes = $Notes }
$json = $row | ConvertTo-Json -Compress -Depth 4

$lock = $null
try {
    try { $lock = [IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None') }
    catch {
        [ordered]@{ status='busy'; job_id=$JobId; logged=$false } | ConvertTo-Json -Compress
        exit 0
    }
    $stream = [IO.File]::Open($ledger, 'OpenOrCreate', 'ReadWrite', 'Read')
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
} finally {
    if ($null -ne $lock) { $lock.Dispose() }
}
[ordered]@{ status='logged'; job_id=$JobId; decision_status=$Status; reason_code=$ReasonCode; logged=$true } | ConvertTo-Json -Compress
