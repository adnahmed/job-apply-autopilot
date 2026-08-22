[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$WorkItemDir,
    [Parameter(Mandatory=$true)][ValidateSet('external','linkedin-easy-apply','email')][string]$Route,
    [Parameter(Mandatory=$true)][string]$Target,
    [Parameter(Mandatory=$true)][string]$Evidence
)
$ErrorActionPreference = 'Stop'
$WorkItemDir = (Resolve-Path -LiteralPath $WorkItemDir).Path
if ([string]::IsNullOrWhiteSpace($Target) -or [string]::IsNullOrWhiteSpace($Evidence)) { throw 'Target and Evidence must be non-empty.' }
$path = Join-Path $WorkItemDir 'application-route.json'
$value = [ordered]@{ version=1; route=$Route; target=$Target.Trim(); evidence=$Evidence.Trim(); resolved_at=[DateTimeOffset]::UtcNow.ToString('o') }
$temp = "$path.$PID.$([Guid]::NewGuid().ToString('N')).tmp"
try { $value | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $temp -Encoding UTF8; [IO.File]::Move($temp,$path,$true) }
finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue } }
$value | ConvertTo-Json -Compress
