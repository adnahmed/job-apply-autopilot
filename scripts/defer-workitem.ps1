[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$WorkItemDir,
    [Parameter(Mandatory=$true)][string]$Stage,
    [Parameter(Mandatory=$true)][string]$Code,
    [string]$Message = ''
)

$ErrorActionPreference = 'Stop'

try {
    $WorkItemDir = (Resolve-Path -LiteralPath $WorkItemDir).Path
    $path = Join-Path $WorkItemDir 'recoverable-error.json'
    $prior = $null
    if (Test-Path -LiteralPath $path) {
        try { $prior = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json } catch {}
    }
    $attempts = if ($prior -and $prior.attempts) { [int]$prior.attempts + 1 } else { 1 }
    $delaySeconds = switch ($attempts) {
        1 { 60 }
        2 { 300 }
        default { 1800 }
    }
    $now = [DateTimeOffset]::UtcNow
    $state = [ordered]@{
        stage = $Stage
        code = $Code
        message = $Message
        attempts = $attempts
        updated_at = $now.ToString('o')
        retry_after = $now.AddSeconds($delaySeconds).ToString('o')
    }
    $tmp = "$path.tmp"
    $state | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $path -Force
    [ordered]@{ status='deferred-recoverable'; attempts=$attempts; retry_after=$state.retry_after; next_stage='process_other_work' } | ConvertTo-Json -Depth 6 -Compress
} catch {
    [ordered]@{ status='recoverable-error'; code='defer-workitem-exception'; message=$_.Exception.Message; next_stage='process_other_work' } | ConvertTo-Json -Depth 6 -Compress
    exit 0
}
