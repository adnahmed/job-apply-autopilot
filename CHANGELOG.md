# V5.7.0 — Current-Directory Workspace Edition

- Makes the coordinator's initial current working directory the single authoritative campaign workspace.
- Removes the `$HOME\job-search` fallback and all orchestration examples that hardcoded that convention.
- Forbids workspace discovery/scanning entirely during continuation.
- Defines runtime root as `<coordinator-cwd>\.job-apply-autopilot`.
- Requires subagents to use the absolute queue/generated job path passed by the coordinator rather than their own CWD.
- Keeps scripts portable: `-Workspace` receives the captured coordinator workspace; scripts already default to `(Get-Location).Path` when invoked directly.

# V5.6 — Fast bootstrap and deterministic continuation

- Replaced eager `Load these files first` behavior with lazy, stage-specific reference loading.
- Added deterministic workspace resolution; coordinator must not scan sibling/home folders to guess campaign state.
- Canonical runtime root is always `<workspace>/.job-apply-autopilot`; generated jobs are never read from `<workspace>/generated`.
- Added `scripts/session-state.ps1` to summarize ledger, queue, generated jobs, unreconciled external results, circuit breakers, and campaign stats in one call.
- `Continue applying` now loads only profile + canonical facts, takes one state snapshot, reconciles completed results, resumes actionable work, then returns to discovery.
- Coordinator is explicitly told not to read the full ledger or recursively enumerate directories merely to reconstruct startup state.

# V5.5 — Operational learning from successful real applications

- Added official ATS eligibility adapter guidance. Workable closed-country lists and Ashby exact-role location data can resolve foreign eligibility before opening forms.
- Added persistent BrowserOS playbook from successful Conquer/BTSE flows: Easy Apply draft recovery, hidden-input resume upload, exact filename verification, covered-button fallbacks, Lever native setter workaround, and known unavailable CDP DOM methods.
- Resume compiler now creates a unique professional application PDF plus `resume-artifact.json` SHA-256 manifest; generic `resume.pdf` is compile-only.
- Added one controlled one-page layout fallback (`resume.precompact.tex`, remove `\vfill`, tighten itemize spacing) and working-pdflatex fallback when latexmk is installed but broken.
- External ATS worker step budget increased to 120 and now checkpoints `application-progress.json`; re-dispatch resumes safely and verifies any prior `submit-clicked` state before another submit.
- Added campaign analytics (`update-campaign-stats.ps1`, `campaign-stats.json`) and discovery-lane/search-query metadata to improve search allocation without changing gates.
- Fixed workspace initialization to actually create the shared `domain-circuit-breakers/` marker directory already referenced by workers.
- Preserved V5.4 architecture: all ready external ATS applications can run concurrently through trusted subagents; LinkedIn Easy Apply remains coordinator-owned.

# V5.4 changes

- Added trusted `job-autopilot-external-apply` subagent with BrowserOS access and final-submit authority for external ATS/company-site jobs.
- Removed the skill-level concurrency cap for external applications: dispatch every ready external job concurrently; OpenCode/runtime resources are the only natural limit.
- LinkedIn Easy Apply remains coordinator-owned.
- External workers write per-job `application-result.json`; coordinator merges results into shared ledgers to avoid concurrent JSONL append races.
- Added reactive shared per-domain circuit-breaker markers checked immediately before final Submit; this is not a pre-emptive per-domain concurrency cap.
- Installer/verifier now includes the fourth external-applicator agent and verifies BrowserOS is allowed only for that worker.
- Updated orchestration and anti-automation policies for parallel external submission.

# V5.3 — Trusted worker write + scoring consistency

- Fixed subagent `write`/`edit` failures caused by relative Windows workspace paths not matching the queue/generated permission globs.
- Assessor, eligibility, and resume workers now have trusted direct `edit: allow`; their one-job ownership boundary is enforced by the agent contract and coordinator, while BrowserOS/nested-task restrictions remain.
- Assessor wording now explicitly loads the currently installed V5.3 rules instead of stale `V5` wording.
- Resolved the mandatory-gap contradiction: one learnable central ADJACENT gap can be tolerated only when it is not role-defining and carries no explicit ownership/years requirement. One role-defining missing depth requirement, or two central gaps, still hard-fails.
- Plutus-style `4+ years data-warehouse/governance ownership` remains a legitimate hard failure when canonical evidence only supports ETL/backend work.
- `verify-subagents.ps1` now checks that trusted worker write permissions were actually installed.
- Coordinator Task prompts are now deliberately minimal/evidence-neutral; unsourced “important context” and copied policy summaries are forbidden, preventing stale-policy anchoring and fabricated employer-location context.

# V5.1

- Fixed Windows `AuthorizationManager check failed` when the coordinator invoked packaged `.ps1` files directly.
- All documented/runtime script calls now use `pwsh -NoProfile -ExecutionPolicy Bypass -File ...`.
- Installation unblocks downloaded/extracted skill files with `Unblock-File`.
- `promote-workitem.ps1` now launches its nested scaffold script through a bypassed child `pwsh` process.
- Resume subagent instructions explicitly require the bypassed `pwsh` compile command.
- Clarified that `-ExecutionPolicy Bypass` is a host option, not a script argument.

# V5 change log — Parallel Pipeline Edition

## Parallel orchestration

- Added three hidden OpenCode subagents: `job-autopilot-assessor`, `job-autopilot-eligibility`, and `job-autopilot-resume`.
- Added bounded concurrency: up to 4 assessment workers, 3 eligibility researchers, and 3 resume workers.
- BrowserOS authentication, form filling, uploads, Submit actions, and global ledgers remain coordinator-only and serialized.
- Added `.job-apply-autopilot/queue/` work items so workers never edit the same job directory.
- Added `new-workitem.ps1` and `promote-workitem.ps1` for deterministic queue → generated transitions.
- Added `install-subagents.ps1` to install the packaged agents into `~/.config/opencode/agents/`.
- Added `references/parallel-orchestration.md`.
- Worker agents cannot invoke other subagents, cannot write global ledgers, and cannot use BrowserOS.
- Resume workers only run after the coordinator has passed every hard gate.
- If Task/custom agents are unavailable, V5 falls back to the same pipeline serially.

## Retained V4 safeguards

- Positive foreign-job eligibility evidence remains mandatory.
- LinkedIn OAuth/import remains preferred over password account creation.
- Password generation/autofill remains allowed as fallback.
- Conservative EXACT/DIRECT/ADJACENT/WEAK/NONE evidence scoring remains enforced.
- Canonical LaTeX resumes remain immutable sources; each accepted job receives a fresh independent resume.
- `tailoring-audit.json`, canonical SHA-256 checks, one-page compilation, ghost/identity gates, relocation policy, and domain circuit breakers remain in force.

## V5.2 — Eligibility calibration fix
- Fixed V5 overcorrection that treated nearly all non-literal Pakistan wording as `UNCLEAR`.
- Added `REGION_INCLUDES_PAKISTAN` for explicit Asia/APAC/APJ regional roles unless employer-specific restrictions conflict.
- A direct employer Pakistan job location is positive evidence; Pakistan search placement alone remains weak.
- Verified Pakistan-headquartered employer or Pakistan employing entity tied to an unrestricted remote role can establish `PAKISTAN_ELIGIBLE`.
- Merely having an unrelated Pakistan office is still not enough for a foreign-country role.
- Direct-employer LinkedIn/Easy Apply postings no longer require a duplicate official ATS/careers listing.
- Assessors are forbidden from inventing headquarters/entity/office facts; such metadata must come from captured source text or verified research.
