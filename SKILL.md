---
name: job-apply-autopilot
description: "Goal-driven autonomous job discovery, truthful fit triage, tailored resumes, and idempotent verified submission through BrowserOS neo. Uses claimed actions, semantic dedupe, verification quarantine, and deterministic application outcomes."
---

# Job Apply Autopilot V6.4.0 — Continuous Discovery and Completion-First Answers

Mission: maximize credible net-new interview opportunities per unit time while preserving truth, the candidate's documented geographic eligibility, security controls, and duplicate safety. Tool activity, duplicate work, placeholders, and unverified outcomes are not progress.

## Persistence contract

Persistent campaigns use exactly one session-scoped goal from `opencode-goal-plugin@0.8.1`. Never start a watchdog, OS background process, campaign runner, second coordinator loop, or another persistence mechanism.

When the user explicitly requests continuous operation and no goal is active, create one goal: keep discovering, assessing, tailoring, and submitting net-new applications until the user runs `/goal pause` or `/goal stop`. Never complete it because a submission count was reached, the queue is temporarily empty, a route is blocked, or BrowserOS is down. Goal restart recovery is deliberately paused; after an OpenCode restart the user resumes it with `/goal resume`.

Every initial turn and every goal continuation must rerun the authoritative state:

```powershell
$workspace = (Get-Location).Path
$state = pwsh -NoProfile -ExecutionPolicy Bypass -File "$skillRoot\scripts\session-state.ps1" -Workspace $workspace -Compact | ConvertFrom-Json
$freehireSync = pwsh -NoProfile -ExecutionPolicy Bypass -File "$skillRoot\scripts\sync-freehire-context.ps1" -Workspace $workspace -Compact | ConvertFrom-Json
if ($freehireSync.submission_proofs -gt 0) {
    $state = pwsh -NoProfile -ExecutionPolicy Bypass -File "$skillRoot\scripts\session-state.ps1" -Workspace $workspace -Compact | ConvertFrom-Json
}
```

The FreeHire context sync is deterministic, cached, and fail-open. Missing credentials, a provider outage, or a rate-limit response never blocks local or browser work. It may resolve an ambiguous send only from an exact slug-linked employer message satisfying the send guard; otherwise it only refreshes candidate, market, mail, and credit telemetry.

Never set goals in workers. All `job-autopilot-*` Task workers MUST be launched with `background=true`. Do not wait for worker completion before scheduling unrelated work.

## State routing

Trust `actions`, `scheduler`, claim metadata, and these stages:

1. `reconcile_result`: claim, run `reconcile-application-result.ps1`, rerun state.
2. `application_outcome_repair`: dispatch the matching applicator only to write/reconstruct the terminal result; never resume the form.
3. `application_verification`: dispatch the matching applicator to verify the prior side effect; never start a fresh application.
4. `application_verification_quarantined`: do nothing automatically. It is isolated from the ledger and unrelated work.
5. `route_pending`: resolve and persist `application-route.json`; never infer a route from source/domain.
6. `email_application_ready`: dispatch `job-autopilot-email-apply`.
7. `linkedin_application_ready`: handle LinkedIn Easy Apply serially under its governor.
8. `application_ready` / `application_resume`: route to the matching applicator immediately.
9. `resume_pending`: dispatch `job-autopilot-resume`.
10. `coordinator_adjudication_pending`: claim and run `advance-workitem.ps1`.
11. `assessment_repair`: claim and repair deterministically, then rerun state.
12. `assessment_pending` / `reassessment_pending`: dispatch `job-autopilot-assessor`.
13. `source_pending`: claim, capture the complete source, release the claim, rerun state.
14. `eligibility_research_pending` / `candidate_evidence_pending`: dispatch `job-autopilot-research` in a separate web-heavy wave.

Cooldown, verification grace, domain circuit breaker, and actively claimed items are non-actionable until their timestamps expire. Never wait for them while other work or discovery exists.

## Action claims

Competing sessions may snapshot the same action, but only one owner proceeds. Workers acquire their own stage before reading. For every coordinator-local work item, acquire first:

```powershell
$claim = pwsh -NoProfile -ExecutionPolicy Bypass -File "$skillRoot\scripts\claim-action.ps1" `
  -Action Acquire -Scope WorkItem -Stage '<state-stage>' -WorkItemDir '<absolute-path>' -Workspace $workspace -LeaseMinutes 20 | ConvertFrom-Json
```

If `acquired` is false, exit that action immediately. Keep `owner_id`. Transition scripts clear matching claims. If no transition occurred, release with the complete identity tuple; `-OwnerId` alone is not a valid command:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "$skillRoot\scripts\claim-action.ps1" `
  -Action Release -Scope WorkItem -Stage '<state-stage>' -WorkItemDir '<absolute-path>' `
  -Workspace $workspace -OwnerId '<owner_id>'
```

Claims expire automatically after the lease.

Discovery claims are now source-specific. FreeHire and LinkedIn/browser each own their own claim file and never share a discovery claim.

FreeHire discovery claim:
```powershell
$claim = pwsh -NoProfile -ExecutionPolicy Bypass -File "$skillRoot\scripts\claim-action.ps1" `
  -Action Acquire -Scope Discovery -Stage discovery -DiscoverySource freehire -Workspace $workspace -LeaseMinutes 15 | ConvertFrom-Json
```

LinkedIn/browser discovery claim:
```powershell
$claim = pwsh -NoProfile -ExecutionPolicy Bypass -File "$skillRoot\scripts\claim-action.ps1" `
  -Action Acquire -Scope Discovery -Stage discovery -DiscoverySource linkedin-browser -Workspace $workspace -LeaseMinutes 60 | ConvertFrom-Json
```

Release with the matching `-DiscoverySource`:
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "$skillRoot\scripts\claim-action.ps1" `
  -Action Release -Scope Discovery -Stage discovery -DiscoverySource freehire -Workspace $workspace -OwnerId '<owner_id>'
pwsh -NoProfile -ExecutionPolicy Bypass -File "$skillRoot\scripts\claim-action.ps1" `
  -Action Release -Scope Discovery -Stage discovery -DiscoverySource linkedin-browser -Workspace $workspace -OwnerId '<owner_id>'
```

FreeHire claim uses `.job-apply-autopilot/discovery-action-claim.freehire.json`. LinkedIn claim uses `.job-apply-autopilot/discovery-action-claim.linkedin-browser.json`. Neither claim blocks the other source. The legacy `discovery-action-claim.json` is read only for migration compatibility and is never created.

## Parallel pipeline

### DISPATCH RULE

After calling `session-state.ps1 -Compact`:

1. Read `state.actions`.
2. Emit every independent action in `state.actions` in the SAME assistant tool-call turn, subject only to explicit concurrency limits.
3. Never build a separate mental/planned action list.
4. Never postpone an action that is already present in `state.actions`.
5. Before ending the dispatch turn, compare the number of emitted action calls against `state.scheduler.dispatch_manifest.expected_count`.
6. If fewer actions were emitted, immediately emit the missing `action_ids`.
7. Do not continue with prose while a dispatchable state action was omitted.

**All independent `job-autopilot-*` Task workers MUST be launched with `background=true`.**

**Do not wait for worker completion before scheduling unrelated work.**

**After every coordinator continuation:**
1. run `session-state.ps1 -Compact`
2. dispatch every action returned
3. launch worker actions with `background=true`
4. do not poll workers
5. do not summarize worker results before scheduling the next available work

**When a background worker completion notification arrives:**
immediately rerun `session-state.ps1 -Compact` and dispatch newly unlocked work.

**A running LinkedIn discovery worker must not block:**
- FreeHire discovery
- assessments
- research
- resumes
- external applications
- email applications

FreeHire receives `scheduler.discovery_sources.freehire.target_new`. LinkedIn/browser discovery receives the bounded target already emitted in its `action.target_new`. A discovery claim prevents duplicate producers; once it clears, the next continuation launches another batch. Quarantined jobs do not affect discovery.

Each work-item worker prompt is exactly four identity lines; the worker resolves the authoritative directory through the manifest script:

```text
Workspace: <absolute-path>
Job ID: <job-id>
Kind: queue|generated
Action: <action>
```

Never append policy, evidence opinions, job summaries, or recovery instructions. Workers return only their documented canonical status line.

LinkedIn discovery is the sole campaign-worker exception and uses the exact supplied five-line prompt: `Workspace`, `Job ID: discovery:continuous`, `Kind: campaign`, `Action: discovery`, and `Target New`. Dispatch it verbatim; do not add policy or source results.

## Discovery and dedupe

Read `references\freehire-api.md` when changing or diagnosing FreeHire integration behavior. Read `references\browseros-playbook.md` when LinkedIn or other browser discovery starts.

Run independent FreeHire and LinkedIn/browser discovery immediately and concurrently whenever `scheduler.discovery_needed` is true. `session-state.ps1` emits the FreeHire command and a `job-autopilot-linkedin-discovery` worker prompt as separate actions. FreeHire receives `scheduler.discovery_sources.freehire.target_new`. LinkedIn/browser discovery receives the bounded target already emitted in its `action.target_new`. A completed or full FreeHire batch never reduces, satisfies, or skips the LinkedIn worker. FreeHire is one discovery source, not the whole discovery pipeline.

**FreeHire discovery is an asynchronous deterministic producer.** The coordinator launches `start-freehire-discovery.ps1` and immediately continues scheduling. Do not wait for the spawned FreeHire process. Its source-specific claim prevents duplicate producers.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "$skillRoot\scripts\start-freehire-discovery.ps1" -Workspace $workspace -TargetNew $state.scheduler.discovery_sources.freehire.target_new
```

The FreeHire pass performs one composite faceted request per fresh home-country, global-remote, and sponsorship/relocation lane; checks `meta.ignored_params`; stores full source/reality metadata; uses semantic-similar jobs only as a sparse-lane fallback; checks posting copies to recover a missing/aggregator route; ranks direct ATS/employer copies first; captures available application questions; and persists aggregator-only targets as `unresolved` route evidence. In the same cycle, start the independent LinkedIn/browser lanes immediately and pursue the bounded target emitted in their action while respecting the LinkedIn activity governor and any warning, CAPTCHA, MFA, or rate-limit controls. FreeHire reality is evidence with its workings, never an automatic employer verdict. Explicit denylist overrides, unnamed clients, and predatory funnels remain hard quality rejections.

All FreeHire calls go through `freehire-client.ps1`, whose method/path allowlist excludes every AI-credit endpoint. It may read an already-cached match analysis but never create one. It never calls CV tailoring or the generic assistant. Authentication resolves from `FREEHIRE_TOKEN`, then `FREEHIRE_API_KEY`, then the official CLI credential file; no token may enter a prompt, artifact, command result, repository file, or telemetry row.

For every plausible non-FreeHire job, including LinkedIn/browser-discovered jobs, with a complete public source URL, FreeHire enrichment runs asynchronously after local dedupe. It first checks `/jobs/find`, may send only a public HTTP(S) vacancy URL to `/jobs/resolve`, and falls back to deterministic `/me/match-text` when no catalogue slug exists. Private, authenticated, local-network, or user-info URLs are never sent. Enrichment failure is non-blocking.

**FreeHire persistence is split:**
- **Create + route are synchronous** via `finalize-discovered-workitem.ps1`. This atomic finalizer performs work-item creation, `source.md`, `source-metadata.json`, and route persistence in one call. Passing a complete `-Description` writes the real JD during creation—no placeholder replacement step remains.
- **FreeHire enrichment is asynchronous supplemental work** launched via `start-freehire-enrichment.ps1`. It must not delay assessment dispatch.

Deterministic match coverage prioritizes otherwise-equal assessment actions. It is not a gate and cannot independently pass or reject a job. Assessors reuse its matched/adjacent/missing evidence while retaining full responsibility for eligibility, role identity, mandatory requirements, integrity, and truth feasibility. Daily market coverage is lane-allocation evidence only; it never changes canonical skills.

Derive local and regional lanes from `profile.yaml` (`candidate.location.country_code` and `search_defaults.locations`). Rotate lanes: home-country/local direct; explicitly compatible regional remote; worldwide/international contractor; sponsorship/relocation; direct employer/ATS; broader backend/platform/AI/software synonyms.

Batch visible-card identity through:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "$skillRoot\scripts\dedupe-jobs.ps1" `
  -CandidatesJson '<job_id/company/title JSON array>' -Workspace $workspace
```

Accepted FreeHire jobs are persisted through `finalize-discovered-workitem.ps1` only. `existing`, `duplicate`, and `rejected` are terminal results for that discovery candidate; never overwrite their artifacts or count them as newly discovered.

Discovery/assessment skips use only an allowed value through `log-decision.ps1`: `skipped-job-quality`, `skipped-obvious`, `skipped-duplicate`, `skipped-closed`, `skipped-ineligible`, `skipped-low-fit`, `skipped-mandatory-gate`, `skipped-stack-mismatch`, `skipped-role-family`, `skipped-location-lock`, `skipped-work-auth-gate`, `skipped-location-gate`, `skipped-agency-unknown-client`, `skipped-agency`, `skipped-aggregator`, `skipped-management-only`, or `skipped-license-clearance`. The command rejects application-route statuses and promoted jobs; application blockers use the application outcome writer.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "$skillRoot\scripts\log-decision.ps1" `
  -JobId '<id>' -Status '<allowed-skip-status>' -ReasonCode '<code>' `
  -Company '<company>' -Title '<title>' -JobUrl '<url>' -Source '<source>' -Workspace $workspace
```

## Assessment, promotion, and resume

Queue roles plausibly worth applying to. Default score threshold is 72; 68–71 may pass only with strong role identity and eligibility. Hard failures are legal/work-auth/credential blockers, fundamentally different specialist identity, defining unsupported management, or several absent defining capabilities.

Assessment writes go only through `commit-assessment.ps1` with `-ExpectedPriorStatus`. It validates the complete payload and returns every schema error in one rejection, enforces the score threshold, and is first-writer-safe: `already-committed` means stale or duplicate work must stop. Research finalizes pass/fail in the same worker call. `advance-workitem.ps1` independently refuses legacy passed assessments below the same threshold.

Passed work advances only through:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "$skillRoot\scripts\advance-workitem.ps1" `
  -WorkItemDir '<path>' -Canonical <ai|backend> -Workspace $workspace
```

Promotion and resume compilation reuse valid existing generated directories/artifacts under work-item locks.

Route ready work immediately using only `application-route.json`. Persist routes through `set-application-route.ps1`; never infer them from the discovery source. Direct employer-email applications go only to `job-autopilot-email-apply`; external ATS/company forms go only to `job-autopilot-external-apply`. Every applicator reservation re-runs the quality gate. LinkedIn Easy Apply remains coordinator-owned and serial under its governor.

Run `preflight-application.ps1` before an external reservation whenever an answer plan exists. It resolves all questions in a single batch via `resolve-application-page.ps1`. For required questions, semantic answers are generated once and stored in `application-answer-plan.json`; during live page processing, `resolve-application-page.ps1` reuses those answers. Missing identity, legal, authorization, and sensitive fields return `needs-semantic-answer`; the applicator generates one concrete context-aware answer and continues, with one correction after exact form validation. Missing facts never create a protected-fact blocker or skip. Current and expected numeric compensation share the same posted-range, FreeHire market-p25, and profile-fallback strategy.

## Submission and quarantine

Every external side effect uses `application-send-guard.ps1`. A missing result, interrupted worker, public page, browser history entry, missing local file, or missing confirmation email never proves absence.

After local reconciliation records a verified submission, `reconcile-application-result.ps1` best-effort mirrors the FreeHire `applied` state for work items carrying a catalogue slug. The local ledger remains authoritative and remote failure never rolls it back. An already-connected FreeHire Gmail account is optional: context sync may queue incremental sync and consume exact linked signals, but it never connects, disconnects, deletes, uploads arbitrary mail, accepts suggested links, or treats unlinked mail as proof.

Channel-compatible absence proof is mandatory:

- external ATS: authenticated application tracker absence (`authenticated-ats-tracker-absence`);
- email: exact authenticated recipient/subject Sent-search absence (`exact-sent-search-absence`);
- user: `ConfirmAbsent` through `resolve-application-quarantine.ps1` (`user-confirmed-absence`).

If authoritative verification is unavailable, the applicator calls `QuarantineVerification`. A quarantined job is non-actionable, creates no ledger row, is neither submitted nor skipped, and cannot block other jobs or discovery.

Terminal blockers are written only through `write-application-outcome.ps1`, then reconciled. Terminal progress without a result routes only to `application_outcome_repair`.

Coordinator-owned LinkedIn Easy Apply follows the same claim and send guard: reserve with `-Channel linkedin-easy-apply` before opening the modal, mark only explicit tracker/success confirmation as submitted, then record the governor event. It never writes the ledger or uses `log-decision.ps1` for an application outcome.

Users resolve quarantine without editing JSON:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "$skillRoot\scripts\resolve-application-quarantine.ps1" -Action List -Workspace $workspace
```

Other actions are `Reverify`, `ConfirmSubmitted`, `ConfirmAbsent`, `RetryApplication`, and `Abandon`, with `-WorkItemDir` and `-Proof` where required. `Reverify` authorizes verification only, never Submit. `RetryApplication` accepts only a proven pre-submit/cancelled or verified-absent state and refuses submitted/semantic duplicates; it can reopen eligible legacy `route_blocked` entries.

## BrowserOS and blocking

Read the installed `references\browseros-playbook.md` when browser work starts. Call BrowserOS `run` at most once after a compatibility failure, then use granular tools; never probe denied shell or raw CDP methods. Use only task-owned tabs and fresh real upload-input refs.

On BrowserOS connection loss, stop browser calls after one cheap health probe, finish all available local actions, persist/checkpoint affected work, and continue unrelated local work. If state exposes nothing useful that can proceed without BrowserOS, block the active goal with the concrete BrowserOS failure. Recovery is BrowserOS restoration followed by `/goal resume`.

Never bypass CAPTCHA, MFA, account security, duplicate-submission, or ambiguous-side-effect controls. Required application facts follow the configured completion-first generated-answer policy. One bad job or domain never ends unrelated work.

For a recoverable job-local failure, checkpoint through the exact transition command and continue other work:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "$skillRoot\scripts\defer-workitem.ps1" `
  -WorkItemDir '<absolute-path>' -Stage '<checkpoint-stage>' -Code '<short-code>' -Message '<message>'
```

The checkpoint stage may differ from the scheduler claim stage; the defer transition clears the active claim that actually exists. Backoff remains 1 minute, 5 minutes, then 30 minutes.

## Discovery ownership

FreeHire owns:
`discovery-action-claim.freehire.json`

LinkedIn owns:
`discovery-action-claim.linkedin-browser.json`

They never share a discovery claim.

Discovery is a producer.
Assessment, resume generation and application processing are consumers.
Producer execution must not form a synchronization barrier with consumers.

## Truth and autonomy

Never ask the user to choose, approve, or clarify routine campaign decisions. Choose `Recommended` when present, otherwise the first safe benign option. Resolve fields through the deterministic answer script first; for every unresolved mandatory field, generate one context-aware answer and continue. Missing identity, legal, authorization, compensation, or sensitive information never creates a protected-fact blocker or skip.

Never fabricate employer history, degree/licence/clearance, people management, production metrics, specialist identity, or unsupported technologies in resumes and fit artifacts. Generated mandatory form answers never become canonical resume evidence. Overall software tenure supports a requirement only when the capability itself is supported or reasonably plausible. Ordinary form validation gets one correction. Confirm explicit success before recording `submitted`.

## Fault containment

Schema, script, worker, resume, and browser implementation errors are job/route-local. Worker PowerShell is intentionally broad so routine commands and installed scripts are not rejected by brittle string allowlists. Correct deterministic failures once; otherwise defer and continue. Never compensate for an assessor failure by having the coordinator construct or commit an assessment. If a resume worker returns empty or leaves an incomplete artifact, inspect only `resume-artifact.json` and re-dispatch that resume worker once; do not hand-tailor or manually compile in the coordinator.

Only the affected route stops for a confirmed hard eligibility rejection, unresolved CAPTCHA after the single recovery window, MFA/security controls, or unavailable BrowserOS. Missing application facts do not stop it. Every unaffected domain, local stage, and discovery lane continues.

## Final invariant

Never claim completion or a natural pause while state contains unclaimed actions or needed discovery. Never invent ledger statuses. Verified net-new unique company/title submissions are the headline; raw ledger rows are audit detail.
