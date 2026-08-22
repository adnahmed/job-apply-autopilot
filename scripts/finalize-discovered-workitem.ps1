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

# Validate route parameters before creation
$validRoutes = @('external', 'linkedin-easy-apply', 'email', 'unresolved')
if (-not [string]::IsNullOrWhiteSpace($Route)) {
    if ($Route -notin $validRoutes) {
        Emit-Result 'rejected' -JobIdOut $JobId -Reason 'route-invalid'
        exit 0
    }
    if ([string]::IsNullOrWhiteSpace($RouteTarget) -or [string]::IsNullOrWhiteSpace($RouteEvidence)) {
        Emit-Result 'rejected' -JobIdOut $JobId -Reason 'route-target-evidence-required'
        exit 0
    }
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

# Step C: If status is created, set route if provided, then launch async enrichment
$enrichmentStatus = 'skipped'
$enrichmentError = ''
$sourceReady = $false
$metadataWritten = $false
$routeResult = $null

if ($creationStatus -eq 'created') {
    # Verify source.md and source-metadata.json exist
    $sourcePath = Join-Path $workItemPath 'source.md'
    $metadataPath = Join-Path $workItemPath 'source-metadata.json'
    $sourceReady = Test-Path -LiteralPath $sourcePath
    $metadataWritten = Test-Path -LiteralPath $metadataPath

    # Set route if provided (synchronous, before enrichment)
    if (-not [string]::IsNullOrWhiteSpace($Route)) {
        $setRouteScript = Join-Path $PSScriptRoot 'set-application-route.ps1'
        if (Test-Path -LiteralPath $setRouteScript) {
            try {
                & $setRouteScript -WorkItemDir $workItemPath -Route $Route -Target $RouteTarget -Evidence $RouteEvidence | Out-Null
                $routeResult = $Route
            } catch {
                Write-Warning "Failed to set application route: $($_.Exception.Message)"
            }
        }
    }

    # Launch async enrichment if JobUrl is a public HTTP/HTTPS URL
    if (-not [string]::IsNullOrWhiteSpace($JobUrl)) {
        $isPublicHttp = $false
        try {
            $uri = [Uri]$JobUrl
            $isPublicHttp = ($uri.Scheme -eq 'http' -or $uri.Scheme -eq 'https') -and $uri.IsAbsoluteUri
        } catch {}

        if ($isPublicHttp) {
            $startEnrichScript = Join-Path $PSScriptRoot 'start-freehire-enrichment.ps1'
            if (Test-Path -LiteralPath $startEnrichScript) {
                try {
                    $enrichResult = & $startEnrichScript -WorkItemDir $workItemPath -Workspace $Workspace -ProfilePath $ProfilePath | Select-Object -Last 1 | ConvertFrom-Json
                    if ($enrichResult -and [string]$enrichResult.status -eq 'started') {
                        $enrichmentStatus = 'started'
                    } else {
                        $enrichmentStatus = 'launch-failed'
                        $enrichmentError = if ($enrichResult.error) { [string]$enrichResult.error } else { 'Unknown enrichment launch failure' }
                    }
                } catch {
                    $enrichmentStatus = 'launch-failed'
                    $enrichmentError = $_.Exception.Message
                }
            }
        }
    }

    Emit-Result 'created' -JobIdOut $JobId -Path $workItemPath -SourceReady $sourceReady -MetadataWritten $metadataWritten -EnrichmentStatus $enrichmentStatus -EnrichmentError $enrichmentError -RouteOut $routeResult -NextStage 'assessment_pending'
} else {
    Emit-Result $creationStatus -JobIdOut $JobId -Path $workItemPath -MatchedJobId $matchedJobId -Reason $creationReason
}
