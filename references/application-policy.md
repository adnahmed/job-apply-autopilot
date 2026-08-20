# Autonomous Application Policy V3

## Principle
Quality beats volume. The requested application count is a maximum target, never a quota.

## Hard gates before scoring
A job must pass all of these before any numeric fit score is computed:

1. Job integrity / identity
2. Geographic and work eligibility
3. Campaign role-family intent
4. Mandatory technical requirements
5. Truthful-answer feasibility for known mandatory screening constraints

A hard-gate failure is final for that posting unless new evidence materially changes the facts.

## Truthfulness
Never invent or inflate:

- citizenship or residency,
- work authorization / sponsorship status,
- relocation status,
- employer, title, dates, management scope,
- degree/certification,
- years of experience,
- technologies or domains,
- salary history,
- security clearance,
- phone/address/contact information.

Existing saved LinkedIn answers may be reused only when consistent with `profile.yaml` and the current application.

## Security
Never store or reveal passwords, OTPs, cookies, auth tokens, recovery secrets, or session material.
Never bypass CAPTCHA/MFA/rate limits/automation warnings.

## Score after gates pass
- Role-family / core technical fit: 0-35
- Mandatory-responsibility evidence: 0-20
- Seniority / ownership: 0-15
- AI/LLM domain fit: 0-10
- Remote/relocation compatibility: 0-10
- Experience band: 0-5
- Recency / employer / compensation clarity: 0-5

Default threshold: 82.
Agency with named client: threshold 86.
Direct referral / known hiring manager: threshold may be 78 if all gates pass.

## Scoring discipline
Do not award points because a title merely contains "AI" or "ML". Evidence must map to actual responsibilities.
Do not treat adjacent experience as equivalent to a mandatory specialized skill.
Do not let recency, salary, brand, or relocation desirability compensate for a core technical mismatch.

## Campaign isolation
The campaign request defines the role family. Do not broaden it silently.

Examples:
- AI/LLM campaign -> no generic Django/backend/data job unless AI/LLM engineering is genuinely central.
- Backend/platform campaign -> AI exposure is a bonus, not required.

## Application limits
- requested count = maximum target
- default max submissions/run = 20
- default max external/run = 10
- stop safely on account/security/rate-limit signals

## Unknown required facts
Try, in order:
1. `profile.yaml`
2. truthful saved LinkedIn/application data
3. explicit non-disclosure / N/A option
4. otherwise skip `blocked-unknown-fact`

Never fabricate to complete a form.
