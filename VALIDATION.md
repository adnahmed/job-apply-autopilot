# V4 Validation

## Canonical LaTeX
The two canonical `.tex` files are carried forward unchanged from the user-supplied sources and their SHA-256 hashes remain recorded in `canonical/SHA256SUMS.txt`.

## V4 behavioral changes validated structurally

- Broad engineering role lanes are present in `profile.yaml` and `SKILL.md`.
- Positive eligibility evidence is required by `references/eligibility-policy.md`.
- `Remote`, global-company status, international team distribution, address acceptance, and absence of a screening gate are explicitly marked non-evidence.
- OAuth priority includes LinkedIn before password account creation.
- Password generation/autofill remains allowed as fallback.
- Evidence classes are EXACT / DIRECT / ADJACENT / WEAK / NONE.
- Default calibrated auto-apply threshold is 74; 85+ is documented as rare.
- Resume tailoring is selection-first and requires `tailoring-audit.json`.
- Domain circuit breakers stop retries after spam/automation/rate-limit/security signals.

## Script enforcement

`scaffold-resume.ps1` creates:

- `assessment.json`
- `fit-map.json`
- `tailoring-audit.json`
- immutable `canonical-source.tex`
- working `resume.tex`

`compile-resume.ps1` refuses compilation unless:

- assessment status = passed,
- all hard gates = true,
- fit map status = complete and has requirements + score,
- tailoring audit status = complete,
- unsupported terms list is empty,
- canonical audit copy hash matches the scaffold-time canonical hash.

It then runs LaTeX and validates the generated PDF as before.
