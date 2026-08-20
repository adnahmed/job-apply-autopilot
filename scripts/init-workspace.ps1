[CmdletBinding()]
param([string]$Workspace = (Get-Location).Path)

$ErrorActionPreference = 'Stop'
$root = Join-Path $Workspace '.job-apply-autopilot'
$generated = Join-Path $root 'generated'
$queue = Join-Path $root 'queue'
New-Item -ItemType Directory -Force -Path $generated | Out-Null
New-Item -ItemType Directory -Force -Path $queue | Out-Null

$appLog = Join-Path $root 'applications.jsonl'
$relocLog = Join-Path $root 'relocation-watchlist.jsonl'
$circuitLog = Join-Path $root 'domain-circuit-breakers.jsonl'

foreach ($path in @($appLog, $relocLog, $circuitLog)) {
    if (-not (Test-Path -LiteralPath $path)) { New-Item -ItemType File -Path $path | Out-Null }
}

Write-Output "Workspace initialized: $root"
Write-Output "Applications: $appLog"
Write-Output "Relocation watchlist: $relocLog"
Write-Output "Domain circuit breakers: $circuitLog"
Write-Output "Queue work items: $queue"
Write-Output "Generated resumes: $generated"
