# LinkedIn Activity Governor V5.9

## Purpose
Keep LinkedIn-specific application activity conservative without throttling the rest of the campaign. This governor applies to **LinkedIn Easy Apply only**. External ATS/company-site applications are outside this numeric governor and remain uncapped by the skill.

## Source-derived safety observations
Linked Helper's support material says LinkedIn monitors both the amount and speed of account activity, recommends spreading activity rather than bursting it, treats its 24-hour limits as rolling windows, and warns that simultaneous activity on the same LinkedIn account from multiple programs/sessions can look suspicious. It also says its numerical recommendations are experience/testing based rather than guaranteed LinkedIn platform thresholds.

Sources used for this policy calibration:
- https://support.linkedhelper.com/hc/en-us/articles/360015349559-What-kind-of-limits-should-I-use
- https://support.linkedhelper.com/hc/en-us/articles/23378382591250-How-to-stay-safe-when-managing-accounts-via-Linked-Helper
- https://www.linkedhelper.com/blog/linkedin-easy-apply

Do **not** interpret Linked Helper's general `150 actions / 24h` recommendation as `150 Easy Apply submissions`. The source does not establish that mapping.

## Skill-owned Easy Apply defaults
These are conservative job-apply-autopilot defaults, not claimed LinkedIn limits:

- maximum 4 **confirmed Easy Apply submissions** in any rolling 1-hour window,
- maximum 20 **confirmed Easy Apply submissions** in any rolling 24-hour window,
- minimum 600 seconds between confirmed Easy Apply submissions,
- only the coordinator submits Easy Apply applications,
- every confirmed Easy Apply submission is recorded in `.job-apply-autopilot/linkedin-activity-state.json`,
- on first upgrade/state creation, recent confirmed Easy Apply submissions are seeded from `applications.jsonl` so a new OpenCode session does not reset the rolling window.

Use `scripts/linkedin-governor.ps1 -Action Status` before starting another Easy Apply submission and `-Action RecordEasyApply` only after a confirmed success state.

## When Easy Apply is not currently allowed
Do not stop the campaign. Continue:

- LinkedIn job discovery when there is no LinkedIn warning/rate-limit signal and ordinary browsing remains healthy,
- assessment and eligibility research,
- resume generation,
- unlimited external ATS/company-site application workers,
- reconciliation and analytics.

Queue ready Easy Apply jobs until the governor returns `easy_apply_allowed: true`.

## Security/rate-limit signals
On a LinkedIn 429, unusual-activity/security warning, account restriction, CAPTCHA, or MFA challenge:

1. record the signal with `scripts/linkedin-governor.ps1 -Action RecordSignal -SignalType <type>`,
2. stop LinkedIn application activity immediately,
3. do not retry through alternate LinkedIn endpoints or extra sessions,
4. do not bypass CAPTCHA/MFA/security controls,
5. continue external ATS/company-site applications on unaffected domains.

The packaged governor uses a 24-hour cooldown for ordinary rate-limit/security-warning signals. CAPTCHA, MFA, and account-restriction signals create a manual block instead of an automatic retry timer. `ClearManualBlock` is operator-only; the autonomous coordinator must never invoke it merely to resume activity.

## External ATS is intentionally separate
There is no skill-imposed:

- external-applications-per-run maximum,
- external-applications-per-day maximum,
- external concurrency maximum.

External workers are still subject to their own ATS/domain circuit breakers, truth/eligibility gates, and runtime/system resources.

## OAuth note
LinkedIn OAuth used by an external ATS is authentication, not an Easy Apply submission, so it does not consume the Easy Apply numeric budget. If the OAuth flow itself shows a LinkedIn security/rate-limit warning, stop that LinkedIn flow and use an available non-LinkedIn authentication fallback rather than pushing through the warning.

## No guarantee
Pacing reduces unnecessary burst risk; it does not guarantee LinkedIn will never restrict an account. Never interpret the governor as permission to bypass platform controls.
