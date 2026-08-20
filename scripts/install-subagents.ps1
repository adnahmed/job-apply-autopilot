[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$skillRoot = Split-Path -Parent $PSScriptRoot
$unblock = Get-Command Unblock-File -ErrorAction SilentlyContinue
if ($unblock) {
    Get-ChildItem -LiteralPath $skillRoot -Recurse -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue
}
$sourceDir = Join-Path $skillRoot 'agents'
$targetDir = Join-Path $HOME '.config\opencode\agents'
New-Item -ItemType Directory -Force -Path $targetDir | Out-Null

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$names = @(
    'job-autopilot-assessor.md',
    'job-autopilot-evidence.md',
    'job-autopilot-eligibility.md',
    'job-autopilot-resume.md',
    'job-autopilot-external-apply.md'
)

foreach ($name in $names) {
    $src = Join-Path $sourceDir $name
    if (-not (Test-Path -LiteralPath $src)) { throw "Missing packaged subagent: $src" }
    $dst = Join-Path $targetDir $name
    if (Test-Path -LiteralPath $dst) {
        Copy-Item -LiteralPath $dst -Destination "$dst.backup-$stamp" -Force
    }
    Copy-Item -LiteralPath $src -Destination $dst -Force
    if ($unblock) { Unblock-File -LiteralPath $dst -ErrorAction SilentlyContinue }
    Write-Output "Installed $dst"
}
