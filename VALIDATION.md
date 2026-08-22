# V6.4.0 Release Contract

This document describes the required implementation state. It does not invoke a test suite.

- `VERSION.txt` and the main skill heading are `6.4.0`.
- Every FreeHire request uses the zero-credit allowlisted client; unknown and credit-consuming endpoints are blocked before network access, and credentials never enter logs or repository files.
- Authenticated FreeHire enrichment is cached and fail-open; deterministic match evidence prioritizes work but never passes or rejects a job.
- Cross-source resolution accepts only public HTTP(S) vacancy URLs after local dedupe; private/authenticated/local-network URLs are never sent.
- Candidate autofill and screening data use local-canonical-first precedence, while application tracking mirrors only after local reconciliation.
- Exact linked FreeHire mail may prove an ambiguous submission only through the caller-bound send-guard proof kind; suggested, unlinked, stale, or pre-reservation messages cannot.
- FreeHire composite discovery, ignored-parameter checks, evidence-only reality signals, local salary insights, explicit route sidecars, deterministic answer resolution, quality rejection, and fast/research wave state are present.
- Persistence is owned only by `opencode-goal-plugin@0.8.1`, with `noContinueWhileChildrenActive: true` and durable state enabled.
- Every goal continuation reruns `session-state.ps1` and the cached fail-open `sync-freehire-context.ps1`; a mail proof causes one state refresh, while restart recovery remains paused until `/goal resume`.
- No packaged command launches, monitors, stops, health-gates, or keeps awake an OS background coordinator.
- Queue/generated/discovery stages use expiring claims; matching transitions clear claims and expired claims do not suppress work.
- Assessment commits require expected prior state and serialize under the work-item lock.
- Assessment validation returns all schema errors together and enforces the 72 / narrow 68-71 score policy again at promotion.
- Workers obtain exact artifact and runtime evidence locations from the deterministic work-item manifest rather than path probing.
- Work-item creation has structured created/existing/duplicate/rejected results; only created jobs may receive new source metadata.
- Required answer resolution uses configured facts first and otherwise exposes every unknown category for one context-aware agent-generated answer; it never emits a new protected-fact blocker.
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
- Session state emits a FreeHire command and an exact `job-autopilot-linkedin-discovery` campaign-worker prompt under one coordinator-owned claim; both carry the full independent source target, and FreeHire completion cannot suppress LinkedIn startup.
- Every worker has broad PowerShell access for work-item-local reads and installed scripts, acquires its stage before acting, and returns one canonical status line.
- Browser workers use granular tools without free-form `run`; connection loss ends browser calls for that worker.
- When BrowserOS is unavailable, local work continues; if no useful local work remains, the active goal blocks with the concrete BrowserOS reason until restoration and `/goal resume`.
- Package verification must use temporary campaign workspaces and must never send an application or email.

## Retained pipeline invariants

- The coordinator workspace is captured once; runtime remains `<workspace>\.job-apply-autopilot`, with no sibling/home workspace discovery.
- `session-state.ps1` preserves the established `next_action` compatibility enum while exposing every runnable action once; four-line identity prompts resolve long work-item paths through the manifest instead of copying them.
- Scheduler concurrency exposes `default: unbounded` and `linkedin_easy_apply: 1`; it has no non-LinkedIn skill caps or duplicate dispatch batches.
- The assessor remains local/web-free and can request only one bounded research kind; the research finalizer commits the decision without a third reassessment worker.
- Passed fit maps contain at most eight central requirements. Positive eligibility for the candidate's documented home jurisdiction remains mandatory before submission.
- Canonical `.tex` files remain immutable; generated scaffolds record their canonical SHA-256, compilation checks it, and upload uses only the unique manifest PDF.
- All packaged subagents keep `question: deny` and `task: deny`. Non-browser workers deny BrowserOS; applicators and the dedicated LinkedIn discovery worker alone receive browser permission.
- A placeholder or missing JD routes to `source_pending`. Promoted queue copies are shadowed by their generated work item.
- `repair-workitem.ps1` backs up malformed artifacts and resets them without inventing truth or hard-gate values.
- `advance-workitem.ps1` remains the coordinator promotion boundary and converts promotion exceptions into recoverable job-local state.
- Recoverable failures retain bounded 1m/5m/30m cooldowns and do not hide unrelated application, queue, or discovery work.
- Domain circuit state remains serialized, supports subdomains, repairs legacy concatenated JSONL, and suppresses only affected routes until clearance/expiry.
- `application-send-guard.ps1` remains the only outbound reservation/receipt boundary and prevents parallel semantic company/title attempts.
- `reconcile-application-result.ps1` remains the only result-to-ledger application boundary and is idempotent on repeated calls.
- The LinkedIn governor reconstructs ledger history, parses timestamps invariantly, serializes writers, and avoids duplicate job-ID records.
- Discovery is always emitted as an independent fast-wave action, semantic-dedupes before work-item creation, rotates lanes after dry results, and never waits for downstream work or queue depletion.
- Candidate evidence remains bounded to decision-changing first-party sources; missing evidence is not proof of inability.
- Browser automation retains task-owned tabs, fresh upload-input references, exact filename verification, granular actions, and immediate stop after connection loss.
- Truth boundaries still prohibit invented identity, employment, education, authorization, management, metrics, and technology-specific duration.
- No coordinator may declare completion or a natural pause while unclaimed actions or needed discovery remain.

## Release review boundaries

Release review is static and non-sending. Any future executable verification must use a newly created temporary campaign workspace and must not authenticate, submit, send email, or mutate an existing campaign.

## Throughput self-test

Required validation step (run from the repository root):

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\self-test-throughput.ps1
```

This synthetic-workspace self-test exercises the assessment schema, work-item creation (with and without `MetadataJson` / `Description`), atomic discovered-job persistence through `finalize-discovered-workitem.ps1`, session-state dispatch accounting (LinkedIn bounded batch ≤ 3 vs. full FreeHire `discoverySlots`), idempotent duplicate creation, and all other throughput invariants listed above. It exits non-zero on any failure.
