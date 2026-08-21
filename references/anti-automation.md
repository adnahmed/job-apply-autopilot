# Anti-Automation and Circuit-Breaker Policy V5.14

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
3. call `scripts/domain-circuit-breaker.ps1 -Action Record` to create the domain marker and audit event,
4. do not bypass CAPTCHA/MFA/security controls,
5. continue unaffected domains/jobs.

## Parallel-worker rule
External ATS workers may run without a numeric concurrency cap, including multiple jobs on the same ATS domain. Every worker must check `domain-circuit-breaker.ps1 -Action Status -Domain <domain>` before browser work and immediately before final Submit. If another worker has tripped the circuit breaker, stop without submitting.

This is a reactive safety mechanism, not a pre-emptive per-domain concurrency cap.

## Retry policy
- ordinary form validation error: one corrective retry maximum,
- upload/UI technical failure without security signal: up to two implementation attempts,
- spam/automation/security/rate-limit: zero retries,
- CAPTCHA/MFA/security challenge: zero bypass attempts.

## LinkedIn-specific
LinkedIn Easy Apply remains coordinator-owned and is paced by `scripts/linkedin-governor.ps1`. Before starting a new Easy Apply submission, check governor status. After a confirmed Easy Apply submission, record it immediately.

If the governor says Easy Apply is not currently allowed, do **not** stop the campaign: continue discovery, assessment, resume generation, and all external ATS/company-site applications. External application throughput is not part of the LinkedIn governor.

On a LinkedIn 429, account warning, unusual-activity/security message, CAPTCHA, MFA, or account restriction, record a governor signal and stop LinkedIn application activity. Do not try alternate LinkedIn endpoints, extra sessions, or repeated Submit attempts to get around the pause. External ATS workers on non-LinkedIn sites may continue.

The governor is a conservative pacing/safety mechanism, not a guarantee against LinkedIn restrictions and not a technique for bypassing platform controls.

## ATS-specific
Do not replay POSTs, synthesize hidden security tokens, or probe anti-bot endpoints merely to force submission after an ATS rejects automation.


## Domain health observations
A successful submission may be recorded as positive operational evidence in per-job `application-result.json` and campaign analytics. This does not disable future circuit breakers: a domain can be healthy for one application and later resist automation.

Do not pre-emptively block an entire ATS vendor just because one employer on that vendor behaved differently, unless the observed signal is clearly vendor/domain-wide. Circuit-breaker markers are run-scoped operational state, not permanent reputation labels.
