# V5.5 validation

## Package invariants
- Skill metadata version is 5.5.
- Canonical `.tex` files are unchanged from the prior validated canonical sources.
- Four trusted hidden subagents are packaged.
- External ATS applicator retains BrowserOS + final-submit authority and no skill-imposed concurrency cap.
- LinkedIn Easy Apply remains coordinator-owned.

## Operational-learning checks
- `references/ats-eligibility-adapters.md` exists.
- `references/browseros-playbook.md` exists.
- `references/campaign-analytics.md` exists.
- `scripts/update-campaign-stats.ps1` exists.
- `scripts/init-workspace.ps1` creates the `domain-circuit-breakers/` marker directory and `campaign-stats.json`.
- Queue `job.json` supports `discovery_lane` and `search_query`.
- Promotion carries discovery/source metadata into the generated job.

## Resume artifact checks
- Compile still requires passed hard gates, complete fit map, complete tailoring audit, zero unsupported terms, and canonical SHA-256 match.
- `latexmk` failure falls back to two direct `pdflatex` passes.
- `-AutoCompact` makes at most one controlled layout-only fallback and preserves `resume.precompact.tex`.
- The compile script creates a unique application-facing filename and `resume-artifact.json` with SHA-256.
- Browser/application workers are instructed to verify the exact artifact filename before Submit.

## External application checks
- External worker step budget increased to 120.
- External worker writes/resumes `application-progress.json` checkpoints.
- A `submit-clicked` checkpoint requires success verification before another submit attempt.
- External worker still stops on first spam/automation/429/security signal.

## Eligibility learning checks
- Closed official ATS country lists excluding Pakistan are decisive negative evidence.
- Workable/Ashby adapter failure is not itself negative evidence.
- `Remote`, generic global-company language, or a form accepting Pakistan remains insufficient by itself.

## Campaign analytics checks
- Stats script tolerates legacy ledger entries without discovery-lane metadata.
- Analytics changes search allocation only; it never lowers job gates or forces quota completion.
