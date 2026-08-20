[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$targetDir = Join-Path $HOME '.config\opencode\agents'
$names = @(
    'job-autopilot-assessor.md',
    'job-autopilot-eligibility.md',
    'job-autopilot-resume.md'
)

$failed = $false
foreach ($name in $names) {
    $path = Join-Path $targetDir $name
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Error "MISSING $path"
        $failed = $true
        continue
    }
    $text = Get-Content -LiteralPath $path -Raw
    if ($text -notmatch '(?m)^mode:\s*subagent\s*$') {
        Write-Error "INVALID mode in $path"
        $failed = $true
        continue
    }
    if ($text -notmatch '(?m)^hidden:\s*true\s*$') {
        Write-Error "INVALID hidden flag in $path"
        $failed = $true
        continue
    }
    Write-Output "OK $path"
}

if ($failed) { exit 1 }
