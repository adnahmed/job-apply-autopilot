[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$targetDir = Join-Path $HOME '.config\opencode\agents'
$names = @(
    'job-autopilot-assessor.md',
    'job-autopilot-evidence.md',
    'job-autopilot-eligibility.md',
    'job-autopilot-resume.md',
    'job-autopilot-external-apply.md'
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
    if ($text -notmatch '(?m)^\s{2}edit:\s*allow\s*$') {
        Write-Error "TRUSTED WRITE PERMISSION MISSING in $path"
        $failed = $true
        continue
    }
    if ($name -eq 'job-autopilot-external-apply.md') {
        if ($text -notmatch '(?m)^\s{2}"browseros-neo_\*":\s*allow\s*$') {
            Write-Error "EXTERNAL APPLICATOR BROWSEROS ALLOW MISSING in $path"
            $failed = $true
            continue
        }
    } else {
        if ($text -notmatch '(?m)^\s{2}"browseros-neo_\*":\s*deny\s*$') {
            Write-Error "BROWSEROS DENY MISSING in $path"
            $failed = $true
            continue
        }
    }
    Write-Output "OK trusted-worker $path"
}

if ($failed) { exit 1 }
