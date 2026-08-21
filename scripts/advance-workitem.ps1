[CmdletBinding(DefaultParameterSetName='ByPath')]
param(
    [Parameter(Mandatory=$true,ParameterSetName='ByPath')][string]$WorkItemDir,
    [Parameter(Mandatory=$true,ParameterSetName='ById')][string]$JobId,
    [ValidateSet('ai','backend')][string]$Canonical = 'backend',
    [string]$Workspace = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'

function Emit([hashtable]$Value) {
    $Value | ConvertTo-Json -Depth 10 -Compress | Write-Output
}

function Read-JsonSafe([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json) } catch { return $null }
}

function Invoke-Defer([string]$Dir, [string]$Stage, [string]$Code, [string]$Message) {
    $deferScript = Join-Path $PSScriptRoot 'defer-workitem.ps1'
    return (& $deferScript -WorkItemDir $Dir -Stage $Stage -Code $Code -Message $Message | Select-Object -Last 1)
}


try {
    if ([string]::IsNullOrWhiteSpace($Workspace)) { $Workspace = (Get-Location).Path }
    $Workspace = (Resolve-Path -LiteralPath $Workspace).Path
    $queueRoot = Join-Path $Workspace '.job-apply-autopilot\queue'

    if ($PSCmdlet.ParameterSetName -eq 'ById') {
        $matches = @(Get-ChildItem -LiteralPath $queueRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$JobId-*" })
        if ($matches.Count -ne 1) {
            Emit @{ status='recoverable-error'; code='workitem-id-resolution-failed'; job_id=$JobId; next_stage='process_other_work' }
            exit 0
        }
        $WorkItemDir = $matches[0].FullName
    }
    $WorkItemDir = (Resolve-Path -LiteralPath $WorkItemDir).Path

    $repairScript = Join-Path $PSScriptRoot 'repair-workitem.ps1'
    $repairRaw = & $repairScript -WorkItemDir $WorkItemDir | Select-Object -Last 1
    $repair = $null
    try { $repair = $repairRaw | ConvertFrom-Json } catch {}
    if ($repair -and [string]$repair.status -eq 'repaired') {
        Emit @{ status='needs-assessment'; job_id=[string]$repair.job_id; reason=[string]$repair.reason; next_stage='assessment_pending' }
        exit 0
    }
    if ($repair -and [string]$repair.status -eq 'recoverable-error') {
        Invoke-Defer $WorkItemDir 'repair' ([string]$repair.code) ([string]$repair.message) | Out-Null
        Emit @{ status='recoverable-error'; code=[string]$repair.code; next_stage='process_other_work' }
        exit 0
    }

    $assessment = Read-JsonSafe (Join-Path $WorkItemDir 'assessment.json')
    if ($null -eq $assessment) {
        Emit @{ status='needs-assessment'; code='assessment-unreadable'; next_stage='assessment_pending' }
        exit 0
    }

    switch ([string]$assessment.status) {
        'pending' {
            Emit @{ status='needs-assessment'; job_id=[string]$assessment.job_id; next_stage='assessment_pending' }
            exit 0
        }
        'needs-research' {
            Emit @{ status='needs-research'; job_id=[string]$assessment.job_id; next_stage='eligibility_research_pending' }
            exit 0
        }
        'needs-evidence' {
            Emit @{ status='needs-evidence'; job_id=[string]$assessment.job_id; next_stage='candidate_evidence_pending' }
            exit 0
        }
        'failed' {
            Emit @{ status='terminal'; job_id=[string]$assessment.job_id; next_stage='process_other_work' }
            exit 0
        }
        'passed' { }
        default {
            Emit @{ status='needs-assessment'; job_id=[string]$assessment.job_id; code='unknown-assessment-state'; next_stage='assessment_pending' }
            exit 0
        }
    }

    $candidateEvidence = Join-Path $WorkItemDir 'candidate-evidence-research.json'
    if (Test-Path -LiteralPath $candidateEvidence) {
        try {
            & (Join-Path $PSScriptRoot 'merge-candidate-evidence.ps1') -EvidenceFile $candidateEvidence -Workspace $Workspace | Out-Null
        } catch {
            Invoke-Defer $WorkItemDir 'evidence-merge' 'evidence-merge-exception' $_.Exception.Message | Out-Null
            Emit @{ status='recoverable-error'; job_id=[string]$assessment.job_id; code='evidence-merge-exception'; next_stage='process_other_work' }
            exit 0
        }
    }

    $promote = Join-Path $PSScriptRoot 'promote-workitem.ps1'
    try {
        $generatedDir = & $promote -WorkItemDir $WorkItemDir -Canonical $Canonical -Workspace $Workspace | Select-Object -Last 1
        if ([string]::IsNullOrWhiteSpace([string]$generatedDir) -or -not (Test-Path -LiteralPath ([string]$generatedDir))) {
            throw "Promotion did not produce a valid generated directory: $generatedDir"
        }
        $recoverablePath = Join-Path $WorkItemDir 'recoverable-error.json'
        if (Test-Path -LiteralPath $recoverablePath) { Remove-Item -LiteralPath $recoverablePath -Force }
        $job = Read-JsonSafe (Join-Path $WorkItemDir 'job.json')
        $resolvedJobId = if ($job) { [string]$job.job_id } else { '' }
        Emit @{ status='promoted'; job_id=$resolvedJobId; generated_dir=[string]$generatedDir; next_stage='resume_pending' }
        exit 0
    } catch {
        Invoke-Defer $WorkItemDir 'promotion' 'promotion-exception' $_.Exception.Message | Out-Null
        $job = Read-JsonSafe (Join-Path $WorkItemDir 'job.json')
        $resolvedJobId = if ($job) { [string]$job.job_id } else { '' }
        Emit @{ status='recoverable-error'; job_id=$resolvedJobId; code='promotion-exception'; message=$_.Exception.Message; next_stage='process_other_work' }
        exit 0
    }
} catch {
    Emit @{ status='recoverable-error'; code='advance-workitem-exception'; message=$_.Exception.Message; next_stage='process_other_work' }
    exit 0
}
