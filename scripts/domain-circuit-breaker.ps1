[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateSet('Status','Record','Clear','MigrateLegacy')][string]$Action,
    [string]$Workspace = (Get-Location).Path,
    [string]$Domain = '',
    [string]$Status = 'blocked-security',
    [string]$Reason = '',
    [string]$JobId = '',
    [string]$Company = '',
    [int]$DurationHours = 24
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Workspace)) { $Workspace = (Get-Location).Path }
$Workspace = (Resolve-Path -LiteralPath $Workspace).Path
$root = Join-Path $Workspace '.job-apply-autopilot'
if (-not (Test-Path -LiteralPath $root)) { throw "No job-apply-autopilot runtime at $root" }
$markerRoot = Join-Path $root 'domain-circuit-breakers'
$auditPath = Join-Path $root 'domain-circuit-breakers.jsonl'
New-Item -ItemType Directory -Force -Path $markerRoot | Out-Null
if (-not (Test-Path -LiteralPath $auditPath)) { New-Item -ItemType File -Path $auditPath | Out-Null }
$mutationLock = $null
if ($Action -in @('Record','Clear','MigrateLegacy')) {
    $lockPath = Join-Path $root 'domain-circuit-breakers.lock'
    try { $mutationLock = [IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None') }
    catch {
        [ordered]@{ status='busy'; active=$true; safe_to_submit=$false } | ConvertTo-Json -Compress
        exit 0
    }
}

function Normalize-Domain([string]$Value) {
    $text = $Value.Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($text)) { return '' }
    try {
        if ($text -match '^[a-z][a-z0-9+.-]*://') { $text = ([Uri]$text).Host.ToLowerInvariant() }
    } catch {}
    $text = $text -replace '^www\.', ''
    return $text.TrimEnd('.')
}

function Get-MarkerPath([string]$NormalizedDomain) {
    $safe = $NormalizedDomain -replace '[^a-z0-9.-]', '_'
    return (Join-Path $markerRoot "$safe.json")
}

function Write-JsonAtomic([string]$Path, $Value) {
    $temp = "$Path.$PID.$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        $Value | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temp -Encoding UTF8
        [IO.File]::Move($temp, $Path, $true)
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
    }
}

function Read-LegacyEvents {
    if (-not (Test-Path -LiteralPath $auditPath)) { return @() }
    $raw = Get-Content -LiteralPath $auditPath -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
    $normalized = [regex]::Replace($raw.Trim(), '(?<=\})(?=\s*\{)', "`n")
    $events = @()
    foreach ($line in ($normalized -split "\r?\n")) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $events += ($line | ConvertFrom-Json) } catch {}
    }
    return @($events)
}

function Write-AuditEvents($Events) {
    $lines = @($Events | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 8 })
    $text = if ($lines.Count -gt 0) { ($lines -join [Environment]::NewLine) + [Environment]::NewLine } else { '' }
    $temp = "$auditPath.$PID.$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($temp, $text, [Text.UTF8Encoding]::new($false))
        [IO.File]::Move($temp, $auditPath, $true)
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
    }
}

function Parse-Time($Value) {
    try {
        if ($Value -is [DateTimeOffset]) { return $Value.ToUniversalTime() }
        if ($Value -is [DateTime]) { return ([DateTimeOffset]$Value).ToUniversalTime() }
        return [DateTimeOffset]::Parse([string]$Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
    } catch { return $null }
}

function Migrate-LegacyEvents {
    $events = @(Read-LegacyEvents)
    Write-AuditEvents $events
    $now = [DateTimeOffset]::UtcNow
    foreach ($event in $events) {
        $normalizedDomain = Normalize-Domain ([string]$event.domain)
        if (-not $normalizedDomain) { continue }
        $timestamp = Parse-Time $event.timestamp
        if ($null -eq $timestamp) { continue }
        $expires = if ($event.PSObject.Properties.Name -contains 'expires_at') { Parse-Time $event.expires_at } else { $timestamp.AddHours(24) }
        if ($null -eq $expires -or $expires -le $now) { continue }
        $marker = [ordered]@{
            version = 1
            domain = $normalizedDomain
            status = if ($event.status) { [string]$event.status } else { 'blocked-security' }
            reason = if ($event.reason) { [string]$event.reason } else { 'Migrated legacy circuit-breaker event.' }
            job_id = if ($event.job_id) { [string]$event.job_id } else { $null }
            company = if ($event.company) { [string]$event.company } else { $null }
            first_signal_at = $timestamp.ToString('o')
            updated_at = $timestamp.ToString('o')
            expires_at = $expires.ToString('o')
        }
        Write-JsonAtomic (Get-MarkerPath $normalizedDomain) $marker
    }
    return @($events).Count
}

if ($Action -eq 'MigrateLegacy') {
    $count = Migrate-LegacyEvents
    if ($null -ne $mutationLock) { $mutationLock.Dispose() }
    [ordered]@{ status='migrated'; events=$count; marker_root=$markerRoot; audit=$auditPath } | ConvertTo-Json -Compress
    exit 0
}

$normalized = Normalize-Domain $Domain
if ($Action -in @('Record','Clear') -and -not $normalized) { throw "$Action requires -Domain." }

if ($Action -eq 'Record') {
    if ([string]::IsNullOrWhiteSpace($Reason)) { throw 'Record requires -Reason.' }
    $events = @(Read-LegacyEvents)
    $now = [DateTimeOffset]::UtcNow
    $expires = $now.AddHours([Math]::Max(1, $DurationHours))
    $event = [ordered]@{
        timestamp = $now.ToString('o')
        domain = $normalized
        status = $Status
        reason = $Reason.Trim()
        job_id = if ($JobId) { $JobId } else { $null }
        company = if ($Company) { $Company } else { $null }
        expires_at = $expires.ToString('o')
    }
    $events += [pscustomobject]$event
    Write-AuditEvents $events
    $markerPath = Get-MarkerPath $normalized
    $prior = if (Test-Path -LiteralPath $markerPath) { try { Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json } catch { $null } } else { $null }
    $marker = [ordered]@{
        version = 1
        domain = $normalized
        status = $Status
        reason = $Reason.Trim()
        job_id = if ($JobId) { $JobId } else { $null }
        company = if ($Company) { $Company } else { $null }
        first_signal_at = if ($prior -and $prior.first_signal_at) { $prior.first_signal_at } else { $now.ToString('o') }
        updated_at = $now.ToString('o')
        expires_at = $expires.ToString('o')
    }
    Write-JsonAtomic $markerPath $marker
    if ($null -ne $mutationLock) { $mutationLock.Dispose() }
    [ordered]@{ status='recorded'; domain=$normalized; active=$true; expires_at=$marker.expires_at; marker=$markerPath } | ConvertTo-Json -Compress
    exit 0
}

if ($Action -eq 'Clear') {
    $markerPath = Get-MarkerPath $normalized
    if (Test-Path -LiteralPath $markerPath) { Remove-Item -LiteralPath $markerPath -Force }
    if ($null -ne $mutationLock) { $mutationLock.Dispose() }
    [ordered]@{ status='cleared'; domain=$normalized; active=$false } | ConvertTo-Json -Compress
    exit 0
}

$now = [DateTimeOffset]::UtcNow
$active = @()
foreach ($file in Get-ChildItem -LiteralPath $markerRoot -Filter '*.json' -File -ErrorAction SilentlyContinue) {
    try {
        $marker = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
        $markerDomain = Normalize-Domain ([string]$marker.domain)
        if ($normalized -and $markerDomain -ne $normalized -and -not $normalized.EndsWith(".$markerDomain", [StringComparison]::OrdinalIgnoreCase)) { continue }
        $expires = Parse-Time $marker.expires_at
        if ($null -eq $expires -or $expires -gt $now) {
            $active += [ordered]@{
                domain = $markerDomain
                status = $marker.status
                reason = $marker.reason
                job_id = $marker.job_id
                company = $marker.company
                first_signal_at = $marker.first_signal_at
                expires_at = if ($expires) { $expires.ToString('o') } else { $null }
            }
        }
    } catch {}
}
[ordered]@{ status='ok'; domain=if ($normalized) { $normalized } else { $null }; active=@($active).Count -gt 0; circuits=@($active) } | ConvertTo-Json -Depth 8 -Compress
