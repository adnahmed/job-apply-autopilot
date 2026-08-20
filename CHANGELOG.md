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
