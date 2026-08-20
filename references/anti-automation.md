# Anti-Automation and Circuit-Breaker Policy V5.6

## Principle
When a site resists automation, stop pushing. Protect the account/session and move to unaffected jobs. Parallel external ATS execution does not justify retries or bypasses.

## Immediate circuit-breaker signals
- `possible spam`
- `flagged as spam`
- `automation detected`
- `suspicious activity`
- `unusual traffic`
- `too many requests`
- HTTP 429 attributable to campaign traffic
- account restriction / temporary lock warning
- explicit bot-detection message
- CAPTCHA/MFA challenge requiring human interaction

## On first signal
1. do not click Submit again,
2. mark current job `blocked-automation` / `blocked-security` / `manual-needed` as appropriate,
3. best-effort create a domain marker under `.job-apply-autopilot/domain-circuit-breakers/`,
4. do not bypass CAPTCHA/MFA/security controls,
5. continue unaffected domains/jobs.

## Parallel-worker rule
External ATS workers may run without a numeric concurrency cap, including multiple jobs on the same ATS domain. Every worker must check the shared domain marker immediately before final Submit. If another worker has tripped the circuit breaker, stop without submitting.

This is a reactive safety mechanism, not a pre-emptive per-domain concurrency cap.

## Retry policy
- ordinary form validation error: one corrective retry maximum,
- upload/UI technical failure without security signal: up to two implementation attempts,
- spam/automation/security/rate-limit: zero retries,
- CAPTCHA/MFA/security challenge: zero bypass attempts.

## LinkedIn-specific
LinkedIn Easy Apply remains coordinator-owned. If LinkedIn starts returning repeated 429s, account warnings, or unusual-activity signals, stop the actions causing the signal rather than attempting alternate endpoints or simultaneous Easy Apply workers.

## ATS-specific
Do not replay POSTs, synthesize hidden security tokens, or probe anti-bot endpoints merely to force submission after an ATS rejects automation.


## Domain health observations
A successful submission may be recorded as positive operational evidence in per-job `application-result.json` and campaign analytics. This does not disable future circuit breakers: a domain can be healthy for one application and later resist automation.

Do not pre-emptively block an entire ATS vendor just because one employer on that vendor behaved differently, unless the observed signal is clearly vendor/domain-wide. Circuit-breaker markers are run-scoped operational state, not permanent reputation labels.
