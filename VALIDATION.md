# V5.11.4 Validation

- `VERSION.txt` = `5.11.4`.
- Main skill metadata version = `5.11.4`.
- Canonical `.tex` files are unchanged from V5.11.
- All packaged subagents keep `question: deny`.
- Non-interactive autonomy rule is present in coordinator and application policy.
- Benign workflow choices deterministically select `Recommended`, otherwise the first safe option.
- Factual screening remains evidence-bound; unsupported required facts use legitimate decline/N/A or skip rather than prompting/fabrication.
- CAPTCHA/MFA/security/manual-required states never create an in-chat question; other jobs continue.
- V5.11 fast-path scheduling, bounded evidence lookup, external ATS uncapped behavior, and LinkedIn governor remain unchanged.


## V5.11.4 focused checks
- Persistent-discovery rule present: dry wave is not completion.
- Non-LinkedIn discovery required before current-market exhaustion.
- Batch dedupe-before-details rule present.
- Reconcile guidance forbids runtime/script archaeology.
- No environment-specific BrowserOS configuration-incident guidance remains in operational files.
