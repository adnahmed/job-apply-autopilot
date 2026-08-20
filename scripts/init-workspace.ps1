[CmdletBinding()]
param([string]$Workspace = (Get-Location).Path)

$ErrorActionPreference = 'Stop'
$root = Join-Path $Workspace '.job-apply-autopilot'
$generated = Join-Path $root 'generated'
$queue = Join-Path $root 'queue'
$circuitDir = Join-Path $root 'domain-circuit-breakers'
New-Item -ItemType Directory -Force -Path $generated | Out-Null
New-Item -ItemType Directory -Force -Path $queue | Out-Null
New-Item -ItemType Directory -Force -Path $circuitDir | Out-Null

$appLog = Join-Path $root 'applications.jsonl'
$relocLog = Join-Path $root 'relocation-watchlist.jsonl'
$circuitLog = Join-Path $root 'domain-circuit-breakers.jsonl'
$statsPath = Join-Path $root 'campaign-stats.json'

foreach ($path in @($appLog, $relocLog, $circuitLog)) {
    if (-not (Test-Path -LiteralPath $path)) { New-Item -ItemType File -Path $path | Out-Null }
}


if (-not (Test-Path -LiteralPath $statsPath)) {
    [ordered]@{ generated_at = $null; total_decisions = 0; submitted = 0; blocked = 0; skipped = 0; submission_rate = 0; statuses = @(); by_source = @(); by_discovery_lane = @() } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $statsPath -Encoding UTF8
}
Write-Output "Workspace initialized: $root"
Write-Output "Applications: $appLog"
Write-Output "Relocation watchlist: $relocLog"
Write-Output "Domain circuit breaker events: $circuitLog"
Write-Output "Domain circuit breaker markers: $circuitDir"
Write-Output "Queue work items: $queue"
Write-Output "Generated resumes: $generated"
Write-Output "Campaign stats: $statsPath"
