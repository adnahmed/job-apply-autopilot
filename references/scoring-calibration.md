# Conservative Evidence and Scoring Calibration V4

## Evidence classes

### EXACT
The canonical evidence explicitly demonstrates the same technology/responsibility/depth requested by the JD.

Examples:
- JD Python; canonical Python production work.
- JD PostgreSQL; canonical PostgreSQL/Postgres production work.

### DIRECT
Concrete canonical evidence demonstrates the same capability even if wording differs slightly.

Examples:
- JD REST API design; canonical FastAPI/Node API ownership.
- JD Kubernetes operations; canonical EKS/Kubernetes production work.

### ADJACENT
Related experience, but not the requested capability itself.

Examples:
- semantic mismatch/evaluation workflow -> adjacent to formal ML evaluation methodology,
- client project delivery -> adjacent to FDE/customer-facing consulting,
- FastAPI -> adjacent to Django only as Python web-backend experience, not Django expertise.

ADJACENT is useful context but cannot independently satisfy a central mandatory specialized requirement.

### WEAK
Loose conceptual overlap with little concrete evidence. Give very little credit.

### NONE
No supported evidence.

## Mandatory requirement gate

A role passes only if:

- every central mandatory requirement is EXACT or DIRECT, except at most one non-central mandatory item may be ADJACENT,
- no mandatory years-of-experience requirement depends on ADJACENT evidence,
- no specialist identity depends on inferred experience.

Two or more central mandatory items at ADJACENT/WEAK/NONE -> skip before scoring.

## Score 0-100

- core technical overlap: 0-30
- mandatory-responsibility evidence: 0-25
- role/seniority calibration: 0-15
- production/ownership fit: 0-10
- domain/application fit: 0-8
- eligibility certainty: 0-7
- experience-band fit: 0-3
- posting quality/recency/comp clarity: 0-2

Default auto-apply threshold: 74.

## Credit discipline

- EXACT requirement: up to full allocated credit
- DIRECT: up to 80-90% of allocated credit
- ADJACENT: at most 25-35%
- WEAK: at most 10%
- NONE: 0

Eligibility uncertainty is not scored; it fails the eligibility gate and becomes watchlist.

## Score bands

### 85-100 — rare
Near-exact match across central requirements, reasonable seniority, and explicit eligibility. This should not happen often.

### 78-84 — strong
Several direct matches, few minor gaps, no central unsupported requirement.

### 72-77 — reasonable
Credible application; some learnable gaps; still meets central requirements.

### 65-71 — stretch
Normally skip. May watchlist if company/relocation is attractive, but relocation does not turn it into a technical match.

### below 65
Skip.

## Seniority calibration

Do not automatically target Staff/Principal/Lead because the role contains familiar technology.

For Staff/Principal/Lead, require direct evidence for most of:
- organization-level technical direction,
- cross-team influence,
- architecture scope beyond one team/service,
- mentoring/leadership expected by the JD,
- years band.

If evidence is mostly project ownership and senior IC production work, classify as Senior-level evidence, not Staff/Principal.

## Examples

- Backend Python + AWS + Postgres + Redis + API ownership: likely DIRECT.
- Formal AI evaluation metrics/statistical testing when canonical only shows semantic mismatch checking: ADJACENT.
- CUDA/vLLM/Triton when canonical shows AWS/Kubernetes: NONE.
- Django when canonical shows FastAPI: ADJACENT for web-backend concepts, NONE for Django-years questions.
- FDE requiring repeated customer workshops and solution deployment when canonical only shows client work: ADJACENT unless direct consulting evidence exists.
