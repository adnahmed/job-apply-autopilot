# V5.14.2 Validation

- `VERSION.txt` = `5.14.2`.
- Main skill heading/package version = `5.14.2`.
- The pinned goal plugin registers globally and supervised slices activate one continuous coordinator goal when the user requested persistence.
- Goal completion is forbidden for submission counts, temporary queue exhaustion, blocked routes, or slice boundaries; ordinary messages steer the loop, while `/goal pause` and `/goal stop` are explicit controls.
- Every continuation reruns authoritative campaign state; goal control flow cannot authorize a duplicate Send/Submit or worker-created goal.
- Canonical `.tex` files are unchanged from V5.11.
- All packaged subagents keep `question: deny`.
- Assessor direct `edit` is denied; only `commit-assessment.ps1` is allowed for assessment artifact writes.
- `commit-assessment.ps1` validates canonical status/score/hard-gate/fit-map shape and writes atomically.
- `session-state.ps1` detects malformed or contradictory passed assessment artifacts and routes them to `assessment_repair`.
- Queue copies are non-actionable after promotion, and only an explicit `allow_after_prior_skip` flag may reopen a technical skip.
- `repair-workitem.ps1` backs up malformed artifacts and resets safely to pending rather than inferring truth/gates.
- `advance-workitem.ps1` is the coordinator promotion boundary; it catches promotion exceptions as recoverable job-local results.
- `defer-workitem.ps1` applies bounded retry backoff, and `session-state.ps1` excludes deferred queue/generated items so they cannot stall discovery or other applications.
- `promote-workitem.ps1` accepts either `-WorkItemDir` or `-JobId`, eliminating the V5.11.4 binder mistake.
- Recoverable schema/script/browser/resume/worker errors are explicitly non-terminal for the campaign.
- A standalone CAPTCHA preserves its tab and gets exactly one installed-solver trigger plus a targeted wait of up to 120 seconds; CAPTCHA presence alone is not an immediate domain circuit.
- Failed/repeated CAPTCHA recovery, MFA, and security/automation controls remain zero-Submit-retry and route-local; unaffected jobs continue.
- `domain-circuit-breaker.ps1` repairs legacy concatenated JSONL, writes atomic markers, and `session-state.ps1` suppresses active domains including subdomains.
- `application-send-guard.ps1` prevents missing/ambiguous receipts and parallel same-company/title job IDs from authorizing a second Send/Submit.
- `reconcile-application-result.ps1` appends one ledger row per terminal job result and returns `already-reconciled` on repeats.
- Direct email applications use the dedicated idempotent email subagent and verify Gmail Sent before any retry.
- Persistent discovery, bounded evidence lookup, external ATS uncapped behavior, and LinkedIn governor remain intact.
- Missing/placeholder JDs route to `source_pending`, never `assessment_pending`.
- Recent same-company/same-title reposts are semantically deduped even when the job ID changes.
- `submitted_unique` is the headline and `submitted_rows` remains audit detail.
- The LinkedIn governor merges ledger truth, parses JSON `DateTime` values safely, serializes writers, and replaces state atomically.
- The BrowserOS playbook includes current session ownership, one-strike fallback, connection-loss, and upload behavior.
- BrowserOS health uses IPv4 loopback by default so Windows `localhost`/IPv6 resolution cannot falsely report both ports down.
- Supervisor validation resolves OpenCode without launching it; `get-autopilot-status.ps1` distinguishes running, stopped, stale, and stop-requested state.
- Per-slice launch/logging failures enter `slice-error-recovering` and do not terminate the persistent supervisor.
- Installation backups are stored under `~/.config/opencode/skill-backups`, outside skill discovery.

## Regression self-test

Run:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\selftest-resilience.ps1
```

The test verifies source gating, deterministic repair/commit/promotion, semantic dedupe, idempotent outbound reservations, ambiguity grace, legacy circuit repair, active-domain routing, unique metrics, and governor recovery.

Validate the supervisor without launching an agent:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-campaign.ps1 -Workspace <campaign-workspace> -ValidateOnly
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-browseros-health.ps1
```
