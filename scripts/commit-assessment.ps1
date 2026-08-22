[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$WorkItemDir,
    [Parameter(Mandatory=$true)][string]$AssessmentJson,
    [string]$FitMapJson = '',
    [Parameter(Mandatory=$true)][ValidateSet('unassessed','needs-research','needs-evidence','malformed')][string]$ExpectedPriorStatus
)

$ErrorActionPreference = 'Stop'

function Emit([hashtable]$Value) {
    $Value | ConvertTo-Json -Depth 12 -Compress | Write-Output
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

function Get-RejectionStage([string]$PriorStatus) {
    $stage = switch ($PriorStatus) {
        'malformed' { 'assessment_repair' }
        'needs-research' { 'eligibility_research_pending' }
        'needs-evidence' { 'candidate_evidence_pending' }
        default { 'assessment_pending' }
    }
    return $stage
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
    $rejectionStage = Get-RejectionStage $ExpectedPriorStatus
    $jobPath = Join-Path $WorkItemDir 'job.json'
    if (-not (Test-Path -LiteralPath $jobPath)) {
        Emit @{ status='rejected-payload'; code='missing-job-json'; errors=@('missing-job-json'); next_stage=$rejectionStage }
        exit 0
    }
    $job = Get-Content -LiteralPath $jobPath -Raw | ConvertFrom-Json

    try { $draft = $AssessmentJson | ConvertFrom-Json } catch {
        Emit @{ status='rejected-payload'; code='assessment-json-invalid'; errors=@('assessment-json-invalid'); next_stage=$rejectionStage }
        exit 0
    }

    $validationErrors = [Collections.Generic.List[string]]::new()
    function Add-ValidationError([string]$Code) {
        if (-not $validationErrors.Contains($Code)) { $validationErrors.Add($Code) }
    }

    $allowedStatuses = @('passed','needs-research','needs-evidence','failed')
    $draftStatus = if (Has-Property $draft 'status') { [string]$draft.status } else { '' }
    $statusValid = $draftStatus -in $allowedStatuses
    if (-not $statusValid) { Add-ValidationError 'assessment-status-invalid' }

    $score = 0
    $scoreValid = $false
    if (-not (Has-Property $draft 'score')) {
        Add-ValidationError 'assessment-score-missing'
    } elseif ([int]::TryParse([string]$draft.score, [ref]$score) -and $score -ge 0 -and $score -le 100) {
        $scoreValid = $true
    } else {
        Add-ValidationError 'assessment-score-invalid'
    }

    foreach ($required in @('trust_class','role_family','eligibility_state','hard_gates','needs_external_research','needs_candidate_evidence')) {
        if (-not (Has-Property $draft $required)) { Add-ValidationError "assessment-$required-missing" }
    }
    foreach ($requiredText in @('trust_class','role_family','eligibility_state')) {
        if ((Has-Property $draft $requiredText) -and [string]::IsNullOrWhiteSpace([string]$draft.$requiredText)) {
            Add-ValidationError "assessment-$requiredText-empty"
        }
    }
    $gates = [ordered]@{}
    foreach ($gate in @('integrity','eligibility','role_family','mandatory_requirements','truth_feasibility')) {
        if (-not (Has-Property $draft 'hard_gates') -or -not (Has-Property $draft.hard_gates $gate) -or -not (Is-Bool $draft.hard_gates.$gate)) {
            Add-ValidationError "hard-gate-$gate-invalid"
        } else {
            $gates[$gate] = [bool]$draft.hard_gates.$gate
        }
    }

    $externalFlagValid = (Has-Property $draft 'needs_external_research') -and (Is-Bool $draft.needs_external_research)
    $evidenceFlagValid = (Has-Property $draft 'needs_candidate_evidence') -and (Is-Bool $draft.needs_candidate_evidence)
    if (-not $externalFlagValid -or -not $evidenceFlagValid) { Add-ValidationError 'research-flags-must-be-boolean' }

    if ($statusValid -and $draftStatus -eq 'passed') {
        if ($gates.Count -eq 5 -and @($gates.Values | Where-Object { -not $_ }).Count -gt 0) { Add-ValidationError 'passed-with-failed-hard-gate' }
        if ($externalFlagValid -and $evidenceFlagValid -and ([bool]$draft.needs_external_research -or [bool]$draft.needs_candidate_evidence)) {
            Add-ValidationError 'passed-cannot-need-research'
        }
    }
    if ($statusValid -and $externalFlagValid -and $evidenceFlagValid -and $draftStatus -eq 'needs-research' -and (-not [bool]$draft.needs_external_research -or [bool]$draft.needs_candidate_evidence)) {
        Add-ValidationError 'needs-research-flags-invalid'
    }
    if ($statusValid -and $externalFlagValid -and $evidenceFlagValid -and $draftStatus -eq 'needs-evidence' -and (-not [bool]$draft.needs_candidate_evidence -or [bool]$draft.needs_external_research)) {
        Add-ValidationError 'needs-evidence-flags-invalid'
    }

    $reasonCodes = if (Has-Property $draft 'reason_codes') { @($draft.reason_codes) } else { @() }
    if ($reasonCodes.Count -gt 2) { Add-ValidationError 'too-many-reason-codes' }
    if (@($reasonCodes | Where-Object { [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0) { Add-ValidationError 'reason-code-empty' }
    $candidateRequirements = if (Has-Property $draft 'candidate_evidence_requirements') { @($draft.candidate_evidence_requirements) } else { @() }
    if ($candidateRequirements.Count -gt 4) { Add-ValidationError 'too-many-candidate-evidence-requirements' }
    if ($statusValid -and $draftStatus -eq 'needs-evidence' -and $candidateRequirements.Count -eq 0) { Add-ValidationError 'needs-evidence-requirement-required' }
    if ($statusValid -and $externalFlagValid -and $evidenceFlagValid -and $draftStatus -eq 'failed' -and ([bool]$draft.needs_external_research -or [bool]$draft.needs_candidate_evidence)) { Add-ValidationError 'failed-cannot-need-research' }

    if ($statusValid -and $scoreValid -and $draftStatus -eq 'passed') {
        if ($score -lt 68) {
            Add-ValidationError 'passed-below-minimum-score'
        } elseif ($score -lt 72 -and $reasonCodes -notcontains 'strong-role-identity-and-eligibility') {
            Add-ValidationError 'passed-narrow-exception-reason-required'
        }
    }

    $fit = $null
    if ($statusValid -and $draftStatus -eq 'passed') {
        $fitDraft = $null
        if ([string]::IsNullOrWhiteSpace($FitMapJson)) {
            Add-ValidationError 'passed-fit-map-required'
        } else {
            try { $fitDraft = $FitMapJson | ConvertFrom-Json } catch { Add-ValidationError 'fit-map-json-invalid' }
        }
        $requirements = @()
        if ($null -ne $fitDraft) {
            if (-not (Has-Property $fitDraft 'requirements')) {
                Add-ValidationError 'fit-map-requirements-missing'
            } else {
                $requirements = @($fitDraft.requirements)
                if ($requirements.Count -eq 0) { Add-ValidationError 'fit-map-requirements-empty' }
                if ($requirements.Count -gt 8) { Add-ValidationError 'fit-map-too-many-requirements' }
                foreach ($requirement in $requirements) {
                    foreach ($name in @('requirement','evidence_class','evidence_scope','support','ats_keyword_allowed')) {
                        if (-not (Has-Property $requirement $name)) { Add-ValidationError "fit-map-$name-missing" }
                    }
                    if ((Has-Property $requirement 'ats_keyword_allowed') -and -not (Is-Bool $requirement.ats_keyword_allowed)) {
                        Add-ValidationError 'fit-map-ats-keyword-flag-invalid'
                    }
                }
            }
        }
        if ($null -ne $fitDraft -and $validationErrors.Count -eq 0) {
            $fit = [ordered]@{
                policy_version = '6.2'
                job_id = [string]$job.job_id
                status = 'complete'
                score = $score
                requirements = $requirements
            }
        }
    }

    if ($validationErrors.Count -gt 0) {
        Emit @{
            status = 'rejected-payload'
            code = [string]$validationErrors[0]
            errors = @($validationErrors)
            error_count = $validationErrors.Count
            next_stage = $rejectionStage
        }
        exit 0
    }

    $assessment = [ordered]@{
        policy_version = '6.2'
        job_id = [string]$job.job_id
        status = $draftStatus
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

    $nextStage = switch ($draftStatus) {
        'passed' { 'coordinator_adjudication_pending' }
        'needs-research' { 'eligibility_research_pending' }
        'needs-evidence' { 'candidate_evidence_pending' }
        'failed' { 'terminal' }
    }
    Clear-TransitionClaims $WorkItemDir $ExpectedPriorStatus
    Emit @{ status='committed'; job_id=[string]$job.job_id; assessment_status=$draftStatus; score=$score; expected_prior_status=$ExpectedPriorStatus; next_stage=$nextStage }
} catch {
    Emit @{ status='recoverable-error'; code='commit-assessment-exception'; message=$_.Exception.Message; next_stage='assessment_pending' }
    exit 0
}
