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
    [Parameter(Mandatory=$true)][string]$Description,
    [string]$PostedAt = '',
    [string]$ExternalId = '',
    [string]$MetadataJson = '',
    [string]$Route = '',
    [string]$RouteTarget = '',
    [string]$RouteEvidence = '',
    [string]$Workspace = (Get-Location).Path,
    [string]$ProfilePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'profile.yaml')
)

$ErrorActionPreference = 'Stop'

function Emit-Result([string]$Status, [string]$JobIdOut = '', [string]$Path = '', [string]$MatchedJobId = '', [string]$Reason = '', [string]$EnrichmentStatus = '', [string]$EnrichmentError = '', [string]$RouteOut = '', [string]$NextStage = '', [bool]$SourceReady = $false, [bool]$MetadataWritten = $false) {
    $result = [ordered]@{ status = $Status; job_id = $JobIdOut }
    if ($Status -eq 'created') {
        $result['path'] = $Path
        $result['source_ready'] = $SourceReady
        $result['metadata_written'] = $MetadataWritten
        $result['enrichment_status'] = $EnrichmentStatus
        if (-not [string]::IsNullOrWhiteSpace($EnrichmentError)) { $result['enrichment_error'] = $EnrichmentError }
        $result['route'] = if ([string]::IsNullOrWhiteSpace($RouteOut)) { $null } else { $RouteOut }
        $result['next_stage'] = $NextStage
    } else {
        if (-not [string]::IsNullOrWhiteSpace($MatchedJobId)) { $result['matched_job_id'] = $MatchedJobId }
        if (-not [string]::IsNullOrWhiteSpace($Reason)) { $result['reason'] = $Reason }
        if (-not [string]::IsNullOrWhiteSpace($Path)) { $result['path'] = $Path }
    }
    $result | ConvertTo-Json -Compress | Write-Output
}

# Treat an explicitly empty -Workspace exactly like an omitted one.
if ([string]::IsNullOrWhiteSpace($Workspace)) {
    $Workspace = (Get-Location).Path
}

# Step A: Call new-workitem.ps1 -Structured passing Description and MetadataJson
$newWorkItemScript = Join-Path $PSScriptRoot 'new-workitem.ps1'
$creationArgs = @{
    JobId = $JobId
    Company = $Company
    Title = $Title
    JobUrl = $JobUrl
    Location = $Location
    Source = $Source
    DiscoveryLane = $DiscoveryLane
    SearchQuery = $SearchQuery
    Description = $Description
    PostedAt = $PostedAt
    ExternalId = $ExternalId
    MetadataJson = $MetadataJson
    Workspace = $Workspace
    Structured = $true
}
$creationResult = (& $newWorkItemScript @creationArgs | Select-Object -Last 1) | ConvertFrom-Json

if (-not $creationResult) {
    Emit-Result 'failed' -JobIdOut $JobId -Reason 'creation-result-empty'
    exit 0
}

$creationStatus = [string]$creationResult.status
$workItemPath = if ($creationResult.path) { [string]$creationResult.path } else { '' }
$matchedJobId = if ($creationResult.matched_job_id) { [string]$creationResult.matched_job_id } else { '' }
$creationReason = if ($creationResult.reason) { [string]$creationResult.reason } else { '' }

# Step B: If status is existing, duplicate, rejected - return immediately
if ($creationStatus -in @('existing', 'duplicate', 'rejected')) {
    Emit-Result $creationStatus -JobIdOut $JobId -Path $workItemPath -MatchedJobId $matchedJobId -Reason $creationReason
    exit 0
}

# Step C: If status is created, call enrich-freehire-workitem.ps1 when JobUrl is a public HTTP/HTTPS URL
$enrichmentStatus = 'skipped'
$enrichmentError = ''
$sourceReady = $false
$metadataWritten = $false

if ($creationStatus -eq 'created' -and -not [string]::IsNullOrWhiteSpace($JobUrl)) {
    $isPublicHttp = $false
    try {
        $uri = [Uri]$JobUrl
        $isPublicHttp = ($uri.Scheme -eq 'http' -or $uri.Scheme -eq 'https') -and $uri.IsAbsoluteUri
    } catch {}

    if ($isPublicHttp) {
        $enrichScript = Join-Path $PSScriptRoot 'enrich-freehire-workitem.ps1'
        if (Test-Path -LiteralPath $enrichScript) {
            try {
                & $enrichScript -WorkItemDir $workItemPath -Workspace $Workspace -ProfilePath $ProfilePath | Out-Null
                $enrichmentStatus = 'enriched'
            } catch {
                $enrichmentStatus = 'enrichment-error'
                $enrichmentError = $_.Exception.Message
            }
        }
    }
}

# Step D: If Route is non-empty, validate and call set-application-route.ps1
$routeResult = $null
if (-not [string]::IsNullOrWhiteSpace($Route)) {
    $validRoutes = @('external', 'linkedin-easy-apply', 'email', 'unresolved')
    if ($Route -in $validRoutes) {
        if ([string]::IsNullOrWhiteSpace($RouteTarget) -or [string]::IsNullOrWhiteSpace($RouteEvidence)) {
            Emit-Result 'rejected' -JobIdOut $JobId -Path $workItemPath -Reason 'route-target-evidence-required'
            exit 0
        } else {
            $setRouteScript = Join-Path $PSScriptRoot 'set-application-route.ps1'
            if (Test-Path -LiteralPath $setRouteScript) {
                try {
                    & $setRouteScript -WorkItemDir $workItemPath -Route $Route -Target $RouteTarget -Evidence $RouteEvidence | Out-Null
                    $routeResult = $Route
                } catch {
                    Emit-Result 'rejected' -JobIdOut $JobId -Path $workItemPath -Reason "route-write-failed:$($_.Exception.Message)"
                    exit 0
                }
            }
        }
    } else {
        Emit-Result 'rejected' -JobIdOut $JobId -Path $workItemPath -Reason 'route-invalid'
        exit 0
    }
}

# Step E: Return compact JSON object
if ($creationStatus -eq 'created') {
    # Verify source.md and source-metadata.json exist
    $sourcePath = Join-Path $workItemPath 'source.md'
    $metadataPath = Join-Path $workItemPath 'source-metadata.json'
    $sourceReady = Test-Path -LiteralPath $sourcePath
    $metadataWritten = Test-Path -LiteralPath $metadataPath

    Emit-Result 'created' -JobIdOut $JobId -Path $workItemPath -SourceReady $sourceReady -MetadataWritten $metadataWritten -EnrichmentStatus $enrichmentStatus -EnrichmentError $enrichmentError -RouteOut $routeResult -NextStage 'assessment_pending'
} else {
    Emit-Result $creationStatus -JobIdOut $JobId -Path $workItemPath -MatchedJobId $matchedJobId -Reason $creationReason
}
