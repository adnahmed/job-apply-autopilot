[CmdletBinding()]
param(
    [ValidateSet('Status','RecordEasyApply','RecordSignal','ClearManualBlock','AcquireApply','RenewApply','ReleaseApply')]
    [string]$Action = 'Status',
    [string]$Workspace = (Get-Location).Path,
    [string]$JobId = '',
    [ValidateSet('rate-limit','security-warning','captcha','mfa','account-restriction','other')]
    [string]$SignalType = 'other',
    [string]$OwnerId = '',
    [int]$LeaseMinutes = 15,
    [ValidateSet('submit','maintenance')]
    [string]$Purpose = 'submit',
    [int]$MaxPerHour = 4,
    [int]$MaxPer24Hours = 20,
    [int]$MinIntervalSeconds = 600
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Workspace)) { $Workspace = (Get-Location).Path }
$Workspace = (Resolve-Path -LiteralPath $Workspace).Path
$root = Join-Path $Workspace '.job-apply-autopilot'
if (-not (Test-Path -LiteralPath $root)) { throw "No job-apply-autopilot runtime at $root" }
$statePath = Join-Path $root 'linkedin-activity-state.json'
$lockPath = Join-Path $root 'linkedin-activity-state.lock'

function Parse-Utc($Value) {
    if ($null -eq $Value) { return $null }
    try {
        if ($Value -is [DateTimeOffset]) { return $Value.ToUniversalTime() }
        if ($Value -is [DateTime]) { return ([DateTimeOffset]$Value).ToUniversalTime() }
        $text = [string]$Value
        if ([string]::IsNullOrWhiteSpace($text)) { return $null }
        return [DateTimeOffset]::Parse($text, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
    } catch { return $null }
}

function Test-EasyApplyRow($Row) {
    $submitted = ([string]$Row.status -eq 'submitted' -or $Row.submitted -eq $true)
    if (-not $submitted) { return $false }
    return (
        ([string]$Row.source -match 'linkedin.*easy.*apply') -or
        ([string]$Row.reason_code -eq 'easy-apply-submitted') -or
        ([string]$Row.route -eq 'linkedin-easy-apply')
    )
}

function Get-LedgerSeed {
    $times = @()
    $ids = @()
    $ledger = Join-Path $root 'applications.jsonl'
    if (Test-Path -LiteralPath $ledger) {
        foreach ($line in Get-Content -LiteralPath $ledger) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $row = $line | ConvertFrom-Json
                if (-not (Test-EasyApplyRow $row)) { continue }
                $dt = Parse-Utc $row.timestamp
                if ($null -ne $dt -and $dt -gt [DateTimeOffset]::UtcNow.AddHours(-24)) { $times += $dt.ToString('o') }
                if ($row.job_id) { $ids += [string]$row.job_id }
            } catch {}
        }
    }
    return [ordered]@{ times=@($times | Sort-Object -Unique); ids=@($ids | Sort-Object -Unique) }
}

function New-State {
    $seed = Get-LedgerSeed
    return [ordered]@{
        version = 2
        easy_apply_submissions = @($seed.times)
        easy_apply_job_ids = @($seed.ids)
        pause_until = $null
        pause_reason = $null
        manual_block = $false
        last_signal_at = $null
        last_signal_type = $null
        active_apply = $null
        updated_at = (Get-Date).ToUniversalTime().ToString('o')
    }
}

function Normalize-ActiveApply($State) {
    if ($State.active_apply -and $State.active_apply.expires_at) {
        $expiresAt = Parse-Utc $State.active_apply.expires_at
        if ($null -eq $expiresAt -or $expiresAt -le [DateTimeOffset]::UtcNow) {
            $State.active_apply = $null
        }
    }
    return $State
}

function Read-State {
    $state = New-State
    if (Test-Path -LiteralPath $statePath) {
        try {
            $raw = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
            $state.easy_apply_submissions = @($state.easy_apply_submissions) + @($raw.easy_apply_submissions)
            $state.easy_apply_job_ids = @($state.easy_apply_job_ids) + @($raw.easy_apply_job_ids)
            if ($raw.pause_until) { $state.pause_until = [string]$raw.pause_until }
            if ($raw.pause_reason) { $state.pause_reason = [string]$raw.pause_reason }
            if ($null -ne $raw.manual_block) { $state.manual_block = [bool]$raw.manual_block }
            if ($raw.last_signal_at) { $state.last_signal_at = [string]$raw.last_signal_at }
            if ($raw.last_signal_type) { $state.last_signal_type = [string]$raw.last_signal_type }
            if ($raw.active_apply) { $state.active_apply = $raw.active_apply }
        } catch {
            # The ledger seed is authoritative. A partial/corrupt state file must never erase pacing history.
        }
    }
    $parsed = @()
    foreach ($value in @($state.easy_apply_submissions)) {
        $dt = Parse-Utc $value
        if ($null -ne $dt -and $dt -gt [DateTimeOffset]::UtcNow.AddHours(-24)) { $parsed += $dt.ToString('o') }
    }
    $state.easy_apply_submissions = @($parsed | Sort-Object -Unique)
    $state.easy_apply_job_ids = @($state.easy_apply_job_ids | Where-Object { $_ } | Sort-Object -Unique)

    $state = Normalize-ActiveApply $state
    return $state
}

function Write-State($State) {
    $State.updated_at = (Get-Date).ToUniversalTime().ToString('o')
    $tempPath = "$statePath.$PID.$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        $State | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $tempPath -Encoding UTF8
        [IO.File]::Move($tempPath, $statePath, $true)
    } finally {
        if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue }
    }
}

function Get-Status($State) {
    $now = [DateTimeOffset]::UtcNow
    $parsed = @($State.easy_apply_submissions | ForEach-Object { Parse-Utc $_ } | Where-Object { $null -ne $_ -and $_ -gt $now.AddHours(-24) })
    $lastHour = @($parsed | Where-Object { $_ -gt $now.AddHours(-1) })
    $candidates = @($now)
    $reasons = @()

    if ($State.manual_block) { $reasons += 'manual-block' }
    $pause = Parse-Utc $State.pause_until
    if ($null -ne $pause -and $pause -gt $now) {
        $candidates += $pause
        $reasons += 'signal-cooldown'
    } elseif ($null -ne $pause) {
        $State.pause_until = $null
        $State.pause_reason = $null
    }
    if ($parsed.Count -gt 0) {
        $spacing = (($parsed | Sort-Object)[-1]).AddSeconds($MinIntervalSeconds)
        if ($spacing -gt $now) { $candidates += $spacing; $reasons += 'minimum-spacing' }
    }
    if ($lastHour.Count -ge $MaxPerHour) {
        $candidates += (($lastHour | Sort-Object)[0]).AddHours(1)
        $reasons += 'rolling-hour-limit'
    }
    if ($parsed.Count -ge $MaxPer24Hours) {
        $candidates += (($parsed | Sort-Object)[0]).AddHours(24)
        $reasons += 'rolling-24h-limit'
    }

    $next = ($candidates | Sort-Object)[-1]
    $allowed = (-not $State.manual_block -and $next -le $now)

    $applyInProgress = $false
    $activeApplyJobId = $null
    $activeApplyOwnerId = $null
    $activeApplyExpiresAt = $null
    $activeApplyPurpose = $null
    if ($State.active_apply -and $State.active_apply.expires_at) {
        $expiresAt = Parse-Utc $State.active_apply.expires_at
        if ($expiresAt -and $expiresAt -gt $now) {
            $applyInProgress = $true
            $activeApplyJobId = $State.active_apply.job_id
            $activeApplyOwnerId = $State.active_apply.owner_id
            $activeApplyExpiresAt = $State.active_apply.expires_at
            $activeApplyPurpose = $State.active_apply.purpose
            # If there's an active apply, easy_apply is not allowed for other jobs
            $allowed = $false
            if (-not ($reasons -contains 'apply-in-progress')) { $reasons += 'apply-in-progress' }
        }
    }

    return [ordered]@{
        workspace = $Workspace
        state_path = $statePath
        easy_apply_allowed = $allowed
        easy_apply_submissions_last_hour = $lastHour.Count
        easy_apply_submissions_last_24h = $parsed.Count
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
        apply_in_progress = $applyInProgress
        active_apply_job_id = $activeApplyJobId
        active_apply_owner_id = $activeApplyOwnerId
        active_apply_expires_at = $activeApplyExpiresAt
        active_apply_purpose = $activeApplyPurpose
    }
}

$lock = $null
try {
    for ($attempt = 0; $attempt -lt 100 -and $null -eq $lock; $attempt++) {
        try { $lock = [IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None') }
        catch { Start-Sleep -Milliseconds 25 }
    }
    if ($null -eq $lock) { throw 'Timed out waiting for the LinkedIn governor lock.' }

    $state = Read-State
    $nowText = [DateTimeOffset]::UtcNow.ToString('o')
    $actionResult = $null
    switch ($Action) {
        'RecordEasyApply' {
            $alreadyRecorded = ($JobId -and $JobId -in @($state.easy_apply_job_ids))
            if (-not $alreadyRecorded) {
                $state.easy_apply_submissions = @($state.easy_apply_submissions) + @($nowText)
                if ($JobId) { $state.easy_apply_job_ids = @($state.easy_apply_job_ids) + @($JobId) }
            }
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
        }
        'ClearManualBlock' {
            $state.manual_block = $false
            $state.pause_until = $null
            $state.pause_reason = $null
        }
        'AcquireApply' {
            if ([string]::IsNullOrWhiteSpace($OwnerId)) {
                $actionResult = [ordered]@{ status = 'error'; message = 'OwnerId required for AcquireApply' }
            } elseif ([string]::IsNullOrWhiteSpace($JobId)) {
                $actionResult = [ordered]@{ status = 'error'; message = 'JobId required for AcquireApply' }
            } elseif ($LeaseMinutes -le 0) {
                $actionResult = [ordered]@{ status = 'error'; message = 'LeaseMinutes must be positive' }
            } elseif ($state.active_apply -and $state.active_apply.expires_at) {
                $expiresAt = Parse-Utc $state.active_apply.expires_at
                if ($expiresAt -and $expiresAt -gt [DateTimeOffset]::UtcNow) {
                    if ($state.active_apply.owner_id -eq $OwnerId) {
                        # Same owner already owns it - extend expiry
                        $state.active_apply.expires_at = [DateTimeOffset]::UtcNow.AddMinutes($LeaseMinutes).ToString('o')
                        $actionResult = [ordered]@{ status = 'renewed'; owner_id = $OwnerId; job_id = $state.active_apply.job_id; expires_at = $state.active_apply.expires_at }
                    } else {
                        # Another live owner exists
                        $actionResult = [ordered]@{ status = 'busy'; message = 'Another LinkedIn application in progress'; active_apply_job_id = $state.active_apply.job_id; active_apply_owner_id = $state.active_apply.owner_id; active_apply_expires_at = $state.active_apply.expires_at }
                    }
                } else {
                    # Expired - clear and acquire
                    $state.active_apply = @{
                        owner_id = $OwnerId
                        job_id = $JobId
                        purpose = $Purpose
                        acquired_at = $nowText
                        expires_at = [DateTimeOffset]::UtcNow.AddMinutes($LeaseMinutes).ToString('o')
                    }
                    $actionResult = [ordered]@{ status = 'acquired'; owner_id = $OwnerId; job_id = $JobId; purpose = $Purpose; expires_at = $state.active_apply.expires_at }
                }
            } else {
                # No live owner
                if ($Purpose -eq 'submit') {
                    # For submit purpose, check timing/count rules
                    $tempStatus = Get-Status $state
                    if ($tempStatus.easy_apply_allowed -eq $true) {
                        $state.active_apply = @{
                            owner_id = $OwnerId
                            job_id = $JobId
                            purpose = $Purpose
                            acquired_at = $nowText
                            expires_at = [DateTimeOffset]::UtcNow.AddMinutes($LeaseMinutes).ToString('o')
                        }
                        $actionResult = [ordered]@{ status = 'acquired'; owner_id = $OwnerId; job_id = $JobId; purpose = $Purpose; expires_at = $state.active_apply.expires_at }
                    } else {
                        $actionResult = [ordered]@{ status = 'blocked'; block_reasons = $tempStatus.block_reasons; next_easy_apply_at = $tempStatus.next_easy_apply_at }
                    }
                } else {
                    # Purpose = maintenance: acquire without timing/count restrictions
                    $state.active_apply = @{
                        owner_id = $OwnerId
                        job_id = $JobId
                        purpose = $Purpose
                        acquired_at = $nowText
                        expires_at = [DateTimeOffset]::UtcNow.AddMinutes($LeaseMinutes).ToString('o')
                    }
                    $actionResult = [ordered]@{ status = 'acquired'; owner_id = $OwnerId; job_id = $JobId; purpose = $Purpose; expires_at = $state.active_apply.expires_at }
                }
            }
        }
        'RenewApply' {
            if ([string]::IsNullOrWhiteSpace($OwnerId)) {
                $actionResult = [ordered]@{ status = 'error'; message = 'OwnerId required for RenewApply' }
            } elseif ($state.active_apply -and $state.active_apply.owner_id -eq $OwnerId) {
                $state.active_apply.expires_at = [DateTimeOffset]::UtcNow.AddMinutes($LeaseMinutes).ToString('o')
                $actionResult = [ordered]@{ status = 'renewed'; owner_id = $OwnerId; job_id = $state.active_apply.job_id; purpose = $state.active_apply.purpose; expires_at = $state.active_apply.expires_at }
            } else {
                $actionResult = [ordered]@{ status = 'not-owner'; message = 'Lease owned by different owner' }
            }
        }
        'ReleaseApply' {
            if ([string]::IsNullOrWhiteSpace($OwnerId)) {
                $actionResult = [ordered]@{ status = 'error'; message = 'OwnerId required for ReleaseApply' }
            } elseif ($state.active_apply -and $state.active_apply.owner_id -eq $OwnerId) {
                $state.active_apply = $null
                $actionResult = [ordered]@{ status = 'released'; owner_id = $OwnerId }
            } else {
                # Non-matching OwnerId - leave state untouched
                $actionResult = [ordered]@{ status = 'not-owner'; message = 'Lease owned by different owner; state unchanged' }
            }
        }
    }

    $snapshot = Get-Status $state
    Write-State $state

    if ($null -eq $actionResult) {
        $result = $snapshot
    } else {
        $result = [ordered]@{}
        foreach ($entry in $snapshot.GetEnumerator()) {
            $result[$entry.Key] = $entry.Value
        }
        foreach ($entry in $actionResult.GetEnumerator()) {
            $result[$entry.Key] = $entry.Value
        }
    }

    $result | ConvertTo-Json -Depth 6
} finally {
    if ($null -ne $lock) { $lock.Dispose() }
}
