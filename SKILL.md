---
name: job-apply-autopilot
description: "Persistent autonomous job discovery, truthful fit triage, tailored resumes, and idempotent verified submission through BrowserOS neo. Uses specialized subagents, semantic dedupe, circuit breakers, and a resilient overnight supervisor."
---

# Job Apply Autopilot V5.15.1 — Reliability Hotfix

Mission: maximize credible, **net-new** interview opportunities per unit time. Preserve truth, Pakistan eligibility, anti-automation safety, and useful resumes. Raw tool activity, duplicate submissions, and queued placeholders are not progress.

## Hot loop

Do not plan, narrate, ask routine questions, or inspect files that the state script already summarized.

If the user asks to run forever, continuously, overnight, in the background, or complains that a prior continuous run stopped, treat persistent supervision as the first action. Run `get-autopilot-status.ps1`; if it is not running, run `start-autopilot.ps1`. Report the supervisor PID/state and return instead of trying to simulate persistence inside one chat turn.

If `goal_status` and `goal_set` are available and the user explicitly requested this persistent campaign, inspect goal state once. When no goal is active, set one continuous coordinator goal: keep discovering, assessing, tailoring, and submitting net-new applications until the user runs `/goal pause` or `/goal stop`. Never complete the goal because a submission count was reached, the current queue is empty, one route is blocked, or a supervisor slice ends; rotate discovery lanes and let the outer supervisor recover process/provider exits. Never set goals in workers. Goal continuation is control flow only: rerun state after every continuation and verify ambiguous side effects before retrying.

At start, capture the coordinator workspace once and run:

```powershell
$workspace = (Get-Location).Path
$state = pwsh -NoProfile -ExecutionPolicy Bypass -File "$skillRoot\scripts\session-state.ps1" -Workspace $workspace
```

Trust `next_action`, `actions`, and `scheduler`. `actions` is the complete runnable cross-stage pipeline, not a single-job suggestion. Dispatch independent work concurrently, rerun `session-state.ps1` after each wave, and repeat:

1. `reconcile_result`: run `reconcile-application-result.ps1` for the supplied directory and continue; never hand-append the ledger.
2. `application_verification`: dispatch the matching applicator to verify the prior side effect; never start a fresh application.
3. `email_application_ready`: dispatch `job-autopilot-email-apply`.
4. `application_ready` / `application_resume`: route immediately.
5. `resume_pending`: dispatch the resume worker.
6. `coordinator_adjudication_pending` / `assessment_repair`: run `advance-workitem.ps1`.
7. `assessment_pending` / `reassessment_pending`: dispatch the lean all-in-one assessors.
8. `source_pending`: capture the full JD from `job_url` into `source.md`; never assess a placeholder.
9. `discover`: search and queue unseen plausible jobs.
10. `eligibility_research_pending` / `candidate_evidence_pending`: dispatch `job-autopilot-research` as a separate web-heavy wave.

`recoverable_cooldown` and `domain_circuit_breaker` are intentionally omitted until their retry time. Never wait for them while other work or discovery exists.

## Throughput scheduler — mandatory

The campaign is a parallel pipeline, not a one-job transaction loop. A single job remains sequential across its own dependencies, but independent jobs must overlap.

- Issue all eligible worker Task calls in one assistant turn so the harness can run them concurrently. Never call one worker and wait before issuing the next eligible call.
- Dispatch every assessor, research, resume, external ATS, and email worker path concurrently up to runtime capacity. There is no skill numeric cap for any of them. LinkedIn Easy Apply alone stays coordinator-owned and serial at 1.
- Group `actions` by their `dispatch` field and emit every eligible Task call together. Do not reduce a group to its first path.
- A worker failure does not create a global barrier. Verify its artifact once, defer or re-dispatch that job as appropriate, and keep every other completed job moving.
- Maintain a minimum pipeline buffer of 8 source-ready/actionable jobs. This is an intake floor, not a work cap. Dispatch ready work first, then refill the reported `discovery_slots`; never require an empty queue before discovery.
- Keep web-heavy `job-autopilot-research` calls out of a fast-worker wave when the harness waits for the whole wave. Fast results and ready applications must not wait behind research.

Throughput is measured by verified net-new submissions per hour. Lower first-job latency is useful, but it must not collapse worker utilization or discovery intake.

## Progress definition

A useful submission is a verified submission to a company/title identity not submitted in the previous 45 days. A repost, regional mirror, or new job ID for the same company/title is a duplicate—not another application.

Use structured semantic dedupe whenever cards include company/title:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "$skillRoot\scripts\dedupe-jobs.ps1" `
  -CandidatesJson '<JSON array: job_id, company, title>' -Workspace $workspace
```

Exact-ID-only `-JobIdsCsv` remains available when cards expose no identity. `new-workitem.ps1` performs a second semantic guard. If it returns `DUPLICATE:...`, continue immediately and never treat that string as a path.

Reports use `submitted_unique` as the headline. `submitted_rows` is audit detail only.

## Discovery fast path

Search in this order, switching lane immediately after a dry result:

1. Pakistan/local direct roles;
2. APAC/APJ/Asia remote roles with explicit regional eligibility;
3. worldwide/international-contractor roles;
4. sponsorship/relocation roles;
5. direct employer and ATS sources beyond LinkedIn;
6. broader backend/platform/AI/software title synonyms and freshness window.

Use one BrowserOS extraction for visible card identity, then batch dedupe before opening details. Open full pages only for unseen plausible candidates and close completed disposable tabs promptly. A discovery pass fills the reported pipeline buffer: capture complete JDs continuously until the buffer target is met or the lane is dry, and only then rerun state. Do not stop discovery after the first plausible job.

Obvious closed, ineligible, unrelated, marketplace/agency-without-client, management-only, licence/clearance, or decisive stack-identity failures get one compact row:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "$skillRoot\scripts\log-decision.ps1" `
  -JobId '<id>' -Status '<skip-status>' -ReasonCode '<code>' -Company '<company>' `
  -Title '<title>' -JobUrl '<url>' -Source '<source>' -Workspace $workspace
```

For each plausible job in the current discovery batch, create a work item and write concise metadata plus the complete JD to its `source.md`. Rerun state after the batch, not after each job. Never leave a newly created placeholder as `assessment_pending`:

```powershell
$workItem = pwsh -NoProfile -ExecutionPolicy Bypass -File "$skillRoot\scripts\new-workitem.ps1" `
  -JobId '<id>' -Company '<company>' -Title '<title>' -JobUrl '<url>' `
  -Location '<location>' -Source '<source>' -DiscoveryLane '<lane>' `
  -SearchQuery '<query>' -Workspace $workspace
```

## Fast assessment

Queue only roles plausibly worth applying to. Default threshold is 72; 68–71 may pass opportunistically when role identity and eligibility are strong. A few adjacent learnable gaps are normal.

Hard failures are limited to legal/work-auth/credential blockers, fundamentally different specialist identity, defining unsupported management, or several clearly absent role-defining capabilities.

`job-autopilot-assessor` is local and web-free. It reads `job.json`, real `source.md`, canonical facts, cached evidence, and existing per-job reports, then commits through:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "$skillRoot\scripts\commit-assessment.ps1" ...
```

Do not hand-write assessment transition JSON. Passed jobs have at most eight central fit requirements. The assessor may request exactly one decision-changing research kind. Both eligibility and candidate-evidence requests go to `job-autopilot-research`, which consumes existing reports first, performs only bounded missing research, and commits the final pass/fail itself—there is no third reassessment call. Unresolved ordinary stack evidence reduces score rather than proving absence; unresolved positive eligibility cannot pass.

Positive Pakistan eligibility is required before Submit: exact Pakistan, explicit worldwide/international hiring, Pakistan in a list, explicit APAC/APJ/Asia without conflict, global contractor wording, sponsorship, or relocation. Generic `Remote` alone is not evidence.

## Promotion, resume, and routing

Advance passed work only through:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "$skillRoot\scripts\advance-workitem.ps1" `
  -WorkItemDir $workItem -Canonical <ai|backend> -Workspace $workspace
```

On `promoted`, add the job to the next resume wave immediately. Route completed resume artifacts without waiting for unrelated work; this does not authorize serial one-job worker dispatch.

LinkedIn Easy Apply is coordinator-owned. Check the governor before opening the modal; after explicit confirmation record:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "$skillRoot\scripts\linkedin-governor.ps1" `
  -Action RecordEasyApply -JobId '<id>' -Workspace $workspace
```

Direct employer-email applications go only to `job-autopilot-email-apply`. External ATS/company forms go to `job-autopilot-external-apply`. Both are uncapped by skill policy and run concurrently up to runtime capacity. OAuth/existing session comes before password signup.

Both applicators must reserve the outbound attempt through `scripts/application-send-guard.ps1`. A missing `application-result.json`, interrupted worker, or ambiguous return is not proof that nothing was sent. Route the same worker back for verification; it must search the real Sent/ATS state before a second side effect is even eligible.

## BrowserOS rules

Read `references/browseros-playbook.md` when browser work begins or the first browser action fails. Its rules are operational, not optional:

- always open task-owned tabs; never retry a foreign page ID;
- try `run` at most once per MCP session after a compatibility failure, then use granular tools;
- never probe unavailable raw CDP DOM methods;
- upload only through a fresh ref to an actual file input;
- after `Unable to connect`/CDP loss, stop browser calls for the slice, do local work, persist state, and return for supervisor recovery;
- browser loss is not campaign completion.

One bad site/job never ends the campaign. For recoverable technical failures call `defer-workitem.ps1 -WorkItemDir <path> -Stage <current-stage> -Code <compact-code> -Message <compact-message>` (1m, 5m, then 30m backoff), then continue. Do not invent `-Reason` or `-Workspace` parameters. A standalone CAPTCHA gets the solver-aware recovery flow in `references/captcha-recovery.md`: preserve the tab, click one ordinary challenge trigger when available, wait up to 120 seconds, and continue if it clears. CAPTCHA presence alone does not trip a domain circuit. MFA, account restrictions, explicit automation/security warnings, attributable 429s, failed solver recovery, or a repeated challenge are recorded only through `domain-circuit-breaker.ps1 -Action Record`. Never hand-append circuit-breaker JSONL.

## Truth and autonomy

Never ask the user to choose, approve, or clarify routine workflow decisions. Choose Recommended, otherwise the first safe benign option. For factual fields use canonical/profile evidence, an honest decline/N/A, or skip the job.

Never fabricate employer history, degree/licence/clearance, work authorization, people management, production metrics, specialist identity, or precise technology-specific duration. Overall software tenure may support a requirement only when the capability itself is supported or reasonably plausible.

Ordinary form validation gets one correction. Confirm explicit success before recording `submitted`. Keep logs compact.

Never declare a natural pause, completion, or exhaustion while the final `session-state.ps1` snapshot contains actions. The final words and the machine state must agree.

## Fault containment

Schema, script, worker, resume, and browser implementation errors are job/route-local. Correct once when deterministic; otherwise defer and continue. Do not repeatedly reconsider the same branch. Never compensate for a packaged assessor failure by adding prompt lines, reading candidate evidence in the coordinator, building its payload, or calling `commit-assessment.ps1` yourself. If a resume worker returns empty or leaves `resume.tex` with an incomplete audit, inspect only `resume-artifact.json`, then re-dispatch that same resume worker once; the coordinator must not inspect compiler code/parameters or attempt manual compilation.

Only the affected route stops for truthful impossibility, an unresolved CAPTCHA after solver recovery, MFA/security controls, or unavailable BrowserOS. Other domains, local stages, and discovery continue.

## Overnight supervision

A single chat/agent turn cannot keep running after its host process exits. For persistent operation, use the packaged supervisor from the campaign workspace after BrowserOS neo is open and healthy:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "$skillRoot\scripts\start-autopilot.ps1" -Workspace $workspace
```

It keeps Windows awake without keeping the display on, launches bounded fresh OpenCode slices, restarts after normal/error exits, and waits without spending model sessions when MCP port 9010 is up but browser CDP port 9110 is down. State and slice logs live under `.job-apply-autopilot\supervisor`.

Inspect it deterministically with:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "$skillRoot\scripts\get-autopilot-status.ps1" -Workspace $workspace
```

Stop it cleanly with:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "$skillRoot\scripts\stop-autopilot.ps1" -Workspace $workspace
```

BrowserOS neo, its signed-in profile, internet access, and the PC must remain available. If BrowserOS itself crashes and does not relaunch, the supervisor waits until the user starts it again; it does not bypass BrowserOS or security controls.

## Worker prompt contract

Use `actions[].worker_prompt` verbatim when present. Each worker prompt is exactly two lines: `Work item directory: <absolute-path>` and `Action: <action>`. Do not append efficiency notes, policy, evidence opinions, job summaries, or recovery instructions. Multiple one-job Task calls belong in the same assistant turn. Workers do not load this main skill, invoke nested workers, write shared ledgers, or ask questions. They return one terse status line; the coordinator reruns state after the wave and continues.
