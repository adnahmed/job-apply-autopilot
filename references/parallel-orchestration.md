# Parallel Orchestration V5.7

## Goal
Use OpenCode subagents as trusted job workers. Parallelize all independent work, including end-to-end external ATS applications. Keep LinkedIn Easy Apply under the primary coordinator because Easy Apply shares one LinkedIn surface/session and benefits from centralized dedupe/resume-selection control.

## Workers

### job-autopilot-assessor
One queued job per child session. Reads captured source data and canonical facts; writes assessment + fit map.

### job-autopilot-eligibility
One unclear job per child session. Researches official eligibility/relocation evidence; writes eligibility-research.json.

### job-autopilot-resume
One approved job per child session. Tailors and compiles the fresh canonical LaTeX resume in that job's unique generated folder.

### job-autopilot-external-apply
One approved external-ATS job per child session. Owns its BrowserOS tabs and completes the external application end to end, including OAuth/login, form filling, unique resume-artifact upload, screening questions, final Submit, and confirmation. Writes `application-progress.json` checkpoints and `application-result.json` in its job folder.

## Coordinator-owned operations
The primary agent owns:
- discovery and dedupe,
- queue creation and source capture,
- final gate adjudication,
- promotion to generated folders,
- LinkedIn Easy Apply submissions,
- dispatch of external ATS applicators,
- reconciliation of per-job `application-result.json` files into global ledgers,
- global reporting.

The coordinator is NOT the bottleneck for external ATS applications.

## Concurrency policy
There is **no skill-imposed numeric concurrency limit for external ATS applications**.

When multiple approved external jobs have valid tailored resumes, dispatch one `job-autopilot-external-apply` task for **every ready job** without waiting for earlier external tasks to finish. Actual concurrency is limited only by OpenCode/runtime/system resources.

Assessment, eligibility, and resume stages may also be fanned out aggressively across independent jobs. Avoid assigning two workers to the same job directory at the same time.

LinkedIn Easy Apply remains coordinator-owned and may be processed sequentially while external ATS subagents run concurrently in the background/task pool.

## Domain circuit breakers under parallel load
Unlimited fan-out does not waive anti-automation rules.

- Every external worker owns its job and must stop on its first spam/automation/429/security signal.
- Before final Submit, each external worker checks `.job-apply-autopilot/domain-circuit-breakers/` for an existing marker for its ATS domain.
- A worker that encounters a domain-wide resistance signal should best-effort create the domain marker immediately.
- Concurrent workers already active on the same domain should check again immediately before their own Submit and stop if the marker is present.
- Do not serialize all jobs merely because they share an ATS domain; the circuit breaker is reactive, not a pre-emptive per-domain concurrency cap.

## Batch pipeline
1. Coordinator harvests credible jobs and creates one queue directory per job.
2. Fan out assessors across all complete work items.
3. Fan out eligibility researchers for all `UNCLEAR` jobs that remain otherwise viable.
4. Re-assess researched jobs and perform coordinator final adjudication.
5. Promote every accepted work item.
6. Fan out resume workers across all promoted jobs.
7. As soon as a resume is ready:
   - LinkedIn Easy Apply -> coordinator queue.
   - External ATS/company site -> immediately dispatch `job-autopilot-external-apply`.
8. External applicators run concurrently with each other and with ongoing assessment/resume preparation.
9. Coordinator periodically reads completed `application-result.json` files and safely merges them into `applications.jsonl`, then refreshes `campaign-stats.json`.
10. Continue discovering/preparing while external application tasks are in flight.

## Task-prompt hygiene
Pass one directory path, not a pre-baked verdict. Example external applicator Task prompt:

```text
Handle exactly one approved external job-apply-autopilot generated directory: <path>.
Load the currently installed job-apply-autopilot skill and follow its current policies.
Own this external ATS application end to end and write application-result.json in the supplied directory.
Do not handle LinkedIn Easy Apply; hand it back if the route resolves to Easy Apply.
Do not touch any other job.
```

Do not inject headquarters claims, eligibility conclusions, fit conclusions, passwords, or stale policy summaries into child prompts. Persist sourced evidence in the job files instead.

## File ownership
Never run two workers on the same job directory concurrently.

Safe independent job paths:
- `.job-apply-autopilot/queue/<job-a>/`
- `.job-apply-autopilot/queue/<job-b>/`
- `.job-apply-autopilot/generated/<job-a>/`
- `.job-apply-autopilot/generated/<job-b>/`

External applicators write only their assigned `application-result.json` plus the shared per-domain circuit-breaker marker when necessary. They do not append shared JSONL ledgers.

## Fallback
If custom Task/subagents are unavailable, perform the same logic serially. Correctness rules do not change.
