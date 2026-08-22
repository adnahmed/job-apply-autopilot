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
$backupDir = Join-Path $HOME ".config\opencode\backups\job-apply-autopilot\$stamp"
$names = @(
    'job-autopilot-assessor.md',
    'job-autopilot-research.md',
    'job-autopilot-resume.md',
    'job-autopilot-external-apply.md',
    'job-autopilot-email-apply.md'
)

foreach ($name in $names) {
    $src = Join-Path $sourceDir $name
    if (-not (Test-Path -LiteralPath $src)) { throw "Missing packaged subagent: $src" }
    $dst = Join-Path $targetDir $name
    if (Test-Path -LiteralPath $dst) {
        New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
        Copy-Item -LiteralPath $dst -Destination (Join-Path $backupDir $name) -Force
    }
    Copy-Item -LiteralPath $src -Destination $dst -Force
    if ($unblock) { Unblock-File -LiteralPath $dst -ErrorAction SilentlyContinue }
    Write-Output "Installed $dst"
}
Write-Output 'Restart OpenCode before relying on the updated worker definitions; live sessions may cache agent prompts and permissions.'
if (Test-Path -LiteralPath $backupDir) { Write-Output "Previous definitions backed up outside the auto-discovered agent directory: $backupDir" }
