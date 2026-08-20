# V5.9 validation

## Architecture invariants
- External ATS/company-site applications have no numeric per-run, per-day, or concurrency cap.
- LinkedIn Easy Apply remains coordinator-owned and is the only application route governed by the numeric LinkedIn activity governor.
- A LinkedIn governor cooldown does not block external ATS workers.
- External workers still obey truth/eligibility gates and reactive ATS/domain circuit breakers.

## Continuation invariants
- Coordinator CWD is the authoritative workspace.
- `session-state.ps1` remains the one startup snapshot.
- Snapshot returns `next_action`, `action_paths`, and stage-aware `actions`.
- Queue `pending` stubs map to `assessment_pending`.
- `needs-research` without evidence maps to `eligibility_research_pending`; with evidence maps to `reassessment_pending`.
- Generated jobs without `resume-artifact.json` map to `resume_pending` instead of disappearing from actionable state.
- Existing terminal/ledgered jobs are not actionable.

## LinkedIn governor invariants
- State file: `.job-apply-autopilot/linkedin-activity-state.json`.
- Defaults: 4 confirmed Easy Apply submissions / rolling hour, 20 / rolling 24h, 600 seconds minimum spacing.
- Counts persist across coordinator restarts.
- Record only confirmed Easy Apply submissions, not merely opened/filled forms.
- Ordinary LinkedIn rate-limit/security warning => 24h LinkedIn cooldown.
- CAPTCHA/MFA/account restriction => manual LinkedIn block.
- Governor output always reports `external_applications_restricted: false`.

## Discovery/dedupe invariants
- `dedupe-jobs.ps1` accepts a comma-separated batch of newly discovered job IDs.
- It checks ledger + queue + generated and returns seen/unseen results without coordinator directory archaeology.

## Resume / worker invariants
- Canonical `.tex` files remain immutable.
- External worker retains BrowserOS + final-submit authority and step budget 120.
- Resume artifact filename/hash and application-progress checkpoint behavior remain unchanged from V5.8.

## Environment note
The build container does not provide PowerShell, so packaged `.ps1` files receive static validation here and should also be exercised on the Windows/OpenCode host with the documented `pwsh -NoProfile -ExecutionPolicy Bypass -File ...` commands.
