[CmdletBinding()]
param([string]$Workspace = (Get-Location).Path)
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Workspace)) { $Workspace = (Get-Location).Path }
$path = Join-Path (Join-Path $Workspace '.job-apply-autopilot') 'candidate-evidence.json'
if (-not (Test-Path -LiteralPath $path)) { Write-Output 'candidate evidence cache absent'; exit 0 }
try { $old = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json } catch { Write-Output 'candidate evidence cache unreadable; left unchanged'; exit 0 }
$index = @{}
foreach ($x in @($old.claims)) {
    if ($null -eq $x) { continue }
    $cap = [string]$x.capability
    $url = [string]$x.source_url
    $class = if ($x.evidence_class) { [string]$x.evidence_class } elseif ($x.fit_strength_hint) { [string]$x.fit_strength_hint } else { 'DIRECT' }
    if ([string]::IsNullOrWhiteSpace($cap) -or [string]::IsNullOrWhiteSpace($url) -or $class -in @('NONE','UNRESOLVED')) { continue }
    $obs = if ($x.observed) { [string]$x.observed } elseif ($x.observed_evidence) { [string]$x.observed_evidence } else { '' }
    if ($obs.Length -gt 240) { $obs = $obs.Substring(0,240) }
    $allowed = if ($x.allowed_resume_claim) { [string]$x.allowed_resume_claim } else { '' }
    if ($allowed.Length -gt 240) { $allowed = $allowed.Substring(0,240) }
    $claim = [ordered]@{
        capability = $cap
        evidence_class = $class
        source_url = $url
        observed = $obs
        resume_eligible = if ($null -ne $x.resume_eligible) { [bool]$x.resume_eligible } else { $false }
        allowed_resume_claim = $allowed
        verified_at = if ($x.verified_at) { [string]$x.verified_at } else { [string]$old.refreshed_at }
    }
    $index[$cap.ToLowerInvariant() + '|' + $url] = $claim
}
$new = [ordered]@{ version=2; refreshed_at=$old.refreshed_at; claims=@($index.Values | Sort-Object capability,source_url) }
$new | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
Write-Output ("candidate evidence compacted: {0} reusable claims" -f @($index.Values).Count)
