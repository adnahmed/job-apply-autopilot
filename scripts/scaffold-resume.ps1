[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$JobId,
    [Parameter(Mandatory=$true)][string]$Company,
    [Parameter(Mandatory=$true)][string]$Title,
    [ValidateSet('ai','backend')][string]$Canonical = 'ai',
    [string]$JobUrl = '',
    [string]$Location = '',
    [string]$Workspace = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'
$skillRoot = Split-Path -Parent $PSScriptRoot
$canonicalPath = if ($Canonical -eq 'backend') {
    Join-Path $skillRoot 'canonical\backend-platform-canonical.tex'
} else {
    Join-Path $skillRoot 'canonical\ai-applied-canonical.tex'
}

if (-not (Test-Path -LiteralPath $canonicalPath)) {
    throw "Canonical resume not found: $canonicalPath"
}

function Convert-ToSlug([string]$Text) {
    $slug = $Text.ToLowerInvariant() -replace '[^a-z0-9]+','-'
    $slug = $slug.Trim('-')
    if ($slug.Length -gt 70) { $slug = $slug.Substring(0,70).Trim('-') }
    if ([string]::IsNullOrWhiteSpace($slug)) { return 'job' }
    return $slug
}

$slug = Convert-ToSlug "$Company-$Title"
$runtimeRoot = Join-Path $Workspace '.job-apply-autopilot\generated'
$jobDir = Join-Path $runtimeRoot "$JobId-$slug"
New-Item -ItemType Directory -Force -Path $jobDir | Out-Null

$auditPath = Join-Path $jobDir 'canonical-source.tex'
$texPath = Join-Path $jobDir 'resume.tex'
Copy-Item -LiteralPath $canonicalPath -Destination $auditPath -Force
Copy-Item -LiteralPath $canonicalPath -Destination $texPath -Force

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $canonicalPath).Hash.ToLowerInvariant()
$meta = [ordered]@{
    job_id = $JobId
    company = $Company
    title = $Title
    location = $Location
    job_url = $JobUrl
    canonical = $Canonical
    canonical_path = $canonicalPath
    canonical_sha256 = $hash
    created_at = (Get-Date).ToUniversalTime().ToString('o')
    status = 'canonical-scaffolded-awaiting-fit-map-and-tailoring'
}
$meta | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $jobDir 'job.json') -Encoding UTF8

$fitMap = [ordered]@{
    job_id = $JobId
    requirements = @()
    status = 'must-be-filled-before-resume-tailoring'
}
$fitMap | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $jobDir 'fit-map.json') -Encoding UTF8

Write-Output $texPath
