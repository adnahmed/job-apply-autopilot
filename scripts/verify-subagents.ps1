[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Require-Pattern {
    param(
        [string]$Content,
        [string]$Pattern,
        [string]$Message
    )

    if ($Content -notmatch $Pattern) {
        Write-Error $Message
        return $false
    }

    return $true
}

function Reject-Pattern {
    param(
        [string]$Content,
        [string]$Pattern,
        [string]$Message
    )

    if ($Content -match $Pattern) {
        Write-Error $Message
        return $false
    }

    return $true
}

$targetDir = Join-Path $HOME '.config\opencode\agents'
$names = @(
    'job-autopilot-assessor.md',
    'job-autopilot-research.md',
    'job-autopilot-resume.md',
    'job-autopilot-external-apply.md',
    'job-autopilot-email-apply.md',
    'job-autopilot-linkedin-discovery.md'
)

$failed = $false
foreach ($name in $names) {
    $path = Join-Path $targetDir $name
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Error "MISSING $path"
        $failed = $true
        continue
    }
    $content = Get-Content -LiteralPath $path -Raw
    if ($content -notmatch '(?m)^mode:\s*subagent\s*$') {
        Write-Error "INVALID mode in $path"
        $failed = $true
        continue
    }
    if ($content -notmatch '(?m)^hidden:\s*true\s*$') {
        Write-Error "INVALID hidden flag in $path"
        $failed = $true
        continue
    }
    if ($content -notmatch '(?m)^\s{4}"\*":\s*allow\s*$') {
        Write-Error "BROAD POWERSHELL CONTRACT MISSING in $path"
        $failed = $true
        continue
    }
    $ok = $true

    if ($name -eq 'job-autopilot-resume.md') {
        $ok = (Require-Pattern -Content $content -Pattern 'get-resume-context\.ps1' -Message "RESUME CONTEXT ENTRYPOINT MISSING in $path") -and $ok

        $ok = (Reject-Pattern -Content $content -Pattern '-Action\s+Acquire[\s\S]{0,300}-Stage\s+resume_pending' -Message "RESUME WORKER MUST NOT DIRECTLY ACQUIRE resume_pending in $path; get-resume-context.ps1 owns the claim") -and $ok

        $ok = (Reject-Pattern -Content $content -Pattern '-Stage\s+resume_pending[\s\S]{0,300}-Action\s+Acquire' -Message "RESUME WORKER MUST NOT DIRECTLY ACQUIRE resume_pending in $path; get-resume-context.ps1 owns the claim") -and $ok

    } elseif ($name -eq 'job-autopilot-external-apply.md') {
        foreach ($requirement in @(
            @{ Pattern = 'claim-action\.ps1'; Message = 'CLAIM SCRIPT MISSING' },
            @{ Pattern = '-Action\s+Acquire'; Message = 'CLAIM ACQUIRE MISSING' },
            @{ Pattern = '-Action\s+Release'; Message = 'CLAIM RELEASE MISSING' },
            @{ Pattern = '-LeaseMinutes\s+15\b'; Message = 'EXTERNAL APPLY LEASE MUST BE 15 MINUTES' },
            @{ Pattern = '-OwnerId'; Message = 'CLAIM OWNER REUSE MISSING' }
        )) {
            $ok = (Require-Pattern -Content $content -Pattern $requirement.Pattern -Message "$($requirement.Message) in $path") -and $ok
        }

        $ok = (Require-Pattern -Content $content -Pattern '-Action\s+Acquire[\s\S]{0,500}-OwnerId[\s\S]{0,300}-LeaseMinutes\s+15\b' -Message "EXTERNAL APPLY CLAIM RENEWAL WITH EXISTING OWNER AND 15-MINUTE LEASE MISSING in $path") -and $ok

    } elseif ($name -eq 'job-autopilot-email-apply.md') {
        foreach ($requirement in @(
            @{ Pattern = 'claim-action\.ps1'; Message = 'CLAIM SCRIPT MISSING' },
            @{ Pattern = '-Action\s+Acquire'; Message = 'CLAIM ACQUIRE MISSING' },
            @{ Pattern = '-Action\s+Release'; Message = 'CLAIM RELEASE MISSING' },
            @{ Pattern = '-LeaseMinutes\s+15\b'; Message = 'EMAIL APPLY LEASE MUST BE 15 MINUTES' },
            @{ Pattern = '-OwnerId'; Message = 'CLAIM OWNER REUSE MISSING' }
        )) {
            $ok = (Require-Pattern -Content $content -Pattern $requirement.Pattern -Message "$($requirement.Message) in $path") -and $ok
        }

        $ok = (Require-Pattern -Content $content -Pattern '-Action\s+Acquire[\s\S]{0,500}-OwnerId[\s\S]{0,300}-LeaseMinutes\s+15\b' -Message "EMAIL APPLY CLAIM RENEWAL WITH EXISTING OWNER AND 15-MINUTE LEASE MISSING in $path") -and $ok

    } elseif ($name -eq 'job-autopilot-assessor.md') {
        if ($content -notmatch '(?m)^\s{2}edit:\s*deny\s*$' -or $content -notmatch 'commit-assessment\.ps1' -or $content -notmatch 'ExpectedPriorStatus') {
            Write-Error "ASSESSOR DETERMINISTIC COMMIT PERMISSION INVALID in $path"
            $ok = $false
        }

    } elseif ($name -eq 'job-autopilot-research.md') {
        if ($content -notmatch '(?m)^\s{2}edit:\s*allow\s*$') {
            Write-Error "TRUSTED WRITE PERMISSION MISSING in $path"
            $ok = $false
        }

    } elseif ($name -eq 'job-autopilot-linkedin-discovery.md') {
        if ($content -notmatch 'Job ID: discovery:continuous' -or $content -notmatch 'Kind: campaign' -or
            $content -notmatch 'Target New' -or $content -notmatch 'dedupe-jobs\.ps1' -or
            $content -notmatch 'new-workitem\.ps1' -or $content -notmatch 'never wait for or inspect FreeHire output') {
            Write-Error "LINKEDIN DISCOVERY WORKER CONTRACT MISSING in $path"
            $ok = $false
        }
    }

    if ($ok -and $content -notmatch 'Return exactly one') {
        Write-Error "WORKER PATH/RELEASE/RETURN CONTRACT INVALID in $path"
        $ok = $false
    }

    if ($name -eq 'job-autopilot-email-apply.md') {
        if ($content -notmatch '(?m)^\s{2}edit:\s*deny\s*$' -or $content -notmatch 'application-send-guard\.ps1') {
            Write-Error "EMAIL APPLICATOR DETERMINISTIC SEND PERMISSION INVALID in $path"
            $ok = $false
        }
    }

    if ($name -in @('job-autopilot-external-apply.md','job-autopilot-email-apply.md','job-autopilot-linkedin-discovery.md')) {
        if ($content -notmatch '(?m)^\s{2}"browseros-neo_\*":\s*allow\s*$') {
            Write-Error "BROWSER WORKER BROWSEROS ALLOW MISSING in $path"
            $ok = $false
        }
        if ($name -ne 'job-autopilot-linkedin-discovery.md' -and $content -notmatch 'reservation performs the final quality gate') {
            Write-Error "APPLICATOR QUALITY GATE CONTRACT MISSING in $path"
            $ok = $false
        }
        if ($name -eq 'job-autopilot-external-apply.md' -and ($content -notmatch 'resolve-application-answer\.ps1' -or $content -notmatch 'preflight-application\.ps1' -or $content -notmatch 'set-application-route\.ps1')) {
            Write-Error "EXTERNAL APPLICATOR ANSWER/ROUTE CONTRACT MISSING in $path"
            $ok = $false
        }
        if ($name -ne 'job-autopilot-linkedin-discovery.md' -and ($content -notmatch 'write-application-outcome\.ps1' -or
            $content -notmatch 'do not call the free-form `run` tool' -or $content -notmatch 'quarantined' -or
            $content -notmatch [regex]::Escape('$HOME\.config\opencode\skills\job-apply-autopilot\scripts\write-application-outcome.ps1') -or
            $content -notmatch [regex]::Escape('$HOME\.config\opencode\skills\job-apply-autopilot\references\browseros-playbook.md'))) {
            Write-Error "APPLICATOR V6 OUTCOME/QUARANTINE CONTRACT MISSING in $path"
            $ok = $false
        }
    } else {
        if ($content -notmatch '(?m)^\s{2}"browseros-neo_\*":\s*deny\s*$') {
            Write-Error "BROWSEROS DENY MISSING in $path"
            $ok = $false
        }
    }

    if ($name -eq 'job-autopilot-email-apply.md') {
        if ($content -notmatch 'application-send-guard\.ps1') {
            Write-Error "EMAIL APPLICATOR SEND GUARD PERMISSION MISSING in $path"
            $ok = $false
        }
    }

    if ($ok) {
        Write-Output "OK trusted-worker $path"
    } else {
        $failed = $true
    }
}

if ($failed) { exit 1 }
