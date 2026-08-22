[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$JobId,
    [Parameter(Mandatory=$true)][string]$Company,
    [Parameter(Mandatory=$true)][string]$Title,
    [string]$JobUrl = '',
    [string]$Location = '',
    [string]$Source = '',
    [string]$DiscoveryLane = '',
    [string]$SearchQuery = '',
    [string]$Description = '',
    [string]$PostedAt = '',
    [string]$ExternalId = '',
    [string]$MetadataJson = '',
    [string]$Workspace = (Get-Location).Path,
    [switch]$Structured
)

$ErrorActionPreference = 'Stop'

# Treat an explicitly empty -Workspace exactly like an omitted one.
# This matters when callers pass an unset PowerShell variable such as -Workspace "$workspace".
if ([string]::IsNullOrWhiteSpace($Workspace)) {
    $Workspace = (Get-Location).Path
}


function Convert-ToSlug([string]$Text) {
    $slug = $Text.ToLowerInvariant() -replace '[^a-z0-9]+','-'
    $slug = $slug.Trim('-')
    if ($slug.Length -gt 70) { $slug = $slug.Substring(0,70).Trim('-') }
    if ([string]::IsNullOrWhiteSpace($slug)) { return 'job' }
    return $slug
}

function Emit-Result([string]$Status, [string]$Path = '', [string]$Reason = '', [string]$MatchedJobId = '') {
    if ($Structured) {
        [ordered]@{
            status = $Status
            job_id = $JobId
            path = if ([string]::IsNullOrWhiteSpace($Path)) { $null } else { $Path }
            reason = if ([string]::IsNullOrWhiteSpace($Reason)) { $null } else { $Reason }
            matched_job_id = if ([string]::IsNullOrWhiteSpace($MatchedJobId)) { $null } else { $MatchedJobId }
        } | ConvertTo-Json -Compress
        return
    }
    switch ($Status) {
        'created' { Write-Output $Path }
        'existing' { Write-Output $Path }
        'duplicate' { Write-Output "DUPLICATE:${JobId}:${Reason}:${MatchedJobId}" }
        'rejected' { Write-Output "REJECTED:${JobId}:${Reason}" }
    }
}

$slug = Convert-ToSlug "$Company-$Title"
$queueRoot = Join-Path $Workspace '.job-apply-autopilot\queue'
$generatedRoot = Join-Path $Workspace '.job-apply-autopilot\generated'
$runtimeRoot = Join-Path $Workspace '.job-apply-autopilot'
if (-not (Test-Path -LiteralPath $runtimeRoot)) {
    throw "No job-apply-autopilot runtime at $runtimeRoot"
}
New-Item -ItemType Directory -Force -Path $queueRoot | Out-Null

$qualityCandidate = [ordered]@{ job_id=$JobId; company=$Company; title=$Title; location=$Location; job_url=$JobUrl; source_url=$JobUrl; source=$Source; discovery_lane=$DiscoveryLane; description=$Description; posted_at=$PostedAt; external_id=$ExternalId }
$qualityArgs = @{ JobJson = ($qualityCandidate | ConvertTo-Json -Compress -Depth 8) }
if ($MetadataJson) { $qualityArgs.MetadataJson = $MetadataJson }
$quality = (& (Join-Path $PSScriptRoot 'check-job-quality.ps1') @qualityArgs | Select-Object -Last 1) | ConvertFrom-Json
if (-not [bool]$quality.allowed) {
    & (Join-Path $PSScriptRoot 'log-decision.ps1') -JobId $JobId -Status 'skipped-job-quality' -ReasonCode ([string]$quality.reason_code) `
        -Company $Company -Title $Title -Location $Location -JobUrl $JobUrl -Source $Source -Notes ([string]$quality.evidence) -Workspace $Workspace | Out-Null
    Emit-Result 'rejected' -Reason ([string]$quality.reason_code)
    exit 0
}

# Single persistent-state dedupe scan covers exact-ID and semantic matches.
$dedupeScript = Join-Path $PSScriptRoot 'dedupe-jobs.ps1'
$candidateJson = @($qualityCandidate) | ConvertTo-Json -Compress -Depth 8
$dedupe = (& $dedupeScript -CandidatesJson $candidateJson -Workspace $Workspace | Select-Object -Last 1) | ConvertFrom-Json
$match = @($dedupe | Where-Object { $_.job_id -eq $JobId }) | Select-Object -First 1
if ($match) {
    if ([string]$match.seen -eq $true) {
        $reason = [string]$match.reason
        if ($reason -like 'exact-*') {
            Emit-Result 'existing' -Reason $reason -MatchedJobId ([string]$match.matched_job_id)
        } else {
            if ($reason -notlike 'exact-*') {
                & (Join-Path $PSScriptRoot 'log-decision.ps1') -JobId $JobId -Status 'skipped-duplicate' `
                    -ReasonCode $reason -Company $Company -Title $Title -Location $Location `
                    -JobUrl $JobUrl -Source $Source -Notes "Matches $($match.matched_job_id)." -Workspace $Workspace | Out-Null
            }
            Emit-Result 'duplicate' -Reason $reason -MatchedJobId ([string]$match.matched_job_id)
        }
        exit 0
    }
}

# Validate MetadataJson before creating anything so malformed JSON cannot leave
# a partially initialized work item behind.
$parsedMetadata = $null
if (-not [string]::IsNullOrWhiteSpace($MetadataJson)) {
    try { $parsedMetadata = $MetadataJson | ConvertFrom-Json } catch {
        throw 'metadata-json-invalid'
    }
}

$workDir = Join-Path $queueRoot "$JobId-$slug"
New-Item -ItemType Directory -Force -Path $workDir | Out-Null

$job = [ordered]@{
    job_id = $JobId
    company = $Company
    title = $Title
    location = $Location
    job_url = $JobUrl
    source = $Source
    discovery_lane = $DiscoveryLane
    search_query = $SearchQuery
    description = $Description
    posted_at = $PostedAt
    external_id = $ExternalId
    created_at = (Get-Date).ToUniversalTime().ToString('o')
    status = if ([string]::IsNullOrWhiteSpace($Description)) {
        'captured-awaiting-source-and-assessment'
    } else {
        'captured-awaiting-assessment'
    }
}
$job | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $workDir 'job.json') -Encoding UTF8

$assessment = [ordered]@{
    policy_version = '6.4'
    job_id = $JobId
    status = 'pending'
    score = $null
    trust_class = ''
    role_family = ''
    eligibility_state = 'UNCLEAR'
    needs_external_research = $false
    needs_candidate_evidence = $false
    hard_gates = [ordered]@{
        integrity = $false
        eligibility = $false
        role_family = $false
        mandatory_requirements = $false
        truth_feasibility = $false
    }
}
$assessment | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $workDir 'assessment.json') -Encoding UTF8

$sourcePath = Join-Path $workDir 'source.md'
if (-not [string]::IsNullOrWhiteSpace($Description)) {
    $sourceContent = @"
# $Title

Company: $Company
Location: $Location
Source: $Source
URL: $JobUrl
Posted: $PostedAt

## Job Description

$Description
"@
    Set-Content -LiteralPath $sourcePath -Value $sourceContent -Encoding UTF8
}
elseif (-not (Test-Path -LiteralPath $sourcePath)) {
    Set-Content -LiteralPath $sourcePath -Value "# Captured job source`n`nCoordinator: replace this placeholder with the full JD and source/location evidence before invoking an assessor.`n" -Encoding UTF8
}

if ($null -ne $parsedMetadata) {
    $parsedMetadata |
        ConvertTo-Json -Depth 30 |
        Set-Content -LiteralPath (Join-Path $workDir 'source-metadata.json') -Encoding UTF8
}

Emit-Result 'created' -Path $workDir
