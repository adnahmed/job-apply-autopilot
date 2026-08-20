# Conservative Evidence and Scoring Calibration V5.5

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

Judge mandatory requirements by **role identity and depth**, not by a mechanical one-gap rule.

A role passes when:

- every role-defining central mandatory requirement is EXACT or DIRECT,
- at most one central mandatory requirement may be ADJACENT **only** when it is a learnable/transferable component rather than a defining specialist capability, and the JD does not require explicit years/ownership depth for that missing component,
- no mandatory years-of-experience claim depends on ADJACENT/WEAK/NONE evidence,
- no specialist identity depends on inferred experience,
- non-central mandatory gaps are limited and truthfully answerable.

Hard skip before scoring when any of these is true:

- one role-defining central mandatory capability is WEAK/NONE,
- one role-defining central mandatory capability is only ADJACENT **and** the JD requires explicit ownership/depth/years in that capability,
- two or more central mandatory requirements are ADJACENT/WEAK/NONE,
- passing would require inventing a technology, domain, leadership scope, or years-of-experience claim.

Examples:

- FastAPI candidate vs a Django requirement, where Django is one implementation choice among Python web frameworks and no Django-years requirement exists: may be an ADJACENT learnable gap.
- A role requiring `4+ years owning data warehousing, data modeling, ETL/ELT and governance`, when canonical evidence shows ETL but not warehouse/governance ownership: role-defining depth gap -> fail even though some components are adjacent/direct.

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
