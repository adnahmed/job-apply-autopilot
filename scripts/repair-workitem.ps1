[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$WorkItemDir
)

$ErrorActionPreference = 'Stop'

function Emit([hashtable]$Value) {
    $Value | ConvertTo-Json -Depth 8 -Compress | Write-Output
}

function Read-JsonSafe([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json) } catch { return $null }
}

function Has-Property($Object, [string]$Name) {
    return ($null -ne $Object -and $Object.PSObject.Properties.Name -contains $Name)
}

function New-PendingAssessment([string]$JobId) {
    return [ordered]@{
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
}

try {
    $WorkItemDir = (Resolve-Path -LiteralPath $WorkItemDir).Path
    $job = Read-JsonSafe (Join-Path $WorkItemDir 'job.json')
    if ($null -eq $job -or -not $job.job_id) {
        Emit @{ status='recoverable-error'; code='missing-or-invalid-job-json'; next_stage='assessment_pending' }
        exit 0
    }

    $assessmentPath = Join-Path $WorkItemDir 'assessment.json'
    $fitPath = Join-Path $WorkItemDir 'fit-map.json'
    $assessment = Read-JsonSafe $assessmentPath
    $fit = Read-JsonSafe $fitPath
    $malformed = $false
    $reason = ''

    if ($null -eq $assessment) {
        $malformed = $true; $reason = 'missing-or-invalid-assessment-json'
    } elseif (-not (Has-Property $assessment 'status')) {
        $malformed = $true; $reason = 'assessment-status-missing'
    } elseif ([string]$assessment.status -notin @('pending','passed','needs-research','needs-evidence','failed')) {
        $malformed = $true; $reason = 'assessment-status-unknown'
    } elseif ([string]$assessment.status -ne 'pending') {
        foreach ($required in @('score','trust_class','role_family','eligibility_state','hard_gates','needs_external_research','needs_candidate_evidence')) {
            if (-not (Has-Property $assessment $required)) {
                $malformed = $true; $reason = "assessment-$required-missing"; break
            }
        }
        if (-not $malformed) {
            foreach ($gate in @('integrity','eligibility','role_family','mandatory_requirements','truth_feasibility')) {
                if (-not (Has-Property $assessment.hard_gates $gate) -or $assessment.hard_gates.$gate -isnot [bool]) {
                    $malformed = $true; $reason = "hard-gate-$gate-invalid"; break
                }
            }
        }
        if (-not $malformed -and ($assessment.needs_external_research -isnot [bool] -or $assessment.needs_candidate_evidence -isnot [bool])) {
            $malformed = $true; $reason = 'research-flags-invalid'
        }
        if (-not $malformed -and [string]$assessment.status -eq 'passed') {
            foreach ($gate in @('integrity','eligibility','role_family','mandatory_requirements','truth_feasibility')) {
                if (-not [bool]$assessment.hard_gates.$gate) {
                    $malformed = $true; $reason = "passed-hard-gate-invalid-$gate"; break
                }
            }
            if (-not $malformed) {
                if ($null -eq $fit -or -not (Has-Property $fit 'status') -or [string]$fit.status -notin @('complete','passed') -or -not (Has-Property $fit 'score')) {
                    $malformed = $true; $reason = 'passed-fit-map-incomplete'
                }
            }
        }
    }


    if (-not $malformed) {
        Emit @{ status='valid'; job_id=[string]$job.job_id; assessment_status=[string]$assessment.status; next_stage='unchanged' }
        exit 0
    }

    $stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ')
    if (Test-Path -LiteralPath $assessmentPath) {
        Copy-Item -LiteralPath $assessmentPath -Destination (Join-Path $WorkItemDir "assessment.invalid.$stamp.json") -Force
    }
    if (Test-Path -LiteralPath $fitPath) {
        Copy-Item -LiteralPath $fitPath -Destination (Join-Path $WorkItemDir "fit-map.invalid.$stamp.json") -Force
        Remove-Item -LiteralPath $fitPath -Force
    }
    $temp = "$assessmentPath.$PID.$([Guid]::NewGuid().ToString('N')).tmp"
    New-PendingAssessment ([string]$job.job_id) | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temp -Encoding UTF8
    [IO.File]::Move($temp, $assessmentPath, $true)
    $runtimeRoot = Split-Path -Parent (Split-Path -Parent $WorkItemDir)
    $workspace = Split-Path -Parent $runtimeRoot
    & (Join-Path $PSScriptRoot 'claim-action.ps1') -Action ClearStage -Scope WorkItem -Stage 'assessment_repair' -WorkItemDir $WorkItemDir -Workspace $workspace | Out-Null

    Emit @{ status='repaired'; job_id=[string]$job.job_id; reason=$reason; next_stage='assessment_pending' }
} catch {
    Emit @{ status='recoverable-error'; code='repair-workitem-exception'; message=$_.Exception.Message; next_stage='assessment_pending' }
    exit 0
}
