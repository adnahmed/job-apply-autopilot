# Parallel Orchestration V5.13 — Latency-Aware + Fault-Isolated

Parallelism is useful only when it does not delay the first useful result.

## Fast lane

Fast/local operations:
- assessor without web
- coordinator adjudication
- promotion
- resume worker
- application routing

Act on each completed fast result immediately.

## Slow lane

Potentially slow/web-heavy:
- eligibility research
- candidate public-evidence research
- relocation research

Never put slow-lane tasks in the same waiting wave as a ready/likely fast-lane job when the harness waits for all calls in the turn.

Preferred order:
1. process ready generated applications;
2. process passed/assessment-pending jobs likely to yield an application;
3. route/promote/resume those results;
4. then run slow research for ambiguous jobs;
5. discovery continues whenever no ready fast work exists.

External ATS workers are uncapped by skill policy. LinkedIn Easy Apply remains coordinator-owned.

Workers get exactly one absolute job directory. Do not paste long policy summaries into Task prompts. Packaged agent instructions are authoritative.


## Fault isolation

A failed worker or deterministic transition is never a reason to wait or end the batch. Keep the failed job recoverable, route completed jobs immediately, then continue discovery/other applications. Coordinator assessment writes are forbidden; assessor state is committed through `commit-assessment.ps1`, and queue-to-generated transitions go through `advance-workitem.ps1`.
