[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$targetDir = Join-Path $HOME '.config\opencode\agents'
$names = @(
    'job-autopilot-assessor.md',
    'job-autopilot-research.md',
    'job-autopilot-resume.md',
    'job-autopilot-external-apply.md',
    'job-autopilot-email-apply.md'
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
    if ($text -notmatch '(?m)^\s{4}"\*":\s*allow\s*$' -or
        $text -notmatch '\-Action Acquire' -or $text -notmatch '\-LeaseMinutes\s+(20|30|45)') {
        Write-Error "BROAD POWERSHELL/ACTION CLAIM CONTRACT MISSING in $path"
        $failed = $true
        continue
    }
    if ($text -notmatch [regex]::Escape('$HOME\.config\opencode\skills\job-apply-autopilot\scripts\claim-action.ps1') -or
        $text -notmatch '(?s)-Action Release.*?-Scope WorkItem.*?-Stage.*?-WorkItemDir.*?-OwnerId' -or
        $text -notmatch 'Return exactly one') {
        Write-Error "WORKER PATH/RELEASE/RETURN CONTRACT INVALID in $path"
        $failed = $true
        continue
    }
    if ($name -eq 'job-autopilot-assessor.md') {
        if ($text -notmatch '(?m)^\s{2}edit:\s*deny\s*$' -or $text -notmatch 'commit-assessment\.ps1' -or $text -notmatch 'ExpectedPriorStatus') {
            Write-Error "ASSESSOR DETERMINISTIC COMMIT PERMISSION INVALID in $path"
            $failed = $true
            continue
        }
    } elseif ($name -eq 'job-autopilot-email-apply.md') {
        if ($text -notmatch '(?m)^\s{2}edit:\s*deny\s*$' -or $text -notmatch 'application-send-guard\.ps1') {
            Write-Error "EMAIL APPLICATOR DETERMINISTIC SEND PERMISSION INVALID in $path"
            $failed = $true
            continue
        }
    } elseif ($text -notmatch '(?m)^\s{2}edit:\s*allow\s*$') {
        Write-Error "TRUSTED WRITE PERMISSION MISSING in $path"
        $failed = $true
        continue
    }
    if ($name -in @('job-autopilot-external-apply.md','job-autopilot-email-apply.md')) {
        if ($text -notmatch '(?m)^\s{2}"browseros-neo_\*":\s*allow\s*$') {
            Write-Error "APPLICATOR BROWSEROS ALLOW MISSING in $path"
            $failed = $true
            continue
        }
        if ($text -notmatch 'reservation performs the final quality gate') {
            Write-Error "APPLICATOR QUALITY GATE CONTRACT MISSING in $path"
            $failed = $true
            continue
        }
        if ($name -eq 'job-autopilot-external-apply.md' -and ($text -notmatch 'resolve-application-answer\.ps1' -or $text -notmatch 'preflight-application\.ps1' -or $text -notmatch 'set-application-route\.ps1')) {
            Write-Error "EXTERNAL APPLICATOR ANSWER/ROUTE CONTRACT MISSING in $path"
            $failed = $true
            continue
        }
        if ($text -notmatch 'write-application-outcome\.ps1' -or
            $text -notmatch 'do not call the free-form `run` tool' -or $text -notmatch 'quarantined' -or
            $text -notmatch [regex]::Escape('$HOME\.config\opencode\skills\job-apply-autopilot\scripts\write-application-outcome.ps1') -or
            $text -notmatch [regex]::Escape('$HOME\.config\opencode\skills\job-apply-autopilot\references\browseros-playbook.md')) {
            Write-Error "APPLICATOR V6 OUTCOME/QUARANTINE CONTRACT MISSING in $path"
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
    if ($name -eq 'job-autopilot-email-apply.md') {
        if ($text -notmatch 'application-send-guard\.ps1') {
            Write-Error "EMAIL APPLICATOR SEND GUARD PERMISSION MISSING in $path"
            $failed = $true
            continue
        }
    }
    Write-Output "OK trusted-worker $path"
}

if ($failed) { exit 1 }
