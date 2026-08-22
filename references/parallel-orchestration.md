# Parallel Orchestration V6.4 — Continuous Producer Pipeline

Optimize verified net-new submissions per hour. Keeping one independent job in flight is a scheduler failure.

## Concurrency

LinkedIn Easy Apply is coordinator-owned and serial at 1 under its governor. Continuous discovery and every assessor, research, resume, external ATS, and email worker are otherwise uncapped by skill policy and run up to runtime capacity.

Group compact `session-state.ps1` actions by `dispatch` and emit all Task calls for a group in one assistant turn. Never call one worker, wait, and then call the next independent worker. The state snapshot carries each path once; do not reconstruct or duplicate path batches. Every worker and coordinator-local action must acquire its stage claim before reading or acting; a losing owner exits immediately. Worker leases are stage-sized (20 minutes assessor, 30 research/resume, 45 applicator), not a shared 90-minute stall window.

## Unified runnable wave

Trust `scheduler.active_wave: all`. The state exposes every action once, ordered by priority; dispatch discovery, local work, applicators, and bounded research together. Slow browser/research work must never hold up assessment, resume, routing, reconciliation, applications, or the next discovery producer. The research worker consumes existing evidence or performs one bounded lookup and commits final pass/fail itself; it never sends the job through a third reassessment call.

## Continuous intake

Launch the claimed eight-item discovery batch in the same turn as every downstream fast wave, regardless of current pipeline depth. Never wait for assessment, resume, or application work to finish before discovery. When the discovery claim clears, the next continuation launches another batch. Discovery extracts visible cards, semantic-dedupes, and captures multiple complete JDs before returning to state.

## Fault isolation

A failed worker affects only its job. Completed jobs continue and unused runtime capacity takes other jobs. An empty/incomplete resume result gets one direct resume-worker retry; the coordinator does not inspect compiler implementation.

Worker prompts contain workspace, job ID, kind, and action. Workers resolve the authoritative directory through `get-workitem-manifest.ps1`, avoiding long-path truncation. Assessment commits through `commit-assessment.ps1` with expected prior state, positive candidate evidence merges at coordinator promotion, and every outbound side effect uses `application-send-guard.ps1`. Verification quarantine does not suppress discovery.
