[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$WorkItemDir,
    [Parameter(Mandatory=$true)][string]$AssessmentJson,
    [string]$FitMapJson = '',
    [Parameter(Mandatory=$true)][ValidateSet('unassessed','needs-research','needs-evidence','malformed')][string]$ExpectedPriorStatus
)

$ErrorActionPreference = 'Stop'

function Emit([hashtable]$Value) {
    $Value | ConvertTo-Json -Depth 10 -Compress | Write-Output
}

function Has-Property($Object, [string]$Name) {
    return ($null -ne $Object -and $Object.PSObject.Properties.Name -contains $Name)
}

function Is-Bool($Value) {
    return ($Value -is [bool])
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

function Get-CurrentAssessmentStatus([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return 'unassessed' }
    try {
        $current = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
        if ([string]$current.status -in @('pending','captured-awaiting-source-and-assessment')) { return 'unassessed' }
        if ([string]$current.status -in @('passed','needs-research','needs-evidence','failed')) { return [string]$current.status }
        return 'malformed'
    } catch { return 'malformed' }
}

function Clear-TransitionClaims([string]$Dir, [string]$PriorStatus) {
    $claimScript = Join-Path $PSScriptRoot 'claim-action.ps1'
    if (-not (Test-Path -LiteralPath $claimScript)) { return }
    $runtimeRoot = Split-Path -Parent (Split-Path -Parent $Dir)
    $workspace = Split-Path -Parent $runtimeRoot
    $stages = switch ($PriorStatus) {
        'unassessed' { @('assessment_pending','reassessment_pending') }
        'malformed' { @('assessment_repair') }
        'needs-research' { @('eligibility_research_pending') }
        'needs-evidence' { @('candidate_evidence_pending') }
    }
    foreach ($stage in $stages) {
        & $claimScript -Action ClearStage -Scope WorkItem -Stage $stage -WorkItemDir $Dir -Workspace $workspace | Out-Null
    }
}

try {
    $WorkItemDir = (Resolve-Path -LiteralPath $WorkItemDir).Path
    $jobPath = Join-Path $WorkItemDir 'job.json'
    if (-not (Test-Path -LiteralPath $jobPath)) {
        Emit @{ status='rejected-payload'; code='missing-job-json'; next_stage='assessment_pending' }
        exit 0
    }
    $job = Get-Content -LiteralPath $jobPath -Raw | ConvertFrom-Json

    try { $draft = $AssessmentJson | ConvertFrom-Json } catch {
        Emit @{ status='rejected-payload'; code='assessment-json-invalid'; next_stage='assessment_pending' }
        exit 0
    }

    $allowedStatuses = @('passed','needs-research','needs-evidence','failed')
    if (-not (Has-Property $draft 'status') -or [string]$draft.status -notin $allowedStatuses) {
        Emit @{ status='rejected-payload'; code='assessment-status-invalid'; next_stage='assessment_pending' }
        exit 0
    }
    if (-not (Has-Property $draft 'score')) {
        Emit @{ status='rejected-payload'; code='assessment-score-missing'; next_stage='assessment_pending' }
        exit 0
    }
    $score = 0
    if (-not [int]::TryParse([string]$draft.score, [ref]$score) -or $score -lt 0 -or $score -gt 100) {
        Emit @{ status='rejected-payload'; code='assessment-score-invalid'; next_stage='assessment_pending' }
        exit 0
    }

    foreach ($required in @('trust_class','role_family','eligibility_state','hard_gates','needs_external_research','needs_candidate_evidence')) {
        if (-not (Has-Property $draft $required)) {
            Emit @{ status='rejected-payload'; code="assessment-$required-missing"; next_stage='assessment_pending' }
            exit 0
        }
    }

    foreach ($requiredText in @('trust_class','role_family','eligibility_state')) {
        if ([string]::IsNullOrWhiteSpace([string]$draft.$requiredText)) {
            Emit @{ status='rejected-payload'; code="assessment-$requiredText-empty"; next_stage='assessment_pending' }
            exit 0
        }
    }

    $gates = [ordered]@{}
    foreach ($gate in @('integrity','eligibility','role_family','mandatory_requirements','truth_feasibility')) {
        if (-not (Has-Property $draft.hard_gates $gate) -or -not (Is-Bool $draft.hard_gates.$gate)) {
            Emit @{ status='rejected-payload'; code="hard-gate-$gate-invalid"; next_stage='assessment_pending' }
            exit 0
        }
        $gates[$gate] = [bool]$draft.hard_gates.$gate
    }

    if ([string]$draft.status -eq 'passed' -and @($gates.Values | Where-Object { -not $_ }).Count -gt 0) {
        Emit @{ status='rejected-payload'; code='passed-with-failed-hard-gate'; next_stage='assessment_pending' }
        exit 0
    }
    if (-not (Is-Bool $draft.needs_external_research) -or -not (Is-Bool $draft.needs_candidate_evidence)) {
        Emit @{ status='rejected-payload'; code='research-flags-must-be-boolean'; next_stage='assessment_pending' }
        exit 0
    }

    if ([string]$draft.status -eq 'passed' -and ([bool]$draft.needs_external_research -or [bool]$draft.needs_candidate_evidence)) {
        Emit @{ status='rejected-payload'; code='passed-cannot-need-research'; next_stage='assessment_pending' }
        exit 0
    }
    if ([string]$draft.status -eq 'needs-research' -and (-not [bool]$draft.needs_external_research -or [bool]$draft.needs_candidate_evidence)) {
        Emit @{ status='rejected-payload'; code='needs-research-flags-invalid'; next_stage='assessment_pending' }
        exit 0
    }
    if ([string]$draft.status -eq 'needs-evidence' -and (-not [bool]$draft.needs_candidate_evidence -or [bool]$draft.needs_external_research)) {
        Emit @{ status='rejected-payload'; code='needs-evidence-flags-invalid'; next_stage='assessment_pending' }
        exit 0
    }

    $reasonCodes = @()
    if (Has-Property $draft 'reason_codes') { $reasonCodes = @($draft.reason_codes) }
    if ($reasonCodes.Count -gt 2) {
        Emit @{ status='rejected-payload'; code='too-many-reason-codes'; next_stage='assessment_pending' }
        exit 0
    }
    $candidateRequirements = @()
    if (Has-Property $draft 'candidate_evidence_requirements') { $candidateRequirements = @($draft.candidate_evidence_requirements) }
    if ($candidateRequirements.Count -gt 4) {
        Emit @{ status='rejected-payload'; code='too-many-candidate-evidence-requirements'; next_stage='assessment_pending' }
        exit 0
    }

    $assessment = [ordered]@{
        policy_version = '6.1'
        job_id = [string]$job.job_id
        status = [string]$draft.status
        score = $score
        trust_class = [string]$draft.trust_class
        role_family = [string]$draft.role_family
        eligibility_state = [string]$draft.eligibility_state
        hard_gates = $gates
        reason_codes = $reasonCodes
        candidate_evidence_requirements = $candidateRequirements
        needs_external_research = [bool]$draft.needs_external_research
        needs_candidate_evidence = [bool]$draft.needs_candidate_evidence
        committed_at = (Get-Date).ToUniversalTime().ToString('o')
    }

    $fit = $null
    if ([string]$draft.status -eq 'passed') {
        if ([string]::IsNullOrWhiteSpace($FitMapJson)) {
            Emit @{ status='rejected-payload'; code='passed-fit-map-required'; next_stage='assessment_pending' }
            exit 0
        }
        try { $fitDraft = $FitMapJson | ConvertFrom-Json } catch {
            Emit @{ status='rejected-payload'; code='fit-map-json-invalid'; next_stage='assessment_pending' }
            exit 0
        }
        if (-not (Has-Property $fitDraft 'requirements')) {
            Emit @{ status='rejected-payload'; code='fit-map-requirements-missing'; next_stage='assessment_pending' }
            exit 0
        }
        $requirements = @($fitDraft.requirements)
        if ($requirements.Count -gt 8) {
            Emit @{ status='rejected-payload'; code='fit-map-too-many-requirements'; next_stage='assessment_pending' }
            exit 0
        }
        foreach ($r in $requirements) {
            foreach ($name in @('requirement','evidence_class','evidence_scope','support','ats_keyword_allowed')) {
                if (-not (Has-Property $r $name)) {
                    Emit @{ status='rejected-payload'; code="fit-map-$name-missing"; next_stage='assessment_pending' }
                    exit 0
                }
            }
            if (-not (Is-Bool $r.ats_keyword_allowed)) {
                Emit @{ status='rejected-payload'; code='fit-map-ats-keyword-flag-invalid'; next_stage='assessment_pending' }
                exit 0
            }
        }
        $fit = [ordered]@{
            policy_version = '6.1'
            job_id = [string]$job.job_id
            status = 'complete'
            score = $score
            requirements = $requirements
        }
    }

    $assessmentPath = Join-Path $WorkItemDir 'assessment.json'
    $fitPath = Join-Path $WorkItemDir 'fit-map.json'
    $lockPath = Join-Path $WorkItemDir '.work-item.lock'
    $lock = $null
    try {
        try { $lock = [IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None') }
        catch {
            Emit @{ status='busy'; job_id=[string]$job.job_id; next_stage=$ExpectedPriorStatus }
            exit 0
        }

        $currentStatus = Get-CurrentAssessmentStatus $assessmentPath
        if ($currentStatus -ne $ExpectedPriorStatus) {
            Emit @{ status='already-committed'; job_id=[string]$job.job_id; expected_prior_status=$ExpectedPriorStatus; current_status=$currentStatus; next_stage='rerun_session_state' }
            exit 0
        }

        Write-JsonAtomic $assessmentPath $assessment 10
        if ($null -ne $fit) {
            Write-JsonAtomic $fitPath $fit 12
        } elseif (Test-Path -LiteralPath $fitPath) {
            Remove-Item -LiteralPath $fitPath -Force
        }

        $recoverablePath = Join-Path $WorkItemDir 'recoverable-error.json'
        if (Test-Path -LiteralPath $recoverablePath) { Remove-Item -LiteralPath $recoverablePath -Force }
    } finally {
        if ($null -ne $lock) { $lock.Dispose() }
    }

    $nextStage = switch ([string]$assessment.status) {
        'passed' { 'coordinator_adjudication_pending' }
        'needs-research' { 'eligibility_research_pending' }
        'needs-evidence' { 'candidate_evidence_pending' }
        'failed' { 'terminal' }
    }
    Clear-TransitionClaims $WorkItemDir $ExpectedPriorStatus
    Emit @{ status='committed'; job_id=[string]$job.job_id; assessment_status=[string]$assessment.status; score=$score; expected_prior_status=$ExpectedPriorStatus; next_stage=$nextStage }
} catch {
    Emit @{ status='recoverable-error'; code='commit-assessment-exception'; message=$_.Exception.Message; next_stage='assessment_pending' }
    exit 0
}
