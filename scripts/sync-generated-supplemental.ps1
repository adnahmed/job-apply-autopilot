[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$SourceWorkItemDir,
    [Parameter(Mandatory=$true)][string]$Workspace
)

$ErrorActionPreference = 'Stop'
$SourceWorkItemDir = (Resolve-Path -LiteralPath $SourceWorkItemDir).Path
$Workspace = (Resolve-Path -LiteralPath $Workspace).Path

function Read-JsonSafe([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json } catch { return $null }
}

function Write-JsonAtomic([string]$Path, $Value, [int]$Depth = 10) {
    $temp = "$Path.$PID.$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $temp -Encoding UTF8
        [IO.File]::Move($temp, $Path, $true)
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
    }
}

$jobPath = Join-Path $SourceWorkItemDir 'job.json'
$sourceJob = Read-JsonSafe $jobPath
if (-not $sourceJob -or -not [string]$sourceJob.job_id) {
    [ordered]@{status='not-promoted'} | ConvertTo-Json -Compress
    exit 0
}
$jobId = [string]$sourceJob.job_id

$generatedRoot = Join-Path $Workspace '.job-apply-autopilot\generated'
if (-not (Test-Path -LiteralPath $generatedRoot)) {
    [ordered]@{status='not-promoted'} | ConvertTo-Json -Compress
    exit 0
}

$generatedDir = $null
$generatedItems = Get-ChildItem -LiteralPath $generatedRoot -Directory -ErrorAction SilentlyContinue
foreach ($item in $generatedItems) {
    $candidateJob = Read-JsonSafe (Join-Path $item.FullName 'job.json')
    if ($candidateJob -and [string]$candidateJob.job_id -eq $jobId) {
        $generatedDir = $item.FullName
        break
    }
}

if (-not $generatedDir) {
    [ordered]@{status='not-promoted'} | ConvertTo-Json -Compress
    exit 0
}

$metadataSynced = $false
$answerPlanSynced = $false
$routeStatus = 'unchanged'

# source-metadata.json
$sourceMetadata = Join-Path $SourceWorkItemDir 'source-metadata.json'
$generatedMetadata = Join-Path $generatedDir 'source-metadata.json'
if (Test-Path -LiteralPath $sourceMetadata) {
    $content = Get-Content -LiteralPath $sourceMetadata -Raw
    try { $parsed = $content | ConvertFrom-Json } catch { $parsed = $null }
    if ($parsed) { Write-JsonAtomic $generatedMetadata $parsed; $metadataSynced = $true }
}

# application-answer-plan.json
$sourceAnswerPlan = Join-Path $SourceWorkItemDir 'application-answer-plan.json'
$generatedAnswerPlan = Join-Path $generatedDir 'application-answer-plan.json'
if (Test-Path -LiteralPath $sourceAnswerPlan) {
    $content = Get-Content -LiteralPath $sourceAnswerPlan -Raw
    try { $parsed = $content | ConvertFrom-Json } catch { $parsed = $null }
    if ($parsed) { Write-JsonAtomic $generatedAnswerPlan $parsed; $answerPlanSynced = $true }
}

# application-route.json - smart merge
$sourceRoute = Join-Path $SourceWorkItemDir 'application-route.json'
$generatedRoute = Join-Path $generatedDir 'application-route.json'
$sourceRouteObj = Read-JsonSafe $sourceRoute
$generatedRouteObj = Read-JsonSafe $generatedRoute

$sourceRouteType = if ($sourceRouteObj -and $sourceRouteObj.route) { [string]$sourceRouteObj.route } else { '' }
$generatedRouteType = if ($generatedRouteObj -and $generatedRouteObj.route) { [string]$generatedRouteObj.route } else { '' }
$sourceResolvedAt = if ($sourceRouteObj -and $sourceRouteObj.resolved_at) { [DateTimeOffset]$sourceRouteObj.resolved_at } else { [DateTimeOffset]::MinValue }
$generatedResolvedAt = if ($generatedRouteObj -and $generatedRouteObj.resolved_at) { [DateTimeOffset]$generatedRouteObj.resolved_at } else { [DateTimeOffset]::MinValue }

$shouldUpdateRoute = $false
if (-not $generatedRouteType -and $sourceRouteType) {
    $shouldUpdateRoute = $true
    $routeStatus = 'updated-from-source'
} elseif ($generatedRouteType -eq 'unresolved' -and $sourceRouteType -in @('external','email','linkedin-easy-apply')) {
    $shouldUpdateRoute = $true
    $routeStatus = 'updated-from-source'
} elseif ($generatedRouteType -in @('external','email','linkedin-easy-apply') -and $generatedResolvedAt -gt $sourceResolvedAt) {
    $shouldUpdateRoute = $false
    $routeStatus = 'kept-generated'
} elseif ($generatedRouteType -in @('external','email','linkedin-easy-apply')) {
    $shouldUpdateRoute = $false
    $routeStatus = 'kept-generated'
}

if ($shouldUpdateRoute -and $sourceRouteObj) {
    Write-JsonAtomic $generatedRoute $sourceRouteObj
}

[ordered]@{
    status = 'synced'
    job_id = $jobId
    metadata = $metadataSynced
    answer_plan = $answerPlanSynced
    route = $routeStatus
} | ConvertTo-Json -Compress