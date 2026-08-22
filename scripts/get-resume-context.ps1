[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Workspace,
    [Parameter(Mandatory=$true)][string]$JobId,
    [ValidateSet('generated')][string]$Kind = 'generated'
)

$ErrorActionPreference = 'Stop'

function Read-JsonSafe([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json) } catch { return $null }
}

function Read-FileSafe([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return Get-Content -LiteralPath $Path -Raw } catch { return $null }
}

function Has-Property($Object, [string]$Name) {
    return (
        $null -ne $Object -and
        $Object.PSObject.Properties.Name -contains $Name
    )
}

function Emit([hashtable]$Value) {
    $Value | ConvertTo-Json -Depth 12 -Compress | Write-Output
}

# Resolve workspace and runtime
$Workspace = (Resolve-Path -LiteralPath $Workspace).Path
$runtimeRoot = Join-Path $Workspace '.job-apply-autopilot'
if (-not (Test-Path -LiteralPath $runtimeRoot)) {
    Emit @{ status='error'; code='no-runtime'; message="No job-apply-autopilot runtime at $runtimeRoot" }
    exit 0
}

# Resolve work item by JobId using get-workitem-manifest
$manifestScript = Join-Path $PSScriptRoot 'get-workitem-manifest.ps1'
$manifestRaw = & $manifestScript -Workspace $Workspace -JobId $JobId -Kind generated | Select-Object -Last 1
try { $manifest = $manifestRaw | ConvertFrom-Json } catch {
    Emit @{ status='error'; code='manifest-parse-failed'; message='Failed to parse manifest output' }
    exit 0
}
if (-not $manifest -or -not $manifest.work_item) {
    Emit @{ status='error'; code='workitem-not-found'; message="No generated work item found for job '$JobId'" }
    exit 0
}
$workItemDir = $manifest.work_item

# Acquire resume_pending claim with 10-minute lease
$claimScript = Join-Path $PSScriptRoot 'claim-action.ps1'
$claim = (& $claimScript -Action Acquire -Scope WorkItem -Stage 'resume_pending' -WorkItemDir $workItemDir -Workspace $Workspace -LeaseMinutes 10 | Select-Object -Last 1) | ConvertFrom-Json

if (-not $claim -or [string]$claim.status -notin @('acquired','renewed')) {
    Emit @{ status='busy' }
    exit 0
}
$ownerId = $claim.owner_id

$retainClaim = $false
try {
    # Read assessment and validate
    $assessmentPath = Join-Path $workItemDir 'assessment.json'
    $assessment = Read-JsonSafe $assessmentPath
    if ($null -eq $assessment -or [string]$assessment.status -ne 'passed') {
        Emit @{ status='error'; code='assessment-not-passed'; message='Assessment is not passed'; work_item=$workItemDir; owner_id=$ownerId }
        exit 0
    }

    # Validate hard gates
    $gateNames = @('integrity','eligibility','role_family','mandatory_requirements','truth_feasibility')
    foreach ($gate in $gateNames) {
        if (-not (Has-Property $assessment.hard_gates $gate) -or -not [bool]$assessment.hard_gates.$gate) {
            Emit @{ status='error'; code='hard-gate-failed'; message="Hard gate not passed: $gate"; work_item=$workItemDir; owner_id=$ownerId }
            exit 0
        }
    }

    # Validate fit map complete
    $fitPath = Join-Path $workItemDir 'fit-map.json'
    $fit = Read-JsonSafe $fitPath
    if ($null -eq $fit -or [string]$fit.status -ne 'complete' -or -not (Has-Property $fit 'requirements') -or $fit.requirements.Count -eq 0) {
        Emit @{ status='error'; code='fit-map-incomplete'; message='Fit map is incomplete'; work_item=$workItemDir; owner_id=$ownerId }
        exit 0
    }

    # Read all required files
    $job = Read-JsonSafe (Join-Path $workItemDir 'job.json')
    $source = Read-FileSafe (Join-Path $workItemDir 'source.md')
    $fitMap = $fit
    $canonicalFacts = Read-FileSafe (Join-Path $PSScriptRoot '..\canonical\canonical-facts.yaml')
    $candidateEvidence = Read-JsonSafe (Join-Path $runtimeRoot 'candidate-evidence.json')
    $canonicalSourceTex = Read-FileSafe (Join-Path $workItemDir 'canonical-source.tex')
    $resumeTex = Read-FileSafe (Join-Path $workItemDir 'resume.tex')
    $tailoringAudit = Read-JsonSafe (Join-Path $workItemDir 'tailoring-audit.json')
    $resumeArtifact = Read-JsonSafe (Join-Path $workItemDir 'resume-artifact.json')

    # Check if valid ready resume artifact already exists
    $artifactReady = $false
    if ($resumeArtifact -and [string]$resumeArtifact.status -eq 'ready-for-upload' -and $resumeArtifact.path -and (Test-Path -LiteralPath ([string]$resumeArtifact.path))) {
        $pdfHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $resumeArtifact.path).Hash.ToLowerInvariant()
        if ($pdfHash -eq [string]$resumeArtifact.sha256) {
            $artifactReady = $true
        }
    }

    $retainClaim = $true

    Emit @{
        status = 'ready'
        work_item = $workItemDir
        owner_id = $ownerId
        job = $job
        assessment = $assessment
        fit_map = $fitMap
        source = $source
        canonical_facts = $canonicalFacts
        candidate_evidence = if ($candidateEvidence) { $candidateEvidence } else { @{} }
        canonical_source_tex = $canonicalSourceTex
        resume_tex = $resumeTex
        tailoring_audit = if ($tailoringAudit) { $tailoringAudit } else { @{} }
        resume_artifact = if ($artifactReady) { $resumeArtifact } else { $null }
    }
} finally {
    if (-not $retainClaim -and $ownerId) {
        & $claimScript `
            -Action Release `
            -Scope WorkItem `
            -Stage 'resume_pending' `
            -WorkItemDir $workItemDir `
            -Workspace $Workspace `
            -OwnerId $ownerId |
            Out-Null
    }
}