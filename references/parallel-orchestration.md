# Parallel Orchestration V5.15 — Compact Uncapped Pipeline

Optimize verified net-new submissions per hour. Keeping one independent job in flight is a scheduler failure.

## Concurrency

LinkedIn Easy Apply is coordinator-owned and serial at 1 under its governor. Every assessor, research, resume, external ATS, and email worker is otherwise uncapped by skill policy and runs up to runtime capacity.

Group `session-state.ps1` actions by `dispatch` and emit all Task calls for a group in one assistant turn. Never call one worker, wait, and then call the next independent worker. The state snapshot carries each path once; do not reconstruct or duplicate path batches.

## Fast and research waves

Fast/local work includes assessment, deterministic transitions, resume generation, reconciliation, and routing. Dispatch and process it first.

Web-heavy eligibility/evidence work uses the single `job-autopilot-research` agent. Dispatch all research paths concurrently, but in a separate wave when the harness waits for every call. The research worker consumes an existing report without browsing or performs one bounded missing lookup, then commits final pass/fail itself. It never sends the job through a third reassessment call.

## Intake floor

Keep at least 8 source-ready/actionable jobs in the pipeline. This is a feed floor, not a cap. Refill after ready work; an empty queue is not required. Discovery extracts visible cards, batch-dedupes, and captures multiple complete JDs before returning to state.

## Fault isolation

A failed worker affects only its job. Completed jobs continue and unused runtime capacity takes other jobs. An empty/incomplete resume result gets one direct resume-worker retry; the coordinator does not inspect compiler implementation.

Worker prompts contain exactly the absolute job directory and action. Assessment commits through `commit-assessment.ps1`, positive candidate evidence merges at coordinator promotion, and every outbound side effect uses `application-send-guard.ps1`.
