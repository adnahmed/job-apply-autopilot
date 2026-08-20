[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$JobId,
    [Parameter(Mandatory=$true)][string]$Company,
    [Parameter(Mandatory=$true)][string]$Title,
    [ValidateSet('ai','backend')][string]$Canonical = 'backend',
    [string]$JobUrl = '',
    [string]$Location = '',
    [string]$Workspace = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'

# Treat an explicitly empty -Workspace exactly like an omitted one.
# This matters when callers pass an unset PowerShell variable such as -Workspace "$workspace".
if ([string]::IsNullOrWhiteSpace($Workspace)) {
    $Workspace = (Get-Location).Path
}

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
    status = 'canonical-scaffolded-awaiting-assessment-fit-map-and-tailoring'
}
$meta | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $jobDir 'job.json') -Encoding UTF8

$assessment = [ordered]@{
    job_id = $JobId
    trust_class = ''
    eligibility_state = ''
    eligibility_evidence = @()
    hard_gates = [ordered]@{
        integrity = $false
        eligibility = $false
        role_family = $false
        mandatory_requirements = $false
        truth_feasibility = $false
    }
    status = 'must-pass-hard-gates-before-score-or-tailoring'
}
$assessment | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $jobDir 'assessment.json') -Encoding UTF8

$fitMap = [ordered]@{
    job_id = $JobId
    requirements = @()
    score = $null
    status = 'must-be-filled-before-resume-tailoring'
}
$fitMap | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $jobDir 'fit-map.json') -Encoding UTF8

$tailoringAudit = [ordered]@{
    job_id = $JobId
    canonical_source = $canonicalPath
    headline = ''
    canonical_claim_ids_used = @()
    bullets_removed = @()
    bullets_reordered = @()
    aliases_introduced = @()
    material_rewrites = @()
    unsupported_terms_added = @()
    status = 'must-be-completed-before-compile'
}
$tailoringAudit | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $jobDir 'tailoring-audit.json') -Encoding UTF8

Write-Output $texPath
