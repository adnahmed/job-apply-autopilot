[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$skillRoot = Split-Path -Parent $PSScriptRoot
$workspace = Join-Path ([IO.Path]::GetTempPath()) ("job-autopilot-resilience-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $workspace | Out-Null

function Add-SelfTestLedgerRow([hashtable]$Row) {
    $ledgerPath = Join-Path $workspace '.job-apply-autopilot\applications.jsonl'
    Add-Content -LiteralPath $ledgerPath -Value ($Row | ConvertTo-Json -Compress -Depth 6) -Encoding UTF8
}

try {
    & (Join-Path $PSScriptRoot 'init-workspace.ps1') -Workspace $workspace | Out-Null
    $workItem = & (Join-Path $PSScriptRoot 'new-workitem.ps1') -JobId 'selftest-001' -Company 'Self Test Co' -Title 'Backend Engineer' -Location 'Pakistan' -Source 'selftest' -Workspace $workspace | Select-Object -Last 1

    $existingCreation = (& (Join-Path $PSScriptRoot 'new-workitem.ps1') -JobId 'selftest-001' -Company 'Self Test Co' -Title 'Backend Engineer' -Location 'Pakistan' -Source 'selftest' -Workspace $workspace -Structured | Select-Object -Last 1) | ConvertFrom-Json
    if ($existingCreation.status -ne 'existing' -or [string]$existingCreation.path -ne [string]$workItem) { throw 'Structured exact-ID creation did not return existing/path.' }
    $manifest = (& (Join-Path $PSScriptRoot 'get-workitem-manifest.ps1') -WorkItemDir $workItem | Select-Object -Last 1) | ConvertFrom-Json
    if ([string]$manifest.paths.candidate_evidence.path -ne (Join-Path $workspace '.job-apply-autopilot\candidate-evidence.json')) { throw 'Manifest candidate-evidence path escaped the runtime root.' }
    $manifestById = (& (Join-Path $PSScriptRoot 'get-workitem-manifest.ps1') -Workspace $workspace -JobId 'selftest-001' -Kind queue | Select-Object -Last 1) | ConvertFrom-Json
    if ([string]$manifestById.work_item -ne [string]$workItem) { throw 'Identity-based manifest lookup did not resolve the exact work-item path.' }

    $snapshot = (& (Join-Path $PSScriptRoot 'session-state.ps1') -Workspace $workspace | Select-Object -Last 1) | ConvertFrom-Json
    $action = @($snapshot.actions | Where-Object { $_.job_id -eq 'selftest-001' }) | Select-Object -First 1
    if ($null -eq $action -or $action.stage -ne 'source_pending') {
        throw "Expected a placeholder work item to route to source_pending, got '$($action.stage)'."
    }
    "# Backend Engineer`n`nPakistan role. Build and operate backend APIs, services, databases, tests, and cloud deployments." | Set-Content -LiteralPath (Join-Path $workItem 'source.md') -Encoding UTF8
    [ordered]@{ provider = 'freehire'; quality = [ordered]@{ classification = 'reality-signal-present'; reality_signal = $true; evidence = 'class=likely-evergreen; repost_count=3' }; reality = [ordered]@{ class = 'likely-evergreen'; repost_count = 3 } } |
    ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $workItem 'source-metadata.json') -Encoding UTF8
    & (Join-Path $PSScriptRoot 'set-application-route.ps1') -WorkItemDir $workItem -Route external -Target 'https://jobs.example.com/selftest-001' -Evidence 'self-test explicit route' | Out-Null

    # Reproduce the V5.11.4 failure: a plausible assessor result copied directly into assessment.json.
    @{
        result       = 'apply'
        score        = 88
        geo_eligible = $true
        held_gaps    = @()
        hard_fails   = @()
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
  "score_components": {
    "core_technical": 27,
    "role_identity": 23,
    "seniority_tenure": 13,
    "production_ownership": 9,
    "domain_overlap": 6,
    "eligibility_certainty": 6,
    "experience_band": 2,
    "quality_recency_comp": 2
  },
  "trust_class": "DIRECT_REASONABLE",
  "role_family": "backend-engineer",
  "eligibility_state": "PAKISTAN_ELIGIBLE",
  "identity_check": {
    "advertised_employer": "Self Test Co",
    "body_employer": "Self Test Co",
    "consistent": true,
    "evidence": "Header and body identify Self Test Co."
  },
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
      "requirement_kind": "mandatory",
      "evidence_class": "EXACT",
      "evidence_scope": "professional",
      "support": ["H1"],
      "ats_keyword_allowed": true
    }
  ]
}
'@
    $allErrors = (& (Join-Path $PSScriptRoot 'commit-assessment.ps1') -WorkItemDir $workItem -ExpectedPriorStatus unassessed -AssessmentJson '{"status":"pass","score":"bad"}' | Select-Object -Last 1) | ConvertFrom-Json
    if ($allErrors.status -ne 'rejected-payload' -or [int]$allErrors.error_count -lt 5) { throw 'Assessment validator did not return the complete error set.' }
    $lowScoreAssessment = $assessmentJson -replace '"score": 88', '"score": 60'
    $lowScore = (& (Join-Path $PSScriptRoot 'commit-assessment.ps1') -WorkItemDir $workItem -ExpectedPriorStatus unassessed -AssessmentJson $lowScoreAssessment -FitMapJson $fitMapJson | Select-Object -Last 1) | ConvertFrom-Json
    if ($lowScore.status -ne 'rejected-payload' -or @($lowScore.errors) -notcontains 'passed-below-minimum-score') { throw 'Assessment commit accepted a below-policy passed score.' }

    $unknownNumeric = (& (Join-Path $PSScriptRoot 'resolve-application-answer.ps1') -WorkItemDir $workItem -QuestionJson '{"label":"Years using an unverified specialist tool","type":"number","required":true}' | Select-Object -Last 1) | ConvertFrom-Json
    if ($unknownNumeric.status -ne 'needs-semantic-answer') { throw 'Unknown required numeric answer was defaulted instead of handed off semantically.' }
    $phone = (& (Join-Path $PSScriptRoot 'resolve-application-answer.ps1') -WorkItemDir $workItem -QuestionJson '{"label":"Phone number","type":"text","required":true}' | Select-Object -Last 1) | ConvertFrom-Json
    if ($phone.status -ne 'answered' -or [string]$phone.value -ne '+923205700547') { throw 'Configured phone was not answered deterministically.' }
    $unknownLegal = (& (Join-Path $PSScriptRoot 'resolve-application-answer.ps1') -WorkItemDir $workItem -QuestionJson '{"label":"Passport number","type":"text","required":true}' | Select-Object -Last 1) | ConvertFrom-Json
    if ($unknownLegal.status -ne 'needs-semantic-answer' -or $unknownLegal.strategy -ne 'generate-one-context-aware-answer-and-continue') { throw 'Unknown required identity fact did not route to agent generation.' }
    $currentSalary = (& (Join-Path $PSScriptRoot 'resolve-application-answer.ps1') -WorkItemDir $workItem -QuestionJson '{"label":"Current monthly salary","type":"number","required":true}' | Select-Object -Last 1) | ConvertFrom-Json
    if ($currentSalary.status -ne 'answered' -or [double]$currentSalary.value -le 0) { throw 'Current salary did not reuse expected-compensation resolution.' }

    $commit = (& (Join-Path $PSScriptRoot 'commit-assessment.ps1') -WorkItemDir $workItem -ExpectedPriorStatus unassessed -AssessmentJson $assessmentJson -FitMapJson $fitMapJson | Select-Object -Last 1) | ConvertFrom-Json
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
    $snapshot = (& (Join-Path $PSScriptRoot 'session-state.ps1') -Workspace $workspace | Select-Object -Last 1) | ConvertFrom-Json
    if ($snapshot.summary.queue_actionable -ne 0) { throw 'Promoted queue copy remained actionable.' }

    # Throughput regression: generated work must not hide independent queue work, and the
    # state contract must publish a real assessor wave instead of only its first job.
    foreach ($parallelId in 1..5 | ForEach-Object { 'parallel-{0:D3}' -f $_ }) {
        $parallelItem = & (Join-Path $PSScriptRoot 'new-workitem.ps1') -JobId $parallelId -Company "Parallel Co $parallelId" `
            -Title 'Backend Engineer' -Location 'Pakistan' -Source 'selftest' -Workspace $workspace | Select-Object -Last 1
        "# Backend Engineer`n`nPakistan role. Build backend APIs, services, databases, tests, and cloud deployments for $parallelId." |
        Set-Content -LiteralPath (Join-Path $parallelItem 'source.md') -Encoding UTF8
    }
    $snapshot = (& (Join-Path $PSScriptRoot 'session-state.ps1') -Workspace $workspace | Select-Object -Last 1) | ConvertFrom-Json
    if ($snapshot.next_action -ne 'resume-generated') { throw "Expected compatible resume-generated priority, got '$($snapshot.next_action)'." }
    $resumeAction = @($snapshot.actions | Where-Object { $_.job_id -eq 'selftest-001' -and $_.stage -eq 'resume_pending' })
    $assessorActions = @($snapshot.actions | Where-Object { $_.dispatch -eq 'job-autopilot-assessor' })
    if ($resumeAction.Count -ne 1 -or $assessorActions.Count -ne 5) { throw 'Cross-stage runnable work was hidden or collapsed.' }
    if ($resumeAction[0].wave -ne 'fast' -or $snapshot.scheduler.active_wave -ne 'all' -or -not [bool]$resumeAction[0].reality_signal) { throw 'Unified-wave or reality-evidence state was not preserved.' }
    if ([string]$snapshot.scheduler.concurrency.default -ne 'unbounded' -or [int]$snapshot.scheduler.concurrency.linkedin_easy_apply -ne 1 -or $snapshot.scheduler.PSObject.Properties.Name -contains 'worker_limits' -or $snapshot.scheduler.PSObject.Properties.Name -contains 'dispatch_batches') {
        throw "Compact uncapped scheduler contract is invalid: $($snapshot.scheduler | ConvertTo-Json -Compress)."
    }
    if ($snapshot.scheduler.pipeline_buffer_target -ne 8 -or -not $snapshot.scheduler.continuous_discovery -or -not $snapshot.scheduler.discovery_needed -or $snapshot.scheduler.discovery_slots -ne 8) {
        throw "Pipeline buffer routing is invalid: $($snapshot.scheduler | ConvertTo-Json -Compress)."
    }
    $discoveryActions = @($snapshot.actions | Where-Object { $_.stage -eq 'discovery' })
    $freehireDiscovery = @($discoveryActions | Where-Object { $_.action_id -eq 'discovery:freehire' -and $_.dispatch -eq 'coordinator-discovery' })
    $linkedinDiscovery = @($discoveryActions | Where-Object { $_.action_id -eq 'discovery:linkedin-browser' -and $_.dispatch -eq 'coordinator-browser' })
    if ($discoveryActions.Count -ne 2 -or $freehireDiscovery.Count -ne 1 -or $linkedinDiscovery.Count -ne 1) {
        throw 'Independent FreeHire and LinkedIn/browser discovery actions were not both emitted alongside worker actions.'
    }
    if ([string]$freehireDiscovery[0].command -notmatch 'discover-freehire\.ps1' -or [int]$freehireDiscovery[0].target_new -ne 8) {
        throw 'FreeHire discovery action is missing its executable independent target.'
    }
    if ([string]$linkedinDiscovery[0].browser_instruction -notmatch 'independent per-source target' -or [string]$linkedinDiscovery[0].browser_instruction -notmatch 'never wait for, subtract, or skip' -or [int]$linkedinDiscovery[0].target_new -ne 8) {
        throw 'LinkedIn/browser discovery action can still be skipped after FreeHire fills its target.'
    }
    if ([string]$freehireDiscovery[0].discovery_group -ne [string]$linkedinDiscovery[0].discovery_group -or -not [bool]$freehireDiscovery[0].shared_claim_required -or -not [bool]$linkedinDiscovery[0].shared_claim_required) {
        throw 'Parallel discovery actions do not share the coordinator discovery claim contract.'
    }

    # A fresh terminal skip must not be mistaken for an old explicitly reopened reassessment.
    $freshSkip = & (Join-Path $PSScriptRoot 'new-workitem.ps1') -JobId 'fresh-skip' -Company 'Training Market' -Title 'LLM Evaluator' -Location 'Pakistan' -Source 'test' -Workspace $workspace | Select-Object -Last 1
    "# LLM Evaluator`n`nContractor task marketplace for model-training data evaluation in Pakistan." | Set-Content -LiteralPath (Join-Path $freshSkip 'source.md') -Encoding UTF8
    $freshAssessment = $assessmentJson -replace '"job_id"\s*:\s*"[^"]+"', '"job_id": "fresh-skip"'
    $freshCommit = (& (Join-Path $PSScriptRoot 'commit-assessment.ps1') -WorkItemDir $freshSkip -ExpectedPriorStatus unassessed -AssessmentJson $freshAssessment -FitMapJson $fitMapJson | Select-Object -Last 1) | ConvertFrom-Json
    if ($freshCommit.status -ne 'committed') { throw 'Fresh skip setup assessment failed.' }
    & (Join-Path $PSScriptRoot 'log-decision.ps1') -JobId 'fresh-skip' -Status 'skipped-role-family' -ReasonCode 'test-terminal-skip' `
        -Company 'Training Market' -Title 'LLM Evaluator' -Source 'test' -Workspace $workspace | Out-Null
    $snapshot = (& (Join-Path $PSScriptRoot 'session-state.ps1') -Workspace $workspace | Select-Object -Last 1) | ConvertFrom-Json
    if (@($snapshot.actions | Where-Object { $_.job_id -eq 'fresh-skip' }).Count -ne 0) { throw 'Fresh terminal skip was incorrectly reopened.' }

    # A new ID for a recently submitted company/title must be treated as a semantic duplicate.
    Add-SelfTestLedgerRow ([ordered]@{ timestamp = [DateTimeOffset]::UtcNow.ToString('o'); job_id = 'dup-old'; status = 'submitted'; reason_code = 'test-submitted'; company = 'Acme Ltd.'; title = 'Backend Engineer'; source = 'external' })
    $candidateJson = @([ordered]@{ job_id = 'dup-new'; company = 'Acme'; title = 'Backend Engineer' }) | ConvertTo-Json -Compress
    $dedupe = (& (Join-Path $PSScriptRoot 'dedupe-jobs.ps1') -CandidatesJson $candidateJson -Workspace $workspace | Select-Object -Last 1) | ConvertFrom-Json
    $duplicate = @($dedupe | Where-Object { $_.job_id -eq 'dup-new' }) | Select-Object -First 1
    if (-not $duplicate.seen -or $duplicate.reason -ne 'semantic-submission' -or $duplicate.matched_job_id -ne 'dup-old') {
        throw "Semantic duplicate detection failed: $($duplicate | ConvertTo-Json -Compress)."
    }
    $reorderedJson = @([ordered]@{ job_id = 'dup-reordered'; company = 'Acme'; title = 'Engineer Backend' }) | ConvertTo-Json -Compress
    $reordered = (& (Join-Path $PSScriptRoot 'dedupe-jobs.ps1') -CandidatesJson $reorderedJson -Workspace $workspace | Select-Object -Last 1) | ConvertFrom-Json
    if (-not $reordered.seen -or $reordered.reason -ne 'semantic-submission') { throw 'Title-token reordering bypassed semantic dedupe.' }
    $semanticPair = @(
        [ordered]@{job_id = 'summary-a'; company = 'TectSoft'; title = 'Senior React Native Full Stack Engineer'; location = 'Lahore, Pakistan'; posted_at = '2026-08-22T08:00:00Z'; description = 'Build production mobile apps using React Native and Node.js.' },
        [ordered]@{job_id = 'summary-b'; company = 'TectSoft Ltd'; title = 'Senior React Native Full-Stack Engineer Node.js'; location = 'Lahore, Pakistan'; posted_at = '2026-08-22T10:00:00Z'; description = 'TectSoft seeks an engineer for production-grade React Native mobile applications with Node.js and relational databases.' }
    ) | ConvertTo-Json -Compress
    $semanticBatch = @((& (Join-Path $PSScriptRoot 'dedupe-jobs.ps1') -CandidatesJson $semanticPair -Workspace $workspace | Select-Object -Last 1) | ConvertFrom-Json)
    if (-not [bool](@($semanticBatch | Where-Object job_id -eq 'summary-b')[0].seen)) { throw 'Summary/full semantic duplicate pair was not detected.' }
    $duplicateCreate = & (Join-Path $PSScriptRoot 'new-workitem.ps1') -JobId 'dup-new' -Company 'Acme' -Title 'Backend Engineer' -Source 'test' -Workspace $workspace | Select-Object -Last 1
    if ([string]$duplicateCreate -notlike 'DUPLICATE:dup-new:semantic-submission:*') {
        throw "new-workitem semantic guard failed: $duplicateCreate"
    }

    # Governor must reconstruct Easy Apply history from reason_code even when source is only 'linkedin',
    # accept -JobId, and avoid recording the same job twice.
    Add-SelfTestLedgerRow ([ordered]@{ timestamp = [DateTimeOffset]::UtcNow.ToString('o'); job_id = 'li-ledger'; status = 'submitted'; reason_code = 'easy-apply-submitted'; company = 'Linked Test'; title = 'Platform Engineer'; source = 'linkedin' })
    $governor = (& (Join-Path $PSScriptRoot 'linkedin-governor.ps1') -Action Status -Workspace $workspace | Select-Object -Last 1) | ConvertFrom-Json
    if ($governor.easy_apply_submissions_last_24h -ne 1) { throw "Governor did not recover the ledger Easy Apply event: $($governor | ConvertTo-Json -Compress)." }
    $governor = (& (Join-Path $PSScriptRoot 'linkedin-governor.ps1') -Action RecordEasyApply -JobId 'li-new' -Workspace $workspace | Select-Object -Last 1) | ConvertFrom-Json
    $governor = (& (Join-Path $PSScriptRoot 'linkedin-governor.ps1') -Action RecordEasyApply -JobId 'li-new' -Workspace $workspace | Select-Object -Last 1) | ConvertFrom-Json
    if ($governor.easy_apply_submissions_last_24h -ne 2) { throw 'Governor duplicate JobId protection failed.' }

    # An ambiguous outbound side effect must turn every later Reserve into verification-only.
    $sendDir = Join-Path $workspace '.job-apply-autopilot\generated\send-guard-test'
    New-Item -ItemType Directory -Force -Path $sendDir | Out-Null
    [ordered]@{ job_id = 'send-guard-test'; company = 'Guard Co'; title = 'Platform Engineer'; job_url = 'https://jobs.example.com/apply'; source = 'external' } |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $sendDir 'job.json') -Encoding UTF8
    [ordered]@{ filename = 'Guard_Co_Platform_Engineer.pdf'; sha256 = 'test' } |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $sendDir 'resume-artifact.json') -Encoding UTF8
    $reserve = (& (Join-Path $PSScriptRoot 'application-send-guard.ps1') -WorkItemDir $sendDir -Action Reserve `
            -Channel email -Target 'jobs@example.com' -Subject 'Application - Platform Engineer' | Select-Object -Last 1) | ConvertFrom-Json
    if ($reserve.status -ne 'acquired' -or -not $reserve.safe_to_submit) { throw "Send reservation failed: $($reserve | ConvertTo-Json -Compress)." }
    $secondReserve = (& (Join-Path $PSScriptRoot 'application-send-guard.ps1') -WorkItemDir $sendDir -Action Reserve `
            -Channel email -Target 'jobs@example.com' -Subject 'Application - Platform Engineer' | Select-Object -Last 1) | ConvertFrom-Json
    if ($secondReserve.status -ne 'verify-required' -or $secondReserve.safe_to_submit) { throw 'Ambiguous send did not block a duplicate reservation.' }
    $snapshot = (& (Join-Path $PSScriptRoot 'session-state.ps1') -Workspace $workspace | Select-Object -Last 1) | ConvertFrom-Json
    $sendAction = @($snapshot.actions | Where-Object { $_.job_id -eq 'send-guard-test' }) | Select-Object -First 1
    if ($null -eq $sendAction -or $sendAction.stage -ne 'application_verification') { throw 'Reserved send did not route to application_verification.' }
    if ($sendAction.dispatch -ne 'job-autopilot-email-apply') { throw 'Email verification was dispatched to the wrong applicator.' }
    $grace = (& (Join-Path $PSScriptRoot 'application-send-guard.ps1') -WorkItemDir $sendDir -Action MarkVerifiedAbsent `
            -ReservationId $reserve.reservation_id -ProofKind exact-sent-search-absence -Proof 'Sent search empty' | Select-Object -Last 1) | ConvertFrom-Json
    if ($grace.status -ne 'verification-grace' -or $grace.safe_to_submit) { throw 'Send verification grace failed.' }
    $submitted = (& (Join-Path $PSScriptRoot 'application-send-guard.ps1') -WorkItemDir $sendDir -Action MarkSubmitted `
            -ReservationId $reserve.reservation_id -Proof 'Message visible in Sent' | Select-Object -Last 1) | ConvertFrom-Json
    if ($submitted.status -ne 'submitted') { throw 'Send guard could not commit submission.' }
    $reconciled = (& (Join-Path $PSScriptRoot 'reconcile-application-result.ps1') -WorkItemDir $sendDir -Workspace $workspace | Select-Object -Last 1) | ConvertFrom-Json
    if ($reconciled.status -ne 'reconciled') { throw 'Application result did not reconcile.' }
    $reconciledAgain = (& (Join-Path $PSScriptRoot 'reconcile-application-result.ps1') -WorkItemDir $sendDir -Workspace $workspace | Select-Object -Last 1) | ConvertFrom-Json
    if ($reconciledAgain.status -ne 'already-reconciled') { throw 'Application reconciliation was not idempotent.' }
    if (@(Get-Content -LiteralPath (Join-Path $workspace '.job-apply-autopilot\applications.jsonl') | Where-Object { $_ -match '"job_id":"send-guard-test"' }).Count -ne 1) { throw 'Application reconciliation wrote a duplicate ledger row.' }
    $repostDir = Join-Path $workspace '.job-apply-autopilot\generated\send-guard-repost'
    New-Item -ItemType Directory -Force -Path $repostDir | Out-Null
    [ordered]@{ job_id = 'send-guard-repost'; company = 'Guard Co Ltd.'; title = 'Platform Engineer'; job_url = 'https://jobs.example.com/repost'; source = 'external' } |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $repostDir 'job.json') -Encoding UTF8
    [ordered]@{ filename = 'Guard_Co_Platform_Engineer.pdf'; sha256 = 'test' } |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $repostDir 'resume-artifact.json') -Encoding UTF8
    $repostReserve = (& (Join-Path $PSScriptRoot 'application-send-guard.ps1') -WorkItemDir $repostDir -Action Reserve `
            -Channel external-ats -Target 'https://jobs.example.com/repost' | Select-Object -Last 1) | ConvertFrom-Json
    if ($repostReserve.status -ne 'semantic-already-submitted' -or $repostReserve.safe_to_submit) { throw "Semantic repost reached the send boundary: $($repostReserve | ConvertTo-Json -Compress)." }

    $raceA = Join-Path $workspace '.job-apply-autopilot\generated\race-a'
    $raceB = Join-Path $workspace '.job-apply-autopilot\generated\race-b'
    foreach ($pair in @(@($raceA, 'race-a'), @($raceB, 'race-b'))) {
        New-Item -ItemType Directory -Force -Path $pair[0] | Out-Null
        [ordered]@{ job_id = $pair[1]; company = 'Race Co'; title = 'Backend Engineer'; job_url = "https://race.example/$($pair[1])"; source = 'external' } |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $pair[0] 'job.json') -Encoding UTF8
        [ordered]@{ filename = 'Race_Co_Backend_Engineer.pdf'; sha256 = 'test' } |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $pair[0] 'resume-artifact.json') -Encoding UTF8
    }
    $raceReservation = (& (Join-Path $PSScriptRoot 'application-send-guard.ps1') -WorkItemDir $raceA -Action Reserve -Channel external-ats -Target 'race.example' | Select-Object -Last 1) | ConvertFrom-Json
    $raceConflict = (& (Join-Path $PSScriptRoot 'application-send-guard.ps1') -WorkItemDir $raceB -Action Reserve -Channel external-ats -Target 'race.example' | Select-Object -Last 1) | ConvertFrom-Json
    if ($raceReservation.status -ne 'acquired' -or $raceConflict.status -ne 'semantic-reservation-exists') { throw 'Concurrent semantic reservation guard failed.' }
    & (Join-Path $PSScriptRoot 'application-send-guard.ps1') -WorkItemDir $raceA -Action CancelBeforeSubmit `
        -ReservationId $raceReservation.reservation_id -Proof 'Self-test cancellation before browser work' | Out-Null
    $afterSubmit = (& (Join-Path $PSScriptRoot 'application-send-guard.ps1') -WorkItemDir $sendDir -Action Reserve `
            -Channel email -Target 'jobs@example.com' -Subject 'Application - Platform Engineer' | Select-Object -Last 1) | ConvertFrom-Json
    if ($afterSubmit.status -ne 'already-submitted' -or $afterSubmit.safe_to_submit) { throw 'Submitted send was not idempotent.' }

    # Confirmed overrides hard-reject at the send boundary, while FreeHire reality evidence alone does not.
    $qualityRejectDir = Join-Path $workspace '.job-apply-autopilot\generated\quality-reject'
    New-Item -ItemType Directory -Force -Path $qualityRejectDir | Out-Null
    [ordered]@{ job_id = 'quality-reject'; company = 'Crossing Hurdles'; title = 'Backend Engineer'; job_url = 'https://example.com/apply'; source = 'external' } |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $qualityRejectDir 'job.json') -Encoding UTF8
    $qualityReject = (& (Join-Path $PSScriptRoot 'application-send-guard.ps1') -WorkItemDir $qualityRejectDir -Action Reserve -Channel external-ats -Target 'https://example.com/apply' | Select-Object -Last 1) | ConvertFrom-Json
    $qualityResult = Get-Content -LiteralPath (Join-Path $qualityRejectDir 'application-result.json') -Raw | ConvertFrom-Json
    if ($qualityReject.status -ne 'quality-rejected' -or $qualityResult.status -ne 'skipped-job-quality') { throw 'Confirmed employer override did not stop at the send boundary.' }

    $qualitySignalDir = Join-Path $workspace '.job-apply-autopilot\generated\quality-signal'
    New-Item -ItemType Directory -Force -Path $qualitySignalDir | Out-Null
    [ordered]@{ job_id = 'quality-signal'; company = 'Signal Co'; title = 'Platform Engineer'; job_url = 'https://jobs.example.net/apply'; source = 'freehire' } |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $qualitySignalDir 'job.json') -Encoding UTF8
    [ordered]@{ provider = 'freehire'; reality = [ordered]@{ class = 'likely-evergreen'; repost_count = 5; mass_posting_count = 4; fake_freshness = $true } } |
    ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $qualitySignalDir 'source-metadata.json') -Encoding UTF8
    $qualitySignal = (& (Join-Path $PSScriptRoot 'application-send-guard.ps1') -WorkItemDir $qualitySignalDir -Action Reserve -Channel external-ats -Target 'https://jobs.example.net/apply' | Select-Object -Last 1) | ConvertFrom-Json
    if ($qualitySignal.status -ne 'acquired') { throw 'Reality evidence was incorrectly treated as an automatic rejection.' }
    & (Join-Path $PSScriptRoot 'application-send-guard.ps1') -WorkItemDir $qualitySignalDir -Action CancelBeforeSubmit -ReservationId $qualitySignal.reservation_id -Proof 'Self-test evidence-only cancellation' | Out-Null

    $identityQuality = (& (Join-Path $PSScriptRoot 'check-job-quality.ps1') -JobJson '{"job_id":"identity-mismatch","company":"SENSYS Inc.","title":"Principal Full Stack Engineer","description":"INTECH Automation Intelligence is seeking a Principal Software Engineer for its industrial platform."}' | Select-Object -Last 1) | ConvertFrom-Json
    if ($identityQuality.allowed -or $identityQuality.reason_code -ne 'employer-body-mismatch') { throw 'Employer/body identity mismatch was not rejected.' }
    $unnamedQuality = (& (Join-Path $PSScriptRoot 'check-job-quality.ps1') -JobJson '{"job_id":"unnamed","company":"Hire Feed","title":"Python Developer","description":"We are hiring for one of our clients, seeking a Python developer."}' | Select-Object -Last 1) | ConvertFrom-Json
    if ($unnamedQuality.allowed -or $unnamedQuality.reason_code -ne 'unnamed-client') { throw 'Unnamed-client agency was not rejected.' }

    $aggregatorDir = Join-Path $workspace '.job-apply-autopilot\generated\aggregator-route'
    New-Item -ItemType Directory -Force -Path $aggregatorDir | Out-Null
    [ordered]@{ job_id = 'aggregator-route'; company = 'Route Co'; title = 'Backend Engineer'; job_url = 'https://en-pk.whatjobs.com/job/1'; source = 'freehire' } |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $aggregatorDir 'job.json') -Encoding UTF8
    $aggregatorReserve = (& (Join-Path $PSScriptRoot 'application-send-guard.ps1') -WorkItemDir $aggregatorDir -Action Reserve -Channel external-ats -Target 'https://en-pk.whatjobs.com/job/1' | Select-Object -Last 1) | ConvertFrom-Json
    if ($aggregatorReserve.status -ne 'route-unresolved' -or $aggregatorReserve.safe_to_submit) { throw 'Legacy aggregator route reached reservation.' }

    # Repair concatenated legacy JSONL and enforce an active domain marker in session routing.
    $now = [DateTimeOffset]::UtcNow
    $legacyA = [ordered]@{ timestamp = $now.AddHours(-48).ToString('o'); domain = 'expired.example'; status = 'blocked-security'; reason = 'old' } | ConvertTo-Json -Compress
    $legacyB = [ordered]@{ timestamp = $now.ToString('o'); domain = 'indeed.com'; status = 'blocked-security'; reason = 'captcha'; expires_at = $now.AddHours(1).ToString('o') } | ConvertTo-Json -Compress
    [IO.File]::WriteAllText((Join-Path $workspace '.job-apply-autopilot\domain-circuit-breakers.jsonl'), "$legacyA$legacyB", [Text.UTF8Encoding]::new($false))
    $migration = (& (Join-Path $PSScriptRoot 'domain-circuit-breaker.ps1') -Action MigrateLegacy -Workspace $workspace | Select-Object -Last 1) | ConvertFrom-Json
    if ($migration.events -ne 2) { throw 'Legacy circuit-breaker repair did not recover both objects.' }
    foreach ($line in Get-Content -LiteralPath (Join-Path $workspace '.job-apply-autopilot\domain-circuit-breakers.jsonl')) { $line | ConvertFrom-Json | Out-Null }
    $circuitDir = Join-Path $workspace '.job-apply-autopilot\generated\circuit-test'
    New-Item -ItemType Directory -Force -Path $circuitDir | Out-Null
    [ordered]@{ job_id = 'circuit-test'; company = 'Circuit Co'; title = 'Backend Engineer'; job_url = 'https://pk.indeed.com/viewjob?jk=test'; source = 'indeed' } |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $circuitDir 'job.json') -Encoding UTF8
    [ordered]@{ filename = 'Circuit_Co_Backend_Engineer.pdf'; sha256 = 'test' } |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $circuitDir 'resume-artifact.json') -Encoding UTF8
    $snapshot = (& (Join-Path $PSScriptRoot 'session-state.ps1') -Workspace $workspace | Select-Object -Last 1) | ConvertFrom-Json
    $circuitAction = @($snapshot.actions | Where-Object { $_.job_id -eq 'circuit-test' }) | Select-Object -First 1
    if ($null -ne $circuitAction) { throw 'Circuit-blocked job leaked into actionable state.' }
    if ($snapshot.summary.generated_circuit_blocked -ne 1 -or $snapshot.summary.circuit_breakers_active -ne 1) { throw "Circuit-breaker summary/routing failed: $($snapshot.summary | ConvertTo-Json -Compress)." }

    $snapshot = (& (Join-Path $PSScriptRoot 'session-state.ps1') -Workspace $workspace | Select-Object -Last 1) | ConvertFrom-Json
    if ($snapshot.summary.submitted_unique -ne 3 -or $snapshot.summary.submitted_rows -ne 3) {
        throw "Unique submission metrics failed: $($snapshot.summary | ConvertTo-Json -Compress)."
    }

    # The FreeHire transport must reject paid and unknown surfaces before any network call.
    $paidBlocked = (& (Join-Path $PSScriptRoot 'freehire-client.ps1') -Method POST -Path 'jobs/example/match-analysis' -CostClass credit -Auth required -Workspace $workspace | Select-Object -Last 1) | ConvertFrom-Json
    if ($paidBlocked.status -ne 'policy-blocked' -or $paidBlocked.error_code -ne 'ai-credit-spend-disabled') { throw 'FreeHire AI-credit guard did not block before transport.' }
    $unknownBlocked = (& (Join-Path $PSScriptRoot 'freehire-client.ps1') -Method POST -Path 'assistant/sessions' -CostClass free -Auth none -Workspace $workspace | Select-Object -Last 1) | ConvertFrom-Json
    if ($unknownBlocked.status -ne 'policy-blocked' -or $unknownBlocked.error_code -ne 'endpoint-not-zero-credit-allowlisted') { throw 'FreeHire endpoint allowlist accepted an unknown surface.' }

    $clientSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'freehire-client.ps1') -Raw
    if ($clientSource -match '(?i)Authorization\s*=.*Write-(Output|Host)|Emit\s+.*token') { throw 'FreeHire client appears to expose credential material.' }

    $rawExport = Join-Path $workspace 'session-raw.json'
    $safeExport = Join-Path $workspace 'session-sanitized.json'
    [ordered]@{ email = 'person@example.com'; phone = '+923205700547'; authorization = 'Bearer secret.value'; url = 'https://example.com/confirm?token=abc123&x=1' } |
    ConvertTo-Json | Set-Content -LiteralPath $rawExport -Encoding UTF8
    & (Join-Path $PSScriptRoot 'sanitize-session-export.ps1') -InputPath $rawExport -OutputPath $safeExport | Out-Null
    $safeText = Get-Content -LiteralPath $safeExport -Raw
    $safeText | ConvertFrom-Json | Out-Null
    if ($safeText -match 'person@example\.com|923205700547|secret\.value|token=abc123') { throw 'Session export sanitizer leaked sensitive values.' }
    if ((Get-Content -LiteralPath $rawExport -Raw) -notmatch 'person@example\.com') { throw 'Session export sanitizer modified the raw input.' }

    Write-Output 'PASS resilience: continuous discovery, completion-first answers, source identity gating, semantic dedupe, deterministic transitions, idempotent sends, route safety, redaction, and zero-credit FreeHire policy passed.'
}
finally {
    Remove-Item -LiteralPath $workspace -Recurse -Force -ErrorAction SilentlyContinue
}
