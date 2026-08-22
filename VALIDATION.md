# V6.1.1 Release Contract

This document describes the required implementation state. It does not invoke a test suite.

- `VERSION.txt` and the main skill heading are `6.1.1`.
- FreeHire composite discovery, ignored-parameter checks, evidence-only reality signals, local salary insights, explicit route sidecars, deterministic answer resolution, quality rejection, and fast/research wave state are present.
- Persistence is owned only by `opencode-goal-plugin@0.8.1`, with `noContinueWhileChildrenActive: true` and durable state enabled.
- Every goal continuation reruns `session-state.ps1`; restart recovery remains paused until `/goal resume`.
- No packaged command launches, monitors, stops, health-gates, or keeps awake an OS background coordinator.
- Queue/generated/discovery stages use expiring claims; matching transitions clear claims and expired claims do not suppress work.
- Assessment commits require expected prior state and serialize under the work-item lock.
- Promotion and resume compilation reuse valid existing outputs under work-item locks.
- Applicators write terminal blockers through `write-application-outcome.ps1`.
- Terminal progress without `application-result.json` exposes `application_outcome_repair`, never `application_resume`.
- `log-decision.ps1` accepts only enumerated discovery/assessment skip statuses, serializes writes, and rejects promoted application work.
- External ATS absence requires `authenticated-ats-tracker-absence`; email absence requires `exact-sent-search-absence`; user confirmation is accepted only through the resolution command.
- Public job pages, history, missing files, and missing confirmation email cannot clear a reservation.
- Unavailable authoritative verification becomes `application_verification_quarantined`, creates no ledger row, consumes no discovery slot, and does not block unrelated work.
- `resolve-application-quarantine.ps1` exposes `List`, `Reverify`, `ConfirmSubmitted`, `ConfirmAbsent`, `RetryApplication`, and `Abandon`.
- Retry refuses any submitted exact or semantic duplicate and accepts only proven pre-submit/cancelled or verified-absent state.
- Session state reports quarantine count, outcome-repair count, per-item claim metadata, and discovery claim metadata.
- Every worker uses exact installed script/reference paths, acquires its stage before reading, does not probe denied shell commands, and returns one canonical status line.
- Browser workers use `run` at most once after failure, then granular tools; connection loss ends browser calls for that worker.
- When BrowserOS is unavailable, local work continues; if no useful local work remains, the active goal blocks with the concrete BrowserOS reason until restoration and `/goal resume`.
- Package verification must use temporary campaign workspaces and must never send an application or email.

## Retained pipeline invariants

- The coordinator workspace is captured once; runtime remains `<workspace>\.job-apply-autopilot`, with no sibling/home workspace discovery.
- `session-state.ps1` preserves the established `next_action` compatibility enum while exposing all runnable cross-stage actions once, each with one dispatch target and an exact two-line `worker_prompt`.
- Scheduler concurrency exposes `default: unbounded` and `linkedin_easy_apply: 1`; it has no non-LinkedIn skill caps or duplicate dispatch batches.
- The assessor remains local/web-free and can request only one bounded research kind; the research finalizer commits the decision without a third reassessment worker.
- Passed fit maps contain at most eight central requirements. Positive eligibility for the candidate's documented home jurisdiction remains mandatory before submission.
- Canonical `.tex` files remain immutable; generated scaffolds record their canonical SHA-256, compilation checks it, and upload uses only the unique manifest PDF.
- All packaged subagents keep `question: deny` and `task: deny`. Non-browser workers deny BrowserOS; applicators alone receive browser permission.
- A placeholder or missing JD routes to `source_pending`. Promoted queue copies are shadowed by their generated work item.
- `repair-workitem.ps1` backs up malformed artifacts and resets them without inventing truth or hard-gate values.
- `advance-workitem.ps1` remains the coordinator promotion boundary and converts promotion exceptions into recoverable job-local state.
- Recoverable failures retain bounded 1m/5m/30m cooldowns and do not hide unrelated application, queue, or discovery work.
- Domain circuit state remains serialized, supports subdomains, repairs legacy concatenated JSONL, and suppresses only affected routes until clearance/expiry.
- `application-send-guard.ps1` remains the only outbound reservation/receipt boundary and prevents parallel semantic company/title attempts.
- `reconcile-application-result.ps1` remains the only result-to-ledger application boundary and is idempotent on repeated calls.
- The LinkedIn governor reconstructs ledger history, parses timestamps invariantly, serializes writers, and avoids duplicate job-ID records.
- Discovery still batch-dedupes visible identities before detail-page work, rotates lanes after dry results, and does not stop after the first plausible job.
- Candidate evidence remains bounded to decision-changing first-party sources; missing evidence is not proof of inability.
- Browser automation retains task-owned tabs, fresh upload-input references, exact filename verification, one-strike `run` fallback, and immediate stop after connection loss.
- Truth boundaries still prohibit invented identity, employment, education, authorization, management, metrics, and technology-specific duration.
- No coordinator may declare completion or a natural pause while unclaimed actions or needed discovery remain.

## Release review boundaries

Release review is static and non-sending. Any future executable verification must use a newly created temporary campaign workspace and must not authenticate, submit, send email, or mutate an existing campaign.
