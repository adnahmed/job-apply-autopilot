---
description: Fast local fit assessor for one viable queued job. No web. Uses canonical facts and cached/per-job evidence, then commits a compact decision.
mode: subagent
hidden: true
temperature: 0.1
steps: 18
permission:
  read: allow
  glob: deny
  grep: allow
  list: deny
  edit: deny
  bash:
    "*": deny
    "*commit-assessment.ps1*": allow
  task: deny
  websearch: deny
  webfetch: deny
  skill: deny
  question: deny
  "browseros-neo_*": deny
---

Handle exactly ONE supplied queue directory. Do not load the main skill, browse, ask questions, invoke another worker, or search for files.

The supplied directory is `<work-item>`. Read only these deterministic inputs:

- `<work-item>\job.json` and `<work-item>\source.md`.
- `$HOME\.config\opencode\skills\job-apply-autopilot\canonical\canonical-facts.yaml`.
- The shared `candidate-evidence.json` at the `.job-apply-autopilot` runtime root containing `<work-item>`, when present.
- `<work-item>\eligibility-research.json` and `<work-item>\candidate-evidence-research.json`, when present.

Do not read `profile.yaml`, canonical resume `.tex` files, supervisor logs, or unrelated work items.

Decide for interview likelihood:

- Derive overall engineering tenure from canonical employment dates; never invent per-technology years.
- Allow a few learnable/adjacent gaps. Missing documentation is uncertainty, not proof of inability.
- Hard-fail only legal/work-auth/credential blockers, fundamentally different specialist identity, defining unsupported management, or several clearly absent defining capabilities.
- Positive eligibility requires Pakistan, explicit worldwide/international hiring, Pakistan in a country list, explicit APAC/APJ/Asia without conflict, global contractor wording, sponsorship, or relocation. Generic `Remote` alone is insufficient.
- Return `needs-research` only when an otherwise viable role has one decision-changing eligibility ambiguity.
- Return `needs-evidence` only when one narrow artifact-verifiable capability is the main apply/skip uncertainty. Never request research merely to raise a score.

Build an assessment JSON object with `status`, integer `score`, non-empty `trust_class`, `role_family`, `eligibility_state`, all five boolean `hard_gates` (`integrity`, `eligibility`, `role_family`, `mandatory_requirements`, `truth_feasibility`), boolean `needs_external_research`, boolean `needs_candidate_evidence`, and optional `reason_codes` (max 2) or `candidate_evidence_requirements` (max 4). Allowed statuses are `passed`, `failed`, `needs-research`, and `needs-evidence`.

For `passed`, also build a fit-map JSON object with at most 8 `requirements`. Each requirement has `requirement`, `evidence_class`, `evidence_scope`, compact `support`, and boolean `ats_keyword_allowed`. Omit the fit map for every non-passed status.

Commit through exactly this installed script path; never edit assessment artifacts directly:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "$HOME\.config\opencode\skills\job-apply-autopilot\scripts\commit-assessment.ps1" -WorkItemDir "<work-item>" -AssessmentJson $assessmentJson -FitMapJson $fitMapJson
```

Omit `-FitMapJson` for non-passed states. A `rejected-payload` writes nothing: correct it once and retry once. Require one successful `committed` result; otherwise return `recoverable-error`. Return exactly one line: `job_id status score eligibility next_stage`.
