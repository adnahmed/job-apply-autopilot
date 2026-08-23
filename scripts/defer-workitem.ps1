[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$WorkItemDir,
    [Parameter(Mandatory=$true)][string]$Stage,
    [Parameter(Mandatory=$true)][string]$Code,
    [string]$Message = '',
    [ValidateSet('transient','deterministic')]
    [string]$Class = 'transient'
)

$ErrorActionPreference = 'Stop'

try {
    $WorkItemDir = (Resolve-Path -LiteralPath $WorkItemDir).Path
    $path = Join-Path $WorkItemDir 'recoverable-error.json'
    $prior = $null
    if (Test-Path -LiteralPath $path) {
        try { $prior = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json } catch {}
    }

    $normalizedStage = $Stage.Trim().ToLowerInvariant()
    $normalizedCode = $Code.Trim().ToLowerInvariant()
    $fingerprint = "$normalizedStage|$normalizedCode"

    $attempts = if ($prior -and $prior.attempts) { [int]$prior.attempts + 1 } else { 1 }

    $priorFailureClass = if ($prior -and $prior.failure_class) { [string]$prior.failure_class } else { '' }
    $priorFingerprint = if ($prior -and $prior.fingerprint) { [string]$prior.fingerprint } else { '' }

    $sameFingerprintAttempts = 1
    if ($priorFailureClass -eq $Class -and $priorFingerprint -eq $fingerprint -and $prior.same_fingerprint_attempts) {
        $sameFingerprintAttempts = [int]$prior.same_fingerprint_attempts + 1
    }

    $delaySeconds = switch ($Class) {
        'transient' {
            switch ($sameFingerprintAttempts) {
                1 { 60 }
                2 { 300 }
                default { 1800 }
            }
        }
        'deterministic' {
            switch ($sameFingerprintAttempts) {
                1 { 300 }
                2 { 21600 }
                default { 86400 }
            }
        }
        default { 60 }
    }

    $now = [DateTimeOffset]::UtcNow
    $state = [ordered]@{
        stage = $Stage
        code = $Code
        message = $Message
        failure_class = $Class
        fingerprint = $fingerprint
        attempts = $attempts
        same_fingerprint_attempts = $sameFingerprintAttempts
        updated_at = $now.ToString('o')
        retry_after = $now.AddSeconds($delaySeconds).ToString('o')
    }
    $tmp = "$path.$PID.$([Guid]::NewGuid().ToString('N')).tmp"
    $state | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $tmp -Encoding UTF8
    [IO.File]::Move($tmp, $path, $true)
    # A recovery checkpoint (for example captcha-waiting) is not necessarily the
    # scheduler stage that was claimed. Clear the actual active claim after the
    # defer transition commits so the work can be routed again after cooldown.
    $claimPath = Join-Path $WorkItemDir 'action-claim.json'
    $claimedStage = ''
    if (Test-Path -LiteralPath $claimPath) {
        try { $claimedStage = [string](Get-Content -LiteralPath $claimPath -Raw | ConvertFrom-Json).stage } catch {}
    }
    if (-not [string]::IsNullOrWhiteSpace($claimedStage)) {
        $runtimeRoot = Split-Path -Parent (Split-Path -Parent $WorkItemDir)
        $workspace = Split-Path -Parent $runtimeRoot
        & (Join-Path $PSScriptRoot 'claim-action.ps1') -Action ClearStage -Scope WorkItem -Stage $claimedStage -WorkItemDir $WorkItemDir -Workspace $workspace | Out-Null
    }
    [ordered]@{ status='deferred-recoverable'; attempts=$attempts; retry_after=$state.retry_after; next_stage='process_other_work'; failure_class=$Class; fingerprint=$fingerprint; same_fingerprint_attempts=$sameFingerprintAttempts } | ConvertTo-Json -Depth 6 -Compress
} catch {
    [ordered]@{ status='recoverable-error'; code='defer-workitem-exception'; message=$_.Exception.Message; next_stage='process_other_work' } | ConvertTo-Json -Depth 6 -Compress
    exit 0
}
