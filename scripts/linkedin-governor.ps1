[CmdletBinding()]
param(
    [ValidateSet('Status','RecordEasyApply','RecordSignal','ClearManualBlock')]
    [string]$Action = 'Status',
    [string]$Workspace = (Get-Location).Path,
    [ValidateSet('rate-limit','security-warning','captcha','mfa','account-restriction','other')]
    [string]$SignalType = 'other',
    [int]$MaxPerHour = 4,
    [int]$MaxPer24Hours = 20,
    [int]$MinIntervalSeconds = 600
)

$ErrorActionPreference = 'Stop'
$Workspace = (Resolve-Path -LiteralPath $Workspace).Path
$root = Join-Path $Workspace '.job-apply-autopilot'
if (-not (Test-Path -LiteralPath $root)) { throw "No job-apply-autopilot runtime at $root" }
$statePath = Join-Path $root 'linkedin-activity-state.json'

function New-State {
    $seed = @()
    $ledger = Join-Path $root 'applications.jsonl'
    if (Test-Path -LiteralPath $ledger) {
        foreach ($line in Get-Content -LiteralPath $ledger) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $row = $line | ConvertFrom-Json
                $source = [string]$row.source
                $submitted = ($row.status -eq 'submitted' -or $row.submitted -eq $true)
                if ($submitted -and $source -match 'linkedin.*easy.*apply' -and $row.timestamp) {
                    $dt = [DateTimeOffset]::Parse([string]$row.timestamp).ToUniversalTime()
                    if ($dt -gt [DateTimeOffset]::UtcNow.AddHours(-24)) { $seed += $dt.ToString('o') }
                }
            } catch {}
        }
    }
    return [ordered]@{
        version = 1
        easy_apply_submissions = @($seed | Sort-Object -Unique)
        pause_until = $null
        pause_reason = $null
        manual_block = $false
        last_signal_at = $null
        last_signal_type = $null
        updated_at = (Get-Date).ToUniversalTime().ToString('o')
    }
}

function Read-State {
    if (-not (Test-Path -LiteralPath $statePath)) { return (New-State) }
    try {
        $raw = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        $s = New-State
        if ($null -ne $raw.easy_apply_submissions) { $s.easy_apply_submissions = @($raw.easy_apply_submissions) }
        if ($raw.pause_until) { $s.pause_until = [string]$raw.pause_until }
        if ($raw.pause_reason) { $s.pause_reason = [string]$raw.pause_reason }
        if ($null -ne $raw.manual_block) { $s.manual_block = [bool]$raw.manual_block }
        if ($raw.last_signal_at) { $s.last_signal_at = [string]$raw.last_signal_at }
        if ($raw.last_signal_type) { $s.last_signal_type = [string]$raw.last_signal_type }
        return $s
    } catch { return (New-State) }
}

function Write-State($State) {
    $State.updated_at = (Get-Date).ToUniversalTime().ToString('o')
    $State | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $statePath -Encoding UTF8
}

function Parse-Utc([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    try { return [DateTimeOffset]::Parse($Value).ToUniversalTime() } catch { return $null }
}

function Get-Status($State) {
    $now = [DateTimeOffset]::UtcNow
    $parsed = @()
    foreach ($x in @($State.easy_apply_submissions)) {
        $dt = Parse-Utc ([string]$x)
        if ($null -ne $dt -and $dt -gt $now.AddHours(-24)) { $parsed += $dt }
    }
    $State.easy_apply_submissions = @($parsed | Sort-Object | ForEach-Object { $_.ToString('o') })

    $lastHour = @($parsed | Where-Object { $_ -gt $now.AddHours(-1) })
    $last24 = @($parsed)
    $candidates = @($now)
    $reasons = @()

    if ($State.manual_block) { $reasons += 'manual-block' }

    $pause = Parse-Utc ([string]$State.pause_until)
    if ($null -ne $pause -and $pause -gt $now) {
        $candidates += $pause
        $reasons += 'signal-cooldown'
    } elseif ($null -ne $pause -and $pause -le $now) {
        $State.pause_until = $null
        $State.pause_reason = $null
    }

    if ($parsed.Count -gt 0) {
        $last = ($parsed | Sort-Object)[-1]
        $spacing = $last.AddSeconds($MinIntervalSeconds)
        if ($spacing -gt $now) { $candidates += $spacing; $reasons += 'minimum-spacing' }
    }
    if ($lastHour.Count -ge $MaxPerHour) {
        $oldestHour = ($lastHour | Sort-Object)[0]
        $candidates += $oldestHour.AddHours(1)
        $reasons += 'rolling-hour-limit'
    }
    if ($last24.Count -ge $MaxPer24Hours) {
        $oldest24 = ($last24 | Sort-Object)[0]
        $candidates += $oldest24.AddHours(24)
        $reasons += 'rolling-24h-limit'
    }

    $next = ($candidates | Sort-Object)[-1]
    $allowed = (-not $State.manual_block -and $next -le $now)
    return [ordered]@{
        workspace = $Workspace
        state_path = $statePath
        easy_apply_allowed = $allowed
        easy_apply_submissions_last_hour = $lastHour.Count
        easy_apply_submissions_last_24h = $last24.Count
        max_per_hour = $MaxPerHour
        max_per_rolling_24h = $MaxPer24Hours
        min_interval_seconds = $MinIntervalSeconds
        next_easy_apply_at = if ($allowed) { $now.ToString('o') } elseif ($State.manual_block) { $null } else { $next.ToString('o') }
        block_reasons = @($reasons | Select-Object -Unique)
        manual_block = [bool]$State.manual_block
        pause_reason = $State.pause_reason
        last_signal_at = $State.last_signal_at
        last_signal_type = $State.last_signal_type
        external_applications_restricted = $false
    }
}

$state = Read-State
$nowText = [DateTimeOffset]::UtcNow.ToString('o')

switch ($Action) {
    'RecordEasyApply' {
        $state.easy_apply_submissions = @($state.easy_apply_submissions) + @($nowText)
        Write-State $state
    }
    'RecordSignal' {
        $state.last_signal_at = $nowText
        $state.last_signal_type = $SignalType
        $state.pause_reason = $SignalType
        if ($SignalType -in @('captcha','mfa','account-restriction')) {
            $state.manual_block = $true
            $state.pause_until = $null
        } else {
            $state.pause_until = [DateTimeOffset]::UtcNow.AddHours(24).ToString('o')
        }
        Write-State $state
    }
    'ClearManualBlock' {
        $state.manual_block = $false
        $state.pause_until = $null
        $state.pause_reason = $null
        Write-State $state
    }
    default { }
}

$status = Get-Status $state
Write-State $state
$status | ConvertTo-Json -Depth 6
