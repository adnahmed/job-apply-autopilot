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

$qualityCandidate = [ordered]@{ job_id=$JobId; company=$Company; title=$Title; location=$Location; job_url=$JobUrl; source=$Source; discovery_lane=$DiscoveryLane }
$quality = (& (Join-Path $PSScriptRoot 'check-job-quality.ps1') -JobJson ($qualityCandidate | ConvertTo-Json -Compress -Depth 6) | Select-Object -Last 1) | ConvertFrom-Json
if (-not [bool]$quality.allowed) {
    & (Join-Path $PSScriptRoot 'log-decision.ps1') -JobId $JobId -Status 'skipped-job-quality' -ReasonCode ([string]$quality.reason_code) `
        -Company $Company -Title $Title -Location $Location -JobUrl $JobUrl -Source $Source -Notes ([string]$quality.evidence) -Workspace $Workspace | Out-Null
    Emit-Result 'rejected' -Reason ([string]$quality.reason_code)
    exit 0
}

# Exact-ID creation is idempotent. Never overwrite an assessment or source captured by an earlier slice.
foreach ($base in @($queueRoot, $generatedRoot)) {
    if (-not (Test-Path -LiteralPath $base)) { continue }
    foreach ($existing in Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue) {
        $existingJobPath = Join-Path $existing.FullName 'job.json'
        if (-not (Test-Path -LiteralPath $existingJobPath)) { continue }
        try {
            $existingJob = Get-Content -LiteralPath $existingJobPath -Raw | ConvertFrom-Json
            if ([string]$existingJob.job_id -eq $JobId) {
                Emit-Result 'existing' -Path $existing.FullName -Reason 'exact-job-id' -MatchedJobId $JobId
                exit 0
            }
        } catch {}
    }
}

# Guard against reposts/region variants with a new job ID after the same company/title was
# already submitted or is already active. Exact job-ID dedupe alone allowed duplicate applications.
$dedupeScript = Join-Path $PSScriptRoot 'dedupe-jobs.ps1'
$candidateJson = @([ordered]@{ job_id=$JobId; company=$Company; title=$Title }) | ConvertTo-Json -Compress
$dedupe = (& $dedupeScript -CandidatesJson $candidateJson -Workspace $Workspace | Select-Object -Last 1) | ConvertFrom-Json
$duplicate = @($dedupe | Where-Object { $_.job_id -eq $JobId -and $_.seen }) | Select-Object -First 1
if ($duplicate) {
    if ([string]$duplicate.reason -notlike 'exact-*') {
        & (Join-Path $PSScriptRoot 'log-decision.ps1') -JobId $JobId -Status 'skipped-duplicate' `
            -ReasonCode ([string]$duplicate.reason) -Company $Company -Title $Title -Location $Location `
            -JobUrl $JobUrl -Source $Source -Notes "Matches $($duplicate.matched_job_id)." -Workspace $Workspace | Out-Null
    }
    Emit-Result 'duplicate' -Reason ([string]$duplicate.reason) -MatchedJobId ([string]$duplicate.matched_job_id)
    exit 0
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
    created_at = (Get-Date).ToUniversalTime().ToString('o')
    status = 'captured-awaiting-source-and-assessment'
}
$job | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $workDir 'job.json') -Encoding UTF8

$assessment = [ordered]@{
    policy_version = '6.3'
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
if (-not (Test-Path -LiteralPath $sourcePath)) {
    Set-Content -LiteralPath $sourcePath -Value "# Captured job source`n`nCoordinator: replace this placeholder with the full JD and source/location evidence before invoking an assessor.`n" -Encoding UTF8
}

Emit-Result 'created' -Path $workDir
