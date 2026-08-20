# Interview-Likelihood Evidence and Scoring Calibration V5.10

## Goal

Maximize credible interview opportunities without turning missing documentation into a rejection. A resume/public profile is incomplete by nature. Prefer evidence refresh and calibrated score penalties over hard skips when a candidate could plausibly do the job.

## Evidence classes

### EXACT
Observed evidence demonstrates the same technology/responsibility/capability requested by the JD. Evidence may be professional or a substantial verified first-party project when the requirement is project-verifiable.

### DIRECT
Concrete evidence demonstrates substantially the same capability even if wording/context differs.

### ADJACENT
Related and transferable capability. This is a real stretch, not zero evidence.

### WEAK
Loose overlap or insufficiently verified evidence. Give little credit, but do not automatically hard-fail unless it defines the role identity.

### NONE
After any required public-evidence refresh, no supported evidence was found.

## Evidence-source scope

Fit strength and provenance are separate. Follow `candidate-evidence-policy.md`.

- `professional`: canonical employment evidence.
- `verified_project`: substantial first-party source/config/deployment evidence.
- `corroborated_public`: candidate-authored public context corroborated by artifacts.
- `public_self_attested`: exact candidate-authored public context without artifact corroboration.
- `mixed`: more than one scope.

Verified project evidence is valid evidence of technology/project capability. It does not by itself establish employer association, production scale, paying customers, people leadership, clearance, or work authorization.

Before assigning a technical `WEAK`/`NONE` that would cause rejection, apply the public-evidence freshness guard. If the capability has not been checked and live evidence could settle it, return `needs-evidence` first.

## Experience-band model

Derive overall professional software-engineering tenure from canonical employment dates/facts at assessment time. Never hardcode the candidate's total years in this scoring policy.

Do **not** score or gate technology-by-technology years. A JD requirement such as `3+ years React` is evaluated as:

- overall engineering tenure satisfies the requested band, plus
- React capability is supported (`EXACT`/`DIRECT`, or occasionally strong `ADJACENT` when the role is otherwise clearly aligned).

Do not require proof that React itself has been used for exactly three calendar years. This is an interview-fit rule, not permission to write a fabricated `3 years React` claim on the resume/application.

## Mandatory-requirement gate — interview-likelihood mode

Do not mechanically hard-fail because one or two requirements are not exact. A few stretches are acceptable when the overall job identity matches and the candidate could reasonably be interviewed/hired.

Normally allow scoring when:
- the majority of role-defining central requirements are `EXACT`/`DIRECT`,
- up to two central requirements are `ADJACENT` when transferable/learnable,
- one central `WEAK`/`NONE` may remain after evidence refresh when it is not the defining specialist identity of the job and the rest of the role is strong,
- several non-central gaps remain learnable,
- overall engineering tenure meets the role's general seniority/experience band.

Hard skip before scoring only for a clear blocker such as:
- role identity is fundamentally outside the candidate's engineering lane (for example mobile-only with no mobile evidence, research-scientist/model-training identity with no such evidence, or a specialist CUDA/GPU role with no specialist evidence),
- a required licence/degree/clearance/work authorization/legal condition is not met,
- explicit people-management/manager history is role-defining and unsupported,
- after targeted evidence refresh, multiple defining central capabilities remain `WEAK`/`NONE` such that the candidate would effectively be applying for a different profession/specialization,
- truthful application answers cannot satisfy a genuinely decisive factual requirement.

Do not hard-skip just because:
- a capability is absent from the canonical resume,
- exact technology-specific years are undocumented,
- the candidate has a few stack gaps,
- a requirement is supported mainly by substantial current projects rather than employment bullets.

## Score 0-100

- core technical overlap: 0-30
- mandatory-responsibility evidence: 0-25
- role/seniority calibration: 0-15
- production/ownership fit: 0-10
- domain/application fit: 0-8
- eligibility certainty: 0-7
- global experience-band fit: 0-3
- posting quality/recency/comp clarity: 0-2

Default auto-apply threshold: **72**.

## Credit discipline

- EXACT: up to full allocated credit
- DIRECT: usually 80-95%
- ADJACENT: usually 35-60% when genuinely transferable
- WEAK: usually 10-25%
- NONE: 0 for that requirement, but not automatically a hard gate unless role-defining under the rules above

Eligibility uncertainty is not scored; it fails the eligibility gate and becomes watchlist/research.

## Score bands

### 85-100 — rare near-exact
Strong evidence across almost all central requirements.

### 78-84 — strong
Good interview probability; small gaps are fine.

### 72-77 — credible / apply
Reasonable interview target with a few learnable stretches. Auto-apply when all true hard blockers are clear.

### 68-71 — opportunistic stretch
May apply when role identity, employer quality and eligibility are strong and gaps are learnable; otherwise watchlist. Do not lower truth/eligibility standards.

### below 68
Usually skip unless targeted evidence refresh is still outstanding.

## Seniority calibration

Do not automatically target Staff/Principal/Lead because technologies match. For Staff/Principal/Lead, look for organization-level technical direction, cross-team influence, architecture scope, expected mentoring/leadership, and the global years/seniority band.

Project ownership can strengthen technical breadth but does not automatically prove people management.

## Examples

- Backend Python + AWS + Postgres + Redis + API ownership: `EXACT/DIRECT` core fit.
- React absent from resume but verified across substantial first-party applications: `DIRECT` or `EXACT` capability, not `NONE`.
- JD says `3+ years React`, canonical career tenure exceeds that band, and React capability is verified: years band is not a gate; assess React capability and overall role fit.
- FastAPI vs Django: `ADJACENT` for framework-specific Django, but a Python backend role can still be viable if Django is not the whole role identity.
- CUDA/vLLM/Triton model-serving specialist with only general cloud/Kubernetes evidence: defining specialist mismatch -> fail.
- Full-stack role with strong backend plus verified frontend/full-stack projects and one UI/design stretch: score it; do not hard-skip mechanically.
