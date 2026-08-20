# Anti-Automation and Circuit-Breaker Policy V4

## Principle
When a site resists automation, stop pushing. Protect the account/session and move to another job.

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
2. mark current job `blocked-automation` or `manual-needed`,
3. append domain + reason to `.job-apply-autopilot/domain-circuit-breakers.jsonl`,
4. stop new submissions on that domain for the rest of the run,
5. continue with unaffected domains when safe.

## Retry policy

- ordinary form validation error: one corrective retry maximum,
- upload/UI technical failure without security signal: up to two implementation attempts, then `blocked-technical`,
- spam/automation/security/rate-limit: zero retries,
- failed CAPTCHA/MFA/security challenge: zero bypass attempts.

## LinkedIn-specific
If LinkedIn starts returning repeated 429s, account warnings, or unusual-activity signals:

- stop job-submission/browser harvesting actions that caused the signal,
- do not evade the limit through alternate URLs/endpoints,
- end or sharply curtail the run rather than risking the account.

## ATS-specific
Do not replay POSTs, synthesize hidden security tokens, or probe anti-bot endpoints merely to force submission after an ATS rejected automation.

A manual-needed role can be reported to the user at completion; the autonomous campaign should continue elsewhere.
