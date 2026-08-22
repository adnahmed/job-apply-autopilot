---
name: job-apply-autopilot
description: "Goal-driven autonomous job discovery, truthful fit triage, tailored resumes, and idempotent verified submission through BrowserOS neo. Uses claimed actions, semantic dedupe, verification quarantine, and deterministic application outcomes."
---

# Job Apply Autopilot V6.3.0 — Zero-Credit API-Accelerated Parallel Pipeline

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

Never set goals in workers. The configured child-session gate prevents continuation coordinator turns while workers are active.

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

Discovery is also claimed:

```powershell
$claim = pwsh -NoProfile -ExecutionPolicy Bypass -File "$skillRoot\scripts\claim-action.ps1" `
  -Action Acquire -Scope Discovery -Stage discovery -Workspace $workspace -LeaseMinutes 15 | ConvertFrom-Json
```

Only the acquired discovery owner browses or creates items. Release after the pass with:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "$skillRoot\scripts\claim-action.ps1" `
  -Action Release -Scope Discovery -Stage discovery -Workspace $workspace -OwnerId '<owner_id>'
```

## Parallel pipeline

Issue all independent worker Task calls in one assistant turn. Respect `scheduler.active_wave` and each action's `wave`: exhaust `fast` before dispatching `research`. Group by `dispatch`, use every supplied `worker_prompt` verbatim, and rerun compact state after each wave. LinkedIn Easy Apply alone is serial at one; the skill imposes no concurrency ceiling on assessor, research, resume, external ATS, or email workers. The runtime may schedule as many independent workers as it can host.

Maintain the reported eight-item source-ready/actionable intake floor. Dispatch ready work, then fill `scheduler.discovery_slots`. Quarantined jobs do not consume discovery capacity.

Each worker prompt is exactly two lines:

```text
Work item directory: <absolute-path>
Action: <action>
```

Never append policy, evidence opinions, job summaries, or recovery instructions. Workers return only their documented canonical status line.

## Discovery and dedupe

Read `references\freehire-api.md` when changing or diagnosing FreeHire integration behavior.

Prefer keyless FreeHire discovery before browser search when `scheduler.discovery_slots` is positive:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "$skillRoot\scripts\discover-freehire.ps1" -Workspace $workspace -TargetNew $state.scheduler.discovery_slots
```

It performs one composite faceted request per fresh Pakistan, global-remote, and sponsorship lane; checks `meta.ignored_params`; stores full source/reality metadata; uses semantic-similar jobs only as a sparse-lane fallback; checks posting copies to recover a missing/aggregator route; ranks direct ATS/employer copies first; captures available application questions; and persists aggregator-only targets as `unresolved` route evidence. FreeHire reality is evidence with its workings, never an automatic employer verdict. Explicit denylist overrides, unnamed clients, and predatory funnels remain hard quality rejections.

All FreeHire calls go through `freehire-client.ps1`, whose method/path allowlist excludes every AI-credit endpoint. It may read an already-cached match analysis but never create one. It never calls CV tailoring or the generic assistant. Authentication resolves from `FREEHIRE_TOKEN`, then `FREEHIRE_API_KEY`, then the official CLI credential file; no token may enter a prompt, artifact, command result, repository file, or telemetry row.

For every plausible non-FreeHire job with a complete public source URL, run `enrich-freehire-workitem.ps1` immediately after local dedupe and source capture. It first checks `/jobs/find`, may send only a public HTTP(S) vacancy URL to `/jobs/resolve`, and falls back to deterministic `/me/match-text` when no catalogue slug exists. Private, authenticated, local-network, or user-info URLs are never sent. Enrichment failure is non-blocking.

Deterministic match coverage prioritizes otherwise-equal assessment actions. It is not a gate and cannot independently pass or reject a job. Assessors reuse its matched/adjacent/missing evidence while retaining full responsibility for eligibility, role identity, mandatory requirements, integrity, and truth feasibility. Daily market coverage is lane-allocation evidence only; it never changes canonical skills.

Derive local and regional lanes from `profile.yaml` (`candidate.location` and `search_defaults.locations`). Rotate lanes: home-country/local direct; explicitly compatible regional remote; worldwide/international contractor; sponsorship/relocation; direct employer/ATS; broader backend/platform/AI/software synonyms.

Batch visible-card identity through:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "$skillRoot\scripts\dedupe-jobs.ps1" `
  -CandidatesJson '<job_id/company/title JSON array>' -Workspace $workspace
```

Create plausible jobs only through the structured `new-workitem.ps1` contract, then replace the source placeholder with the complete JD only when status is `created`. `existing`, `duplicate`, and `rejected` are terminal results for that discovery candidate; never overwrite their artifacts or count them as newly discovered.

```powershell
$creation = pwsh -NoProfile -ExecutionPolicy Bypass -File "$skillRoot\scripts\new-workitem.ps1" `
  -JobId '<id>' -Company '<company>' -Title '<title>' -JobUrl '<url>' `
  -Location '<location>' -Source '<source>' -DiscoveryLane '<lane>' `
  -SearchQuery '<query>' -Workspace $workspace -Structured | ConvertFrom-Json
```

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

Run `preflight-application.ps1` before an external reservation whenever an answer plan exists. For required questions, call `resolve-application-answer.ps1`. It resolves canonical identity/education/employment facts, demographic declines, availability, and expected compensation. Salary resolution uses a posted range first, then cached FreeHire `/insights/salary` p25 data from the job's country/category/seniority with progressively broader market fallbacks, period conversion, and profile defaults only last. Unknown required capability/routine questions return `needs-semantic-answer`; unknown required identity, legal, authorization, or sensitive-disclosure facts return `blocked-protected-fact`. It never fabricates zero, No, or Not applicable defaults, and a per-claim loop guard stops the same normalized question after two attempts.

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

Never bypass CAPTCHA, MFA, security, truth, identity, eligibility, or work-authorization controls. One bad job or domain never ends unrelated work.

For a recoverable job-local failure, checkpoint through the exact transition command and continue other work:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "$skillRoot\scripts\defer-workitem.ps1" `
  -WorkItemDir '<absolute-path>' -Stage '<checkpoint-stage>' -Code '<short-code>' -Message '<message>'
```

The checkpoint stage may differ from the scheduler claim stage; the defer transition clears the active claim that actually exists. Backoff remains 1 minute, 5 minutes, then 30 minutes.

## Truth and autonomy

Never ask the user to choose, approve, or clarify routine campaign decisions. Choose `Recommended` when present, otherwise the first safe benign option. Resolve routine fields through the deterministic answer script. Factual fields must come from canonical/profile evidence or verified per-job evidence; use an honest decline/N/A for optional sensitive fields and reserve a protected-fact blocker for identity, legal, authorization, or sensitive disclosure only.

Never fabricate employer history, degree/licence/clearance, work authorization, people management, production metrics, specialist identity, or precise technology-specific duration. Overall software tenure supports a requirement only when the capability itself is supported or reasonably plausible. Ordinary form validation gets one correction. Confirm explicit success before recording `submitted`.

## Fault containment

Schema, script, worker, resume, and browser implementation errors are job/route-local. Correct once when deterministic; otherwise defer and continue. Never compensate for an assessor failure by having the coordinator construct or commit an assessment. If a resume worker returns empty or leaves an incomplete artifact, inspect only `resume-artifact.json` and re-dispatch that resume worker once; do not hand-tailor or manually compile in the coordinator.

Only the affected route stops for truthful impossibility, unresolved CAPTCHA after the single recovery window, MFA/security controls, or unavailable BrowserOS. Every unaffected domain, local stage, and discovery lane continues.

## Final invariant

Never claim completion or a natural pause while state contains unclaimed actions or needed discovery. Never invent ledger statuses. Verified net-new unique company/title submissions are the headline; raw ledger rows are audit detail.
