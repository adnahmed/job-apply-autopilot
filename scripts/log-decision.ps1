[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$JobId,
    [Parameter(Mandatory=$true)][string]$Status,
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
$root = Join-Path $Workspace '.job-apply-autopilot'
$ledger = Join-Path $root 'applications.jsonl'
if (-not (Test-Path -LiteralPath $ledger)) { New-Item -ItemType File -Force -Path $ledger | Out-Null }
if ($Notes.Length -gt 300) { $Notes = $Notes.Substring(0,300) }
$row = [ordered]@{
    timestamp = (Get-Date).ToUniversalTime().ToString('o')
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
Add-Content -LiteralPath $ledger -Value ($row | ConvertTo-Json -Compress -Depth 4) -Encoding UTF8
Write-Output "logged $JobId $Status $ReasonCode"
