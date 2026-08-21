[CmdletBinding()]
param([string]$Workspace = (Get-Location).Path)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Workspace)) { $Workspace = (Get-Location).Path }
$Workspace = (Resolve-Path -LiteralPath $Workspace).Path
$supervisorRoot = Join-Path $Workspace '.job-apply-autopilot\supervisor'
$statePath = Join-Path $supervisorRoot 'state.json'
$stopPath = Join-Path $supervisorRoot 'stop.requested'
$state = if (Test-Path -LiteralPath $statePath) { try { Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json } catch { $null } } else { $null }
$pidValue = if ($state -and $state.pid) { [int]$state.pid } else { 0 }
$process = if ($pidValue -gt 0) { Get-Process -Id $pidValue -ErrorAction SilentlyContinue } else { $null }
$alive = ($null -ne $process)
$stopRequested = Test-Path -LiteralPath $stopPath
$effective = if ($alive -and -not $stopRequested -and [string]$state.status -notin @('stopped','stopping')) {
    'running'
} elseif ($stopRequested) {
    'stop-requested'
} elseif ($state -and [string]$state.status -eq 'stopped') {
    'stopped'
} elseif ($state -and -not $alive) {
    'stale-state'
} else {
    'not-started'
}

$health = try {
    ((& (Join-Path $PSScriptRoot 'test-browseros-health.ps1') | Select-Object -Last 1) | ConvertFrom-Json)
} catch { $null }

[ordered]@{
    status = $effective
    running = ($effective -eq 'running')
    pid = if ($pidValue -gt 0) { $pidValue } else { $null }
    process_name = if ($process) { $process.ProcessName } else { $null }
    supervisor_state = if ($state) { $state.status } else { $null }
    session = if ($state -and $state.PSObject.Properties.Name -contains 'session') { $state.session } elseif ($state -and $state.PSObject.Properties.Name -contains 'sessions') { $state.sessions } else { $null }
    stop_requested = $stopRequested
    browseros_healthy = if ($health) { [bool]$health.healthy } else { $false }
    browseros_reason = if ($health) { $health.reason } else { 'health-check-failed' }
    state_path = $statePath
    updated_at = if ($state) { $state.updated_at } else { $null }
} | ConvertTo-Json -Depth 6
