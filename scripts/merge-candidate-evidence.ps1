[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$EvidenceFile,
    [string]$Workspace = (Get-Location).Path
)
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Workspace)) { $Workspace = (Get-Location).Path }
if ([string]::IsNullOrWhiteSpace($EvidenceFile)) { throw 'EvidenceFile is required.' }
$evidencePath = (Resolve-Path -LiteralPath $EvidenceFile).Path
$report = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json

$marker = [IO.Path]::DirectorySeparatorChar + '.job-apply-autopilot' + [IO.Path]::DirectorySeparatorChar + 'queue' + [IO.Path]::DirectorySeparatorChar
if ($evidencePath.Contains($marker)) {
    $prefix = $evidencePath.Substring(0, $evidencePath.IndexOf($marker))
    if (-not (Test-Path -LiteralPath (Join-Path $Workspace '.job-apply-autopilot'))) { $Workspace = $prefix }
}
$cachePath = Join-Path (Join-Path $Workspace '.job-apply-autopilot') 'candidate-evidence.json'
$existing = @()
if (Test-Path -LiteralPath $cachePath) {
    try {
        $cache = Get-Content -LiteralPath $cachePath -Raw | ConvertFrom-Json
        if ($cache.claims) { $existing = @($cache.claims) }
    } catch {}
}

function Normalize-Claim($x) {
    if ($null -eq $x) { return $null }
    $cap = [string]$x.capability
    $url = [string]$x.source_url
    $class = if ($x.evidence_class) { [string]$x.evidence_class } elseif ($x.fit_strength_hint) { [string]$x.fit_strength_hint } else { 'DIRECT' }
    if ([string]::IsNullOrWhiteSpace($cap) -or [string]::IsNullOrWhiteSpace($url)) { return $null }
    if ($class -in @('NONE','UNRESOLVED')) { return $null }
    $obs = if ($x.observed) { [string]$x.observed } elseif ($x.observed_evidence) { [string]$x.observed_evidence } else { '' }
    if ($obs.Length -gt 240) { $obs = $obs.Substring(0,240) }
    $allowed = if ($x.allowed_resume_claim) { [string]$x.allowed_resume_claim } else { '' }
    if ($allowed.Length -gt 240) { $allowed = $allowed.Substring(0,240) }
    return [ordered]@{
        capability = $cap
        evidence_class = $class
        source_url = $url
        observed = $obs
        resume_eligible = if ($null -ne $x.resume_eligible) { [bool]$x.resume_eligible } else { $false }
        allowed_resume_claim = $allowed
        verified_at = (Get-Date).ToUniversalTime().ToString('o')
    }
}

$index = @{}
foreach ($x in $existing) {
    $c = Normalize-Claim $x
    if ($null -ne $c) { $index[($c.capability.ToLowerInvariant() + '|' + $c.source_url)] = $c }
}
$added = 0
foreach ($x in @($report.findings)) {
    $c = Normalize-Claim $x
    if ($null -eq $c) { continue }
    $key = $c.capability.ToLowerInvariant() + '|' + $c.source_url
    if (-not $index.ContainsKey($key)) { $added++ }
    $index[$key] = $c
}

$out = [ordered]@{
    version = 2
    refreshed_at = (Get-Date).ToUniversalTime().ToString('o')
    claims = @($index.Values | Sort-Object capability, source_url)
}
$out | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $cachePath -Encoding UTF8
[ordered]@{ cache_path=$cachePath; job_id=$report.job_id; added=$added; total_claims=@($index.Values).Count } | ConvertTo-Json -Compress
