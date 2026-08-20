[CmdletBinding()]
param([string]$Workspace = (Get-Location).Path)

$ErrorActionPreference = 'Stop'

# Treat an explicitly empty -Workspace exactly like an omitted one.
# This matters when callers pass an unset PowerShell variable such as -Workspace "$workspace".
if ([string]::IsNullOrWhiteSpace($Workspace)) {
    $Workspace = (Get-Location).Path
}

$root = Join-Path $Workspace '.job-apply-autopilot'
$generated = Join-Path $root 'generated'
$queue = Join-Path $root 'queue'
$circuitDir = Join-Path $root 'domain-circuit-breakers'
New-Item -ItemType Directory -Force -Path $generated | Out-Null
New-Item -ItemType Directory -Force -Path $queue | Out-Null
New-Item -ItemType Directory -Force -Path $circuitDir | Out-Null

$appLog = Join-Path $root 'applications.jsonl'
$relocLog = Join-Path $root 'relocation-watchlist.jsonl'
$circuitLog = Join-Path $root 'domain-circuit-breakers.jsonl'
$statsPath = Join-Path $root 'campaign-stats.json'
$linkedinStatePath = Join-Path $root 'linkedin-activity-state.json'
$candidateEvidencePath = Join-Path $root 'candidate-evidence.json'

foreach ($path in @($appLog, $relocLog, $circuitLog)) {
    if (-not (Test-Path -LiteralPath $path)) { New-Item -ItemType File -Path $path | Out-Null }
}


if (-not (Test-Path -LiteralPath $statsPath)) {
    [ordered]@{ generated_at = $null; total_decisions = 0; submitted = 0; blocked = 0; skipped = 0; submission_rate = 0; statuses = @(); by_source = @(); by_discovery_lane = @() } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $statsPath -Encoding UTF8
}
if (-not (Test-Path -LiteralPath $candidateEvidencePath)) {
    [ordered]@{
        version = 2
        refreshed_at = $null
        claims = @()
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $candidateEvidencePath -Encoding UTF8
}

if (-not (Test-Path -LiteralPath $linkedinStatePath)) {
    $easyApplySeed = @()
    if (Test-Path -LiteralPath $appLog) {
        foreach ($line in Get-Content -LiteralPath $appLog) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $row = $line | ConvertFrom-Json
                $source = [string]$row.source
                $submitted = ($row.status -eq 'submitted' -or $row.submitted -eq $true)
                if ($submitted -and $source -match 'linkedin.*easy.*apply' -and $row.timestamp) {
                    $dt = [DateTimeOffset]::Parse([string]$row.timestamp).ToUniversalTime()
                    if ($dt -gt [DateTimeOffset]::UtcNow.AddHours(-24)) { $easyApplySeed += $dt.ToString('o') }
                }
            } catch {}
        }
    }
    [ordered]@{ version = 1; easy_apply_submissions = @($easyApplySeed | Sort-Object -Unique); pause_until = $null; pause_reason = $null; manual_block = $false; last_signal_at = $null; last_signal_type = $null; updated_at = (Get-Date).ToUniversalTime().ToString('o') } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $linkedinStatePath -Encoding UTF8
}
$compactScript = Join-Path $PSScriptRoot 'compact-candidate-evidence.ps1'
if (Test-Path -LiteralPath $compactScript) {
    $pwsh = (Get-Command pwsh -ErrorAction Stop).Source
    & $pwsh -NoProfile -ExecutionPolicy Bypass -File $compactScript -Workspace $Workspace | Out-Null
}

Write-Output "Workspace initialized: $root"
Write-Output "Applications: $appLog"
Write-Output "Relocation watchlist: $relocLog"
Write-Output "Domain circuit breaker events: $circuitLog"
Write-Output "Domain circuit breaker markers: $circuitDir"
Write-Output "Queue work items: $queue"
Write-Output "Generated resumes: $generated"
Write-Output "Campaign stats: $statsPath"

Write-Output "LinkedIn activity state: $linkedinStatePath"
Write-Output "Candidate evidence cache: $candidateEvidencePath"
