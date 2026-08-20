[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$EvidenceFile,
    [string]$Workspace = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Workspace)) {
    $Workspace = (Get-Location).Path
}
if ([string]::IsNullOrWhiteSpace($EvidenceFile)) {
    throw 'EvidenceFile is required.'
}

$evidencePath = (Resolve-Path -LiteralPath $EvidenceFile).Path
$report = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json

# If caller did not provide a useful workspace but the report lives under the runtime queue,
# derive the workspace from ...\.job-apply-autopilot\queue\<job>\candidate-evidence-research.json.
$marker = [IO.Path]::DirectorySeparatorChar + '.job-apply-autopilot' + [IO.Path]::DirectorySeparatorChar + 'queue' + [IO.Path]::DirectorySeparatorChar
if (-not [string]::IsNullOrWhiteSpace($evidencePath) -and $evidencePath.Contains($marker)) {
    $prefix = $evidencePath.Substring(0, $evidencePath.IndexOf($marker))
    if ([string]::IsNullOrWhiteSpace($Workspace) -or -not (Test-Path -LiteralPath (Join-Path $Workspace '.job-apply-autopilot'))) {
        $Workspace = $prefix
    }
}

$root = Join-Path $Workspace '.job-apply-autopilot'
New-Item -ItemType Directory -Force -Path $root | Out-Null
$cachePath = Join-Path $root 'candidate-evidence.json'

if (Test-Path -LiteralPath $cachePath) {
    try { $cache = Get-Content -LiteralPath $cachePath -Raw | ConvertFrom-Json } catch { $cache = $null }
} else {
    $cache = $null
}

$claims = @()
$sources = @()
if ($cache) {
    if ($cache.claims) { $claims = @($cache.claims) }
    if ($cache.sources) { $sources = @($cache.sources) }
}

function Get-ClaimKey($claim) {
    if ($claim.evidence_id) { return 'id:' + [string]$claim.evidence_id }
    $cap = if ($claim.capability) { [string]$claim.capability } else { '' }
    $url = if ($claim.source_url) { [string]$claim.source_url } else { '' }
    $obs = if ($claim.observed_evidence) { [string]$claim.observed_evidence } else { '' }
    return 'fallback:' + $cap + '|' + $url + '|' + $obs
}

$index = @{}
foreach ($claim in $claims) {
    $index[(Get-ClaimKey $claim)] = $claim
}

$added = 0
$updated = 0
foreach ($finding in @($report.findings)) {
    if ($null -eq $finding) { continue }
    $key = Get-ClaimKey $finding
    if ($index.ContainsKey($key)) {
        $index[$key] = $finding
        $updated++
    } else {
        $index[$key] = $finding
        $added++
    }
}

$sourceSet = @{}
foreach ($src in $sources) {
    if ($null -eq $src) { continue }
    $k = if ($src -is [string]) { [string]$src } elseif ($src.url) { [string]$src.url } elseif ($src.source_url) { [string]$src.source_url } else { ($src | ConvertTo-Json -Compress -Depth 5) }
    $sourceSet[$k] = $src
}
foreach ($src in @($report.sources_checked)) {
    if ($null -eq $src) { continue }
    $k = if ($src -is [string]) { [string]$src } elseif ($src.url) { [string]$src.url } elseif ($src.source_url) { [string]$src.source_url } else { ($src | ConvertTo-Json -Compress -Depth 5) }
    $sourceSet[$k] = $src
}

$out = [ordered]@{
    version = 1
    refreshed_at = (Get-Date).ToUniversalTime().ToString('o')
    refresh_reason = 'merged-targeted-job-evidence'
    sources = @($sourceSet.Values)
    claims = @($index.Values)
}
$out | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $cachePath -Encoding UTF8

[ordered]@{
    cache_path = $cachePath
    evidence_file = $evidencePath
    job_id = if ($report.job_id) { [string]$report.job_id } else { $null }
    added = $added
    updated = $updated
    total_claims = @($index.Values).Count
} | ConvertTo-Json -Depth 6
