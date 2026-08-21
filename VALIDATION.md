# V5.13.0 Validation

- `VERSION.txt` = `5.13.0`.
- Main skill metadata version = `5.13.0`.
- Canonical `.tex` files are unchanged from V5.11.
- All packaged subagents keep `question: deny`.
- Assessor direct `edit` is denied; only `commit-assessment.ps1` is allowed for assessment artifact writes.
- `commit-assessment.ps1` validates canonical status/score/hard-gate/fit-map shape and writes atomically.
- `session-state.ps1` detects malformed or contradictory passed assessment artifacts and routes them to `assessment_repair`.
- `repair-workitem.ps1` backs up malformed artifacts and resets safely to pending rather than inferring truth/gates.
- `advance-workitem.ps1` is the coordinator promotion boundary; it catches promotion exceptions as recoverable job-local results.
- `defer-workitem.ps1` applies bounded retry backoff, and `session-state.ps1` excludes deferred queue/generated items so they cannot stall discovery or other applications.
- `promote-workitem.ps1` accepts either `-WorkItemDir` or `-JobId`, eliminating the V5.11.4 binder mistake.
- Recoverable schema/script/browser/resume/worker errors are explicitly non-terminal for the campaign.
- CAPTCHA/MFA/security/automation controls remain zero-bypass and route-local; unaffected jobs continue.
- Persistent discovery, bounded evidence lookup, external ATS uncapped behavior, and LinkedIn governor remain intact.
- Missing/placeholder JDs route to `source_pending`, never `assessment_pending`.
- Recent same-company/same-title reposts are semantically deduped even when the job ID changes.
- `submitted_unique` is the headline and `submitted_rows` remains audit detail.
- The LinkedIn governor merges ledger truth, parses JSON `DateTime` values safely, serializes writers, and replaces state atomically.
- The BrowserOS playbook includes current session ownership, one-strike fallback, connection-loss, and upload behavior.
- Supervisor validation resolves OpenCode without launching it; when BrowserOS is unhealthy it enters `waiting-browseros` without starting a model session.

## Regression self-test

Run:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\selftest-resilience.ps1
```

The test verifies source gating, reproduces the V5.11.4 malformed `assessment.json` pattern, validates repair/commit/promotion, catches a new-ID semantic duplicate, checks unique metrics, and proves governor ledger recovery plus duplicate-JobId protection.

Validate the supervisor without launching an agent:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\run-campaign.ps1 -Workspace <campaign-workspace> -ValidateOnly
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-browseros-health.ps1
```
