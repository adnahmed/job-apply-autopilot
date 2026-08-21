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
    if ([string]$snapshot.scheduler.concurrency.default -ne 'unbounded' -or [int]$snapshot.scheduler.concurrency.linkedin_easy_apply -ne 1 -or $snapshot.scheduler.PSObject.Properties.Name -contains 'worker_limits' -or $snapshot.scheduler.PSObject.Properties.Name -contains 'dispatch_batches') {
        throw "Compact uncapped scheduler contract is invalid: $($snapshot.scheduler | ConvertTo-Json -Compress)."
    }
    if ($snapshot.scheduler.pipeline_buffer_target -ne 8 -or -not $snapshot.scheduler.discovery_needed -or $snapshot.scheduler.discovery_slots -ne 2) {
        throw "Pipeline buffer routing is invalid: $($snapshot.scheduler | ConvertTo-Json -Compress)."
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
    Add-SelfTestLedgerRow ([ordered]@{ timestamp=[DateTimeOffset]::UtcNow.ToString('o'); job_id='dup-old'; status='submitted'; reason_code='test-submitted'; company='Acme Ltd.'; title='Backend Engineer'; source='external' })
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
    Add-SelfTestLedgerRow ([ordered]@{ timestamp=[DateTimeOffset]::UtcNow.ToString('o'); job_id='li-ledger'; status='submitted'; reason_code='easy-apply-submitted'; company='Linked Test'; title='Platform Engineer'; source='linkedin' })
    $governor = (& (Join-Path $PSScriptRoot 'linkedin-governor.ps1') -Action Status -Workspace $workspace | Select-Object -Last 1) | ConvertFrom-Json
    if ($governor.easy_apply_submissions_last_24h -ne 1) { throw "Governor did not recover the ledger Easy Apply event: $($governor | ConvertTo-Json -Compress)." }
    $governor = (& (Join-Path $PSScriptRoot 'linkedin-governor.ps1') -Action RecordEasyApply -JobId 'li-new' -Workspace $workspace | Select-Object -Last 1) | ConvertFrom-Json
    $governor = (& (Join-Path $PSScriptRoot 'linkedin-governor.ps1') -Action RecordEasyApply -JobId 'li-new' -Workspace $workspace | Select-Object -Last 1) | ConvertFrom-Json
    if ($governor.easy_apply_submissions_last_24h -ne 2) { throw 'Governor duplicate JobId protection failed.' }

    # An ambiguous outbound side effect must turn every later Reserve into verification-only.
    $sendDir = Join-Path $workspace '.job-apply-autopilot\generated\send-guard-test'
    New-Item -ItemType Directory -Force -Path $sendDir | Out-Null
    [ordered]@{ job_id='send-guard-test'; company='Guard Co'; title='Platform Engineer'; job_url='https://jobs.example.com/apply'; source='external' } |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $sendDir 'job.json') -Encoding UTF8
    [ordered]@{ filename='Guard_Co_Platform_Engineer.pdf'; sha256='test' } |
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
    [ordered]@{ job_id='send-guard-repost'; company='Guard Co Ltd.'; title='Platform Engineer'; job_url='https://jobs.example.com/repost'; source='external' } |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $repostDir 'job.json') -Encoding UTF8
    [ordered]@{ filename='Guard_Co_Platform_Engineer.pdf'; sha256='test' } |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $repostDir 'resume-artifact.json') -Encoding UTF8
    $repostReserve = (& (Join-Path $PSScriptRoot 'application-send-guard.ps1') -WorkItemDir $repostDir -Action Reserve `
        -Channel external-ats -Target 'https://jobs.example.com/repost' | Select-Object -Last 1) | ConvertFrom-Json
    if ($repostReserve.status -ne 'semantic-already-submitted' -or $repostReserve.safe_to_submit) { throw "Semantic repost reached the send boundary: $($repostReserve | ConvertTo-Json -Compress)." }

    $raceA = Join-Path $workspace '.job-apply-autopilot\generated\race-a'
    $raceB = Join-Path $workspace '.job-apply-autopilot\generated\race-b'
    foreach ($pair in @(@($raceA,'race-a'),@($raceB,'race-b'))) {
        New-Item -ItemType Directory -Force -Path $pair[0] | Out-Null
        [ordered]@{ job_id=$pair[1]; company='Race Co'; title='Backend Engineer'; job_url="https://race.example/$($pair[1])"; source='external' } |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path $pair[0] 'job.json') -Encoding UTF8
        [ordered]@{ filename='Race_Co_Backend_Engineer.pdf'; sha256='test' } |
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

    # Repair concatenated legacy JSONL and enforce an active domain marker in session routing.
    $now = [DateTimeOffset]::UtcNow
    $legacyA = [ordered]@{ timestamp=$now.AddHours(-48).ToString('o'); domain='expired.example'; status='blocked-security'; reason='old' } | ConvertTo-Json -Compress
    $legacyB = [ordered]@{ timestamp=$now.ToString('o'); domain='indeed.com'; status='blocked-security'; reason='captcha'; expires_at=$now.AddHours(1).ToString('o') } | ConvertTo-Json -Compress
    [IO.File]::WriteAllText((Join-Path $workspace '.job-apply-autopilot\domain-circuit-breakers.jsonl'), "$legacyA$legacyB", [Text.UTF8Encoding]::new($false))
    $migration = (& (Join-Path $PSScriptRoot 'domain-circuit-breaker.ps1') -Action MigrateLegacy -Workspace $workspace | Select-Object -Last 1) | ConvertFrom-Json
    if ($migration.events -ne 2) { throw 'Legacy circuit-breaker repair did not recover both objects.' }
    foreach ($line in Get-Content -LiteralPath (Join-Path $workspace '.job-apply-autopilot\domain-circuit-breakers.jsonl')) { $line | ConvertFrom-Json | Out-Null }
    $circuitDir = Join-Path $workspace '.job-apply-autopilot\generated\circuit-test'
    New-Item -ItemType Directory -Force -Path $circuitDir | Out-Null
    [ordered]@{ job_id='circuit-test'; company='Circuit Co'; title='Backend Engineer'; job_url='https://pk.indeed.com/viewjob?jk=test'; source='indeed' } |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $circuitDir 'job.json') -Encoding UTF8
    [ordered]@{ filename='Circuit_Co_Backend_Engineer.pdf'; sha256='test' } |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $circuitDir 'resume-artifact.json') -Encoding UTF8
    $snapshot = (& (Join-Path $PSScriptRoot 'session-state.ps1') -Workspace $workspace | Select-Object -Last 1) | ConvertFrom-Json
    $circuitAction = @($snapshot.actions | Where-Object { $_.job_id -eq 'circuit-test' }) | Select-Object -First 1
    if ($null -ne $circuitAction) { throw 'Circuit-blocked job leaked into actionable state.' }
    if ($snapshot.summary.generated_circuit_blocked -ne 1 -or $snapshot.summary.circuit_breakers_active -ne 1) { throw "Circuit-breaker summary/routing failed: $($snapshot.summary | ConvertTo-Json -Compress)." }

    $snapshot = (& (Join-Path $PSScriptRoot 'session-state.ps1') -Workspace $workspace | Select-Object -Last 1) | ConvertFrom-Json
    if ($snapshot.summary.submitted_unique -ne 3 -or $snapshot.summary.submitted_rows -ne 3) {
        throw "Unique submission metrics failed: $($snapshot.summary | ConvertTo-Json -Compress)."
    }

    Write-Output 'PASS resilience: source gating, parallel throughput routing, deterministic transitions, semantic dedupe, idempotent sends, active circuit routing, unique metrics, and atomic governor recovery passed.'
} finally {
    Remove-Item -LiteralPath $workspace -Recurse -Force -ErrorAction SilentlyContinue
}
