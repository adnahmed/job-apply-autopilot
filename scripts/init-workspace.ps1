[CmdletBinding()]
param([string]$Workspace = (Get-Location).Path)

$ErrorActionPreference = 'Stop'
$root = Join-Path $Workspace '.job-apply-autopilot'
$generated = Join-Path $root 'generated'
New-Item -ItemType Directory -Force -Path $generated | Out-Null

$appLog = Join-Path $root 'applications.jsonl'
$relocLog = Join-Path $root 'relocation-watchlist.jsonl'
if (-not (Test-Path -LiteralPath $appLog)) { New-Item -ItemType File -Path $appLog | Out-Null }
if (-not (Test-Path -LiteralPath $relocLog)) { New-Item -ItemType File -Path $relocLog | Out-Null }

Write-Output "Workspace initialized: $root"
Write-Output "Applications: $appLog"
Write-Output "Relocation watchlist: $relocLog"
Write-Output "Generated resumes: $generated"
