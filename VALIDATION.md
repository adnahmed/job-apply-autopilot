# V5.11.1 Validation

- `VERSION.txt` = `5.11.1`.
- Main skill metadata version = `5.11.1`.
- Canonical `.tex` files are unchanged from V5.11.
- All packaged subagents keep `question: deny`.
- Non-interactive autonomy rule is present in coordinator and application policy.
- Benign workflow choices deterministically select `Recommended`, otherwise the first safe option.
- Factual screening remains evidence-bound; unsupported required facts use legitimate decline/N/A or skip rather than prompting/fabrication.
- CAPTCHA/MFA/security/manual-required states never create an in-chat question; other jobs continue.
- V5.11 fast-path scheduling, bounded evidence lookup, external ATS uncapped behavior, and LinkedIn governor remain unchanged.
