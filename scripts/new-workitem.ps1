[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$JobId,
    [Parameter(Mandatory=$true)][string]$Company,
    [Parameter(Mandatory=$true)][string]$Title,
    [string]$JobUrl = '',
    [string]$Location = '',
    [string]$Source = '',
    [string]$Workspace = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'

function Convert-ToSlug([string]$Text) {
    $slug = $Text.ToLowerInvariant() -replace '[^a-z0-9]+','-'
    $slug = $slug.Trim('-')
    if ($slug.Length -gt 70) { $slug = $slug.Substring(0,70).Trim('-') }
    if ([string]::IsNullOrWhiteSpace($slug)) { return 'job' }
    return $slug
}

$slug = Convert-ToSlug "$Company-$Title"
$queueRoot = Join-Path $Workspace '.job-apply-autopilot\queue'
$workDir = Join-Path $queueRoot "$JobId-$slug"
New-Item -ItemType Directory -Force -Path $workDir | Out-Null

$job = [ordered]@{
    job_id = $JobId
    company = $Company
    title = $Title
    location = $Location
    job_url = $JobUrl
    source = $Source
    created_at = (Get-Date).ToUniversalTime().ToString('o')
    status = 'captured-awaiting-source-and-assessment'
}
$job | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $workDir 'job.json') -Encoding UTF8

$assessment = [ordered]@{
    job_id = $JobId
    trust_class = ''
    role_family = ''
    eligibility_state = 'UNCLEAR'
    eligibility_evidence = @()
    needs_external_research = $false
    hard_gates = [ordered]@{
        integrity = $false
        eligibility = $false
        role_family = $false
        mandatory_requirements = $false
        truth_feasibility = $false
    }
    failure_reason = ''
    status = 'pending'
}
$assessment | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $workDir 'assessment.json') -Encoding UTF8

$fitMap = [ordered]@{
    job_id = $JobId
    requirements = @()
    score = $null
    status = 'pending'
}
$fitMap | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $workDir 'fit-map.json') -Encoding UTF8

$sourcePath = Join-Path $workDir 'source.md'
if (-not (Test-Path -LiteralPath $sourcePath)) {
    Set-Content -LiteralPath $sourcePath -Value "# Captured job source`n`nCoordinator: replace this placeholder with the full JD and source/location evidence before invoking an assessor.`n" -Encoding UTF8
}

Write-Output $workDir
