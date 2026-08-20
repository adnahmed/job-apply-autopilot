# Parallel Orchestration V5

## Goal
Use OpenCode subagents for independent analysis and file-generation work while keeping browser-side irreversible actions under one coordinator.

## Why this split
Parallelism is useful for CPU/context-heavy work but browser automation creates shared-session risk: rate limits, tab ownership confusion, duplicate applications, and anti-spam signals. Therefore V5 uses a bounded pipeline rather than unrestricted browser swarming.

## Workers

### job-autopilot-assessor
One job per child session. Reads captured source data and canonical facts; writes assessment + fit map. No browser, no shell, no application.

### job-autopilot-eligibility
One unclear job per child session. Uses web search/fetch to find official eligibility/relocation evidence; writes eligibility-research.json. No BrowserOS and no form interaction.

### job-autopilot-resume
One approved job per child session. Tailors and compiles the fresh canonical LaTeX resume in that job's unique generated folder. No browser or application tools.

## Coordinator-only operations
The primary agent is the single writer for:
- BrowserOS form interaction,
- ATS authentication/OAuth,
- file upload,
- Submit clicks,
- CAPTCHA/MFA/security decisions,
- global application/watchlist/circuit-breaker ledgers,
- final gate adjudication.

Subagents never write global ledgers.

## Bounded concurrency defaults
- discovery/browser harvesting: 1 coordinator only,
- assessor workers: up to 4 concurrent jobs,
- eligibility workers: up to 3 concurrent jobs,
- resume workers: up to 3 concurrent jobs,
- active ATS submission: exactly 1 at a time.

If a domain circuit breaker trips, do not launch new work for that domain during the run.

## Batch pipeline
1. Coordinator harvests 4-8 credible candidates and saves each as a queue work item.
2. Launch assessor tasks for independent work items together.
3. Read worker outputs; immediately discard hard failures.
4. For `UNCLEAR` eligibility only, launch eligibility workers together.
5. Re-run the assessor once for researched work items so the fit/gate files incorporate the new evidence.
6. Coordinator performs final eligibility adjudication.
7. Promote accepted work items to generated job folders.
8. Launch resume workers together, one folder each.
9. As resumes finish, coordinator applies sequentially, checking OAuth/redirect identity/eligibility again.
10. While one ATS application is being completed, another child worker may assess or prepare a different job, but no child may submit.

## File ownership
Each worker receives exactly one directory path. Never let two workers edit the same job folder.

Safe parallel paths:
- `.job-apply-autopilot/queue/<job-a>/`
- `.job-apply-autopilot/queue/<job-b>/`
- `.job-apply-autopilot/generated/<job-a>/`
- `.job-apply-autopilot/generated/<job-b>/`

Unsafe shared writes:
- `applications.jsonl`
- `relocation-watchlist.jsonl`
- `domain-circuit-breakers.jsonl`

Only the coordinator writes those.

## Failure isolation
A worker failure applies to that work item only. Do not stop other workers unless the failure is a shared-domain automation/security signal reported by the coordinator.

## Fallback
If the Task tool or custom subagents are unavailable, run the exact same pipeline serially. Correctness rules do not change.
