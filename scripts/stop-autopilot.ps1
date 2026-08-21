[CmdletBinding()]
param([string]$Workspace = (Get-Location).Path)

$ErrorActionPreference = 'Stop'
$Workspace = (Resolve-Path -LiteralPath $Workspace).Path
$supervisorRoot = Join-Path $Workspace '.job-apply-autopilot\supervisor'
New-Item -ItemType Directory -Force -Path $supervisorRoot | Out-Null
$stopPath = Join-Path $supervisorRoot 'stop.requested'
[DateTimeOffset]::UtcNow.ToString('o') | Set-Content -LiteralPath $stopPath -Encoding UTF8
[ordered]@{ status='stop-requested'; workspace=$Workspace; marker=$stopPath } | ConvertTo-Json -Compress
