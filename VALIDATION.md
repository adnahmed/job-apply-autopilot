# V5.11 Validation

Package checks:
- `VERSION.txt` = `5.11.0`.
- main skill metadata version = `5.11`.
- canonical `.tex` files must remain byte-identical to V5.10.
- five packaged hidden subagents remain installed/trusted; only external applicator has BrowserOS.
- assessor/evidence/eligibility/resume/external workers deny `skill` loading to avoid repeated main-skill context.
- `session-state.ps1` has no automatic old-policy technical-skip reopening and does not emit full campaign stats/action_paths.
- `log-decision.ps1` exists for compact obvious-skip logging.
- evidence worker policy contains max 5 repos / max 2 deployments / no full inventory.
- `compact-candidate-evidence.ps1` exists and `init-workspace.ps1` invokes it.
- external ATS remains uncapped; LinkedIn governor remains separate.

Runtime PowerShell should be verified on Windows after install because this build environment may not include `pwsh`.
