[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$skillRoot = Split-Path -Parent $PSScriptRoot
$workspace = Join-Path ([IO.Path]::GetTempPath()) ("job-autopilot-resilience-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $workspace | Out-Null

try {
    & (Join-Path $PSScriptRoot 'init-workspace.ps1') -Workspace $workspace | Out-Null
    $workItem = & (Join-Path $PSScriptRoot 'new-workitem.ps1') -JobId 'selftest-001' -Company 'Self Test Co' -Title 'Backend Engineer' -Location 'Pakistan' -Source 'selftest' -Workspace $workspace | Select-Object -Last 1

    $snapshot = (& (Join-Path $PSScriptRoot 'session-state.ps1') -Workspace $workspace | Select-Object -Last 1) | ConvertFrom-Json
    $action = @($snapshot.actions | Where-Object { $_.job_id -eq 'selftest-001' }) | Select-Object -First 1
    if ($null -eq $action -or $action.stage -ne 'source_pending') {
        throw "Expected a placeholder work item to route to source_pending, got '$($action.stage)'."
    }
    "# Backend Engineer`n`nPakistan role. Build and operate backend APIs, services, databases, tests, and cloud deployments." | Set-Content -LiteralPath (Join-Path $workItem 'source.md') -Encoding UTF8

    # Reproduce the V5.11.4 failure: a plausible assessor result copied directly into assessment.json.
    @{
        result = 'apply'
        score = 88
        geo_eligible = $true
        held_gaps = @()
        hard_fails = @()
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $workItem 'assessment.json') -Encoding UTF8

    $snapshot = (& (Join-Path $PSScriptRoot 'session-state.ps1') -Workspace $workspace | Select-Object -Last 1) | ConvertFrom-Json
    $action = @($snapshot.actions | Where-Object { $_.job_id -eq 'selftest-001' }) | Select-Object -First 1
    if ($null -eq $action -or $action.stage -ne 'assessment_repair') {
        throw "Expected malformed assessment to route to assessment_repair, got '$($action.stage)'."
    }

    $repair = (& (Join-Path $PSScriptRoot 'repair-workitem.ps1') -WorkItemDir $workItem | Select-Object -Last 1) | ConvertFrom-Json
    if ($repair.status -ne 'repaired') { throw "Expected repair, got '$($repair.status)'." }

    $snapshot = (& (Join-Path $PSScriptRoot 'session-state.ps1') -Workspace $workspace | Select-Object -Last 1) | ConvertFrom-Json
    $action = @($snapshot.actions | Where-Object { $_.job_id -eq 'selftest-001' }) | Select-Object -First 1
    if ($null -eq $action -or $action.stage -ne 'assessment_pending') {
        throw "Expected repaired work item to route to assessment_pending, got '$($action.stage)'."
    }

    $assessmentJson = @'
{
  "status": "passed",
  "score": 88,
  "trust_class": "DIRECT_REASONABLE",
  "role_family": "backend-engineer",
  "eligibility_state": "PAKISTAN_ELIGIBLE",
  "hard_gates": {
    "integrity": true,
    "eligibility": true,
    "role_family": true,
    "mandatory_requirements": true,
    "truth_feasibility": true
  },
  "reason_codes": ["selftest"],
  "needs_external_research": false,
  "needs_candidate_evidence": false
}
'@
    $fitMapJson = @'
{
  "requirements": [
    {
      "requirement": "Backend engineering",
      "evidence_class": "EXACT",
      "evidence_scope": "professional",
      "support": ["H1"],
      "ats_keyword_allowed": true
    }
  ]
}
'@
    $commit = (& (Join-Path $PSScriptRoot 'commit-assessment.ps1') -WorkItemDir $workItem -AssessmentJson $assessmentJson -FitMapJson $fitMapJson | Select-Object -Last 1) | ConvertFrom-Json
    if ($commit.status -ne 'committed' -or $commit.next_stage -ne 'coordinator_adjudication_pending') {
        throw "Canonical assessment commit failed: $($commit | ConvertTo-Json -Compress)."
    }

    $snapshot = (& (Join-Path $PSScriptRoot 'session-state.ps1') -Workspace $workspace | Select-Object -Last 1) | ConvertFrom-Json
    $action = @($snapshot.actions | Where-Object { $_.job_id -eq 'selftest-001' }) | Select-Object -First 1
    if ($null -eq $action -or $action.stage -ne 'coordinator_adjudication_pending') {
        throw "Expected committed assessment to route to coordinator_adjudication_pending, got '$($action.stage)'."
    }

    # Test the deterministic wrapper and the -JobId compatibility path that previously caused a binder failure.
    $advance = (& (Join-Path $PSScriptRoot 'advance-workitem.ps1') -JobId 'selftest-001' -Canonical backend -Workspace $workspace | Select-Object -Last 1) | ConvertFrom-Json
    if ($advance.status -ne 'promoted' -or $advance.next_stage -ne 'resume_pending') {
        throw "Expected deterministic promotion, got: $($advance | ConvertTo-Json -Compress)."
    }

    # A new ID for a recently submitted company/title must be treated as a semantic duplicate.
    & (Join-Path $PSScriptRoot 'log-decision.ps1') -JobId 'dup-old' -Status 'submitted' -ReasonCode 'test-submitted' `
        -Company 'Acme Ltd.' -Title 'Backend Engineer' -Source 'external' -Workspace $workspace | Out-Null
    $candidateJson = @([ordered]@{ job_id='dup-new'; company='Acme'; title='Backend Engineer' }) | ConvertTo-Json -Compress
    $dedupe = (& (Join-Path $PSScriptRoot 'dedupe-jobs.ps1') -CandidatesJson $candidateJson -Workspace $workspace | Select-Object -Last 1) | ConvertFrom-Json
    $duplicate = @($dedupe | Where-Object { $_.job_id -eq 'dup-new' }) | Select-Object -First 1
    if (-not $duplicate.seen -or $duplicate.reason -ne 'semantic-submission' -or $duplicate.matched_job_id -ne 'dup-old') {
        throw "Semantic duplicate detection failed: $($duplicate | ConvertTo-Json -Compress)."
    }
    $duplicateCreate = & (Join-Path $PSScriptRoot 'new-workitem.ps1') -JobId 'dup-new' -Company 'Acme' -Title 'Backend Engineer' -Source 'test' -Workspace $workspace | Select-Object -Last 1
    if ([string]$duplicateCreate -notlike 'DUPLICATE:dup-new:semantic-submission:*') {
        throw "new-workitem semantic guard failed: $duplicateCreate"
    }

    # Governor must reconstruct Easy Apply history from reason_code even when source is only 'linkedin',
    # accept -JobId, and avoid recording the same job twice.
    & (Join-Path $PSScriptRoot 'log-decision.ps1') -JobId 'li-ledger' -Status 'submitted' -ReasonCode 'easy-apply-submitted' `
        -Company 'Linked Test' -Title 'Platform Engineer' -Source 'linkedin' -Workspace $workspace | Out-Null
    $governor = (& (Join-Path $PSScriptRoot 'linkedin-governor.ps1') -Action Status -Workspace $workspace | Select-Object -Last 1) | ConvertFrom-Json
    if ($governor.easy_apply_submissions_last_24h -ne 1) { throw "Governor did not recover the ledger Easy Apply event: $($governor | ConvertTo-Json -Compress)." }
    $governor = (& (Join-Path $PSScriptRoot 'linkedin-governor.ps1') -Action RecordEasyApply -JobId 'li-new' -Workspace $workspace | Select-Object -Last 1) | ConvertFrom-Json
    $governor = (& (Join-Path $PSScriptRoot 'linkedin-governor.ps1') -Action RecordEasyApply -JobId 'li-new' -Workspace $workspace | Select-Object -Last 1) | ConvertFrom-Json
    if ($governor.easy_apply_submissions_last_24h -ne 2) { throw 'Governor duplicate JobId protection failed.' }

    $snapshot = (& (Join-Path $PSScriptRoot 'session-state.ps1') -Workspace $workspace | Select-Object -Last 1) | ConvertFrom-Json
    if ($snapshot.summary.submitted_unique -ne 2 -or $snapshot.summary.submitted_rows -ne 2) {
        throw "Unique submission metrics failed: $($snapshot.summary | ConvertTo-Json -Compress)."
    }

    Write-Output 'PASS resilience: source gating, repair/commit/promotion, semantic dedupe, unique metrics, and atomic governor recovery passed.'
} finally {
    Remove-Item -LiteralPath $workspace -Recurse -Force -ErrorAction SilentlyContinue
}
