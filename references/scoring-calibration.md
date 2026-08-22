# Scoring Calibration V6.4 — Interview Likelihood

Score for credible interview probability, not checklist perfection.

## Evidence classes

- `EXACT`: explicit same capability.
- `DIRECT`: strong equivalent or clearly demonstrated capability.
- `ADJACENT`: transferable/learnable stretch.
- `WEAK`: slight support.
- `NONE`: credible evidence contradicts/clearly lacks a defining capability after appropriate bounded check. Absence from resume alone is not NONE.

## Tenure

Overall software-engineering tenure is derived from canonical employment history. Do not maintain years per framework/tool. `N+ years <tech>` = global tenure + tech capability for fit.

## Hard blockers

Hard-fail only:
- legal/work-auth/required credential/clearance blocker;
- fundamentally different specialist identity (research/model-training/CUDA/etc.);
- required people-management ownership with no evidence;
- several role-defining capabilities clearly absent, not merely undocumented.

One or a few adjacent/common-stack gaps normally reduce score, not reject.

## Score

- core technical overlap: 0–30
- responsibilities/role identity: 0–25
- seniority/overall tenure: 0–15
- production/ownership: 0–10
- domain/application overlap: 0–8
- eligibility certainty: 0–7
- experience band: 0–3
- quality/recency/comp: 0–2

Default apply threshold: 72.
- 85–100 rare near-exact
- 78–84 strong
- 72–77 credible apply
- 68–71 opportunistic stretch; apply when eligibility + role identity strong
- <68 usually skip

Do not inflate scores to satisfy volume. Do not require exhaustive evidence for every bullet.

Assessment payloads must expose all eight component values within these maxima; `commit-assessment.ps1` recomputes their sum and rejects unexplained totals. A passed fit map labels each requirement as defining, mandatory, or preferred. `WEAK`/`NONE` cannot support defining or mandatory requirements, and ATS keywords are allowed only for `EXACT` or `DIRECT` evidence.
