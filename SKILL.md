---
name: job-apply-autopilot
description: "Fast autonomous job discovery, truthful fit triage, tailored resumes, and verified submission through BrowserOS neo. Uses persistent state, semantic dedupe, bounded recovery, and an optional overnight supervisor."
version: 5.13.0
---

# Job Apply Autopilot V5.13 — Net-New Throughput Edition

Mission: maximize credible, **net-new** interview opportunities per unit time. Preserve truth, Pakistan eligibility, anti-automation safety, and useful resumes. Raw tool activity, duplicate submissions, and queued placeholders are not progress.

## Hot loop

Do not plan, narrate, ask routine questions, or inspect files that the state script already summarized.

At start, capture the coordinator workspace once and run:

```powershell
$workspace = (Get-Location).Path
$state = pwsh -NoProfile -ExecutionPolicy Bypass -File "$skillRoot\scripts\session-state.ps1" -Workspace $workspace
```

Trust `next_action` and `actions`. Perform the highest useful action, rerun `session-state.ps1`, and repeat:

1. `reconcile_result`: log the supplied `application-result.json` and continue.
2. `application_ready` / `application_resume`: route immediately.
3. `resume_pending`: dispatch the resume worker.
4. `coordinator_adjudication_pending` / `assessment_repair`: run `advance-workitem.ps1`.
5. `assessment_pending` / `reassessment_pending`: dispatch quick assessors.
6. `source_pending`: capture the full JD from `job_url` into `source.md`; never assess a placeholder.
7. `discover`: search and queue unseen plausible jobs.
8. `eligibility_research_pending` / `candidate_evidence_pending`: slow lane only after fast work.

`recoverable_cooldown` is intentionally omitted until its retry time. Never wait for it while other work or discovery exists.

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

Use one BrowserOS extraction for visible card identity, then batch dedupe before opening details. Open full pages only for unseen plausible candidates. Keep one search tab and at most four detail/application tabs.

Obvious closed, ineligible, unrelated, marketplace/agency-without-client, management-only, licence/clearance, or decisive stack-identity failures get one compact row:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "$skillRoot\scripts\log-decision.ps1" `
  -JobId '<id>' -Status '<skip-status>' -ReasonCode '<code>' -Company '<company>' `
  -Title '<title>' -JobUrl '<url>' -Source '<source>' -Workspace $workspace
```

For a plausible job, create a work item, write concise metadata plus the complete JD to its `source.md`, then rerun state. Never leave a newly created placeholder as `assessment_pending`:

```powershell
$workItem = pwsh -NoProfile -ExecutionPolicy Bypass -File "$skillRoot\scripts\new-workitem.ps1" `
  -JobId '<id>' -Company '<company>' -Title '<title>' -JobUrl '<url>' `
  -Location '<location>' -Source '<source>' -DiscoveryLane '<lane>' `
  -SearchQuery '<query>' -Workspace $workspace
```

## Fast assessment

Queue only roles plausibly worth applying to. Default threshold is 72; 68–71 may pass opportunistically when role identity and eligibility are strong. A few adjacent learnable gaps are normal.

Hard failures are limited to legal/work-auth/credential blockers, fundamentally different specialist identity, defining unsupported management, or several clearly absent role-defining capabilities.

`job-autopilot-assessor` reads `job.json`, real `source.md`, canonical facts, and existing narrow research. It does no web search and commits only through:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "$skillRoot\scripts\commit-assessment.ps1" ...
```

Do not hand-write assessment transition JSON. Passed jobs have at most eight central fit requirements. If narrow evidence or eligibility research would change apply/skip, route it once; unresolved ordinary stack evidence reduces score rather than proving absence.

Positive Pakistan eligibility is required before Submit: exact Pakistan, explicit worldwide/international hiring, Pakistan in a list, explicit APAC/APJ/Asia without conflict, global contractor wording, sponsorship, or relocation. Generic `Remote` alone is not evidence.

## Promotion, resume, and routing

Advance passed work only through:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "$skillRoot\scripts\advance-workitem.ps1" `
  -WorkItemDir $workItem -Canonical <ai|backend> -Workspace $workspace
```

On `promoted`, dispatch `job-autopilot-resume`, then route as soon as its artifact is ready. Do not wait for a batch.

LinkedIn Easy Apply is coordinator-owned. Check the governor before opening the modal; after explicit confirmation record:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "$skillRoot\scripts\linkedin-governor.ps1" `
  -Action RecordEasyApply -JobId '<id>' -Workspace $workspace
```

External ATS/company applications go immediately to one `job-autopilot-external-apply` worker per ready job. There is no skill numeric cap for external ATS work. OAuth/existing session comes before password signup.

## BrowserOS rules

Read `references/browseros-playbook.md` when browser work begins or the first browser action fails. Its rules are operational, not optional:

- always open task-owned tabs; never retry a foreign page ID;
- try `run` at most once per MCP session after a compatibility failure, then use granular tools;
- never probe unavailable raw CDP DOM methods;
- upload only through a fresh ref to an actual file input;
- after `Unable to connect`/CDP loss, stop browser calls for the slice, do local work, persist state, and return for supervisor recovery;
- browser loss is not campaign completion.

One bad site/job never ends the campaign. Use `defer-workitem.ps1` for recoverable technical failures (1m, 5m, then 30m backoff), then continue. CAPTCHA/MFA/security/automation signals use the route/domain circuit breaker with zero bypass and zero security retries.

## Truth and autonomy

Never ask the user to choose, approve, or clarify routine workflow decisions. Choose Recommended, otherwise the first safe benign option. For factual fields use canonical/profile evidence, an honest decline/N/A, or skip the job.

Never fabricate employer history, degree/licence/clearance, work authorization, people management, production metrics, specialist identity, or precise technology-specific duration. Overall software tenure may support a requirement only when the capability itself is supported or reasonably plausible.

Ordinary form validation gets one correction. Confirm explicit success before recording `submitted`. Keep logs compact.

## Fault containment

Schema, script, worker, resume, and browser implementation errors are job/route-local. Correct once when deterministic; otherwise defer and continue. Do not repeatedly reconsider the same branch.

Only the affected route stops for truthful impossibility, CAPTCHA/MFA/security controls, or unavailable BrowserOS. Other domains, local stages, and discovery continue.

## Overnight supervision

A single chat/agent turn cannot keep running after its host process exits. For persistent operation, use the packaged supervisor from the campaign workspace after BrowserOS neo is open and healthy:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "$skillRoot\scripts\start-autopilot.ps1" -Workspace $workspace
```

It keeps Windows awake without keeping the display on, launches bounded fresh OpenCode slices, restarts after normal/error exits, and waits without spending model sessions when MCP port 9010 is up but browser CDP port 9110 is down. State and slice logs live under `.job-apply-autopilot\supervisor`.

Stop it cleanly with:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "$skillRoot\scripts\stop-autopilot.ps1" -Workspace $workspace
```

BrowserOS neo, its signed-in profile, internet access, and the PC must remain available. If BrowserOS itself crashes and does not relaunch, the supervisor waits until the user starts it again; it does not bypass BrowserOS or security controls.

## Worker prompt contract

Worker prompts contain only the exact one-job directory and requested action. Workers do not load this main skill, invoke nested workers, write shared ledgers, or ask questions. They return one terse status line; the coordinator reruns state and continues.
