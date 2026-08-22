# Autonomous Application Policy V6.4

## Principle
Quality and eligibility beat volume. Requested application count is a maximum target, never a quota.

## Fault containment
A recoverable per-job failure must never terminate the campaign. Schema mismatch, script invocation mistakes, browser implementation failures, resume-build failures, and worker/tool exceptions are isolated to that job/route. Correct once when deterministic; otherwise leave recoverable state and continue unaffected work. A standalone CAPTCHA first gets one solver-assisted wait; an unresolved/repeated CAPTCHA, explicit security signal, or MFA stops only the affected route.

Assessment artifacts are committed only through `scripts/commit-assessment.ps1`; promotion is coordinator-driven only through `scripts/advance-workitem.ps1`. Do not hand-author transition JSON.

Every outbound application side effect is reserved through `scripts/application-send-guard.ps1`. An interrupted worker, missing receipt, or ambiguous return requires authenticated verification of the real Sent/ATS state before another Send/Submit. Channel-incompatible or unavailable evidence quarantines verification. Direct email applications use `job-autopilot-email-apply`; external forms use `job-autopilot-external-apply`.

An exact FreeHire employer-mail link is also authoritative positive evidence only when `sync-freehire-context.ps1` verifies the stored slug, stable external message ID, recognized application signal, candidate mailbox, and a timestamp at or after the reservation. This proof may confirm submission but can never prove absence. Suggested, unlinked, stale, or merely similar mail is not evidence.

Only `scripts/reconcile-application-result.ps1` converts a terminal per-job result into the shared applications ledger. Terminal blockers are created through `scripts/write-application-outcome.ps1`. Both are idempotent; workers and coordinators never hand-append application rows.

FreeHire tracking is a downstream mirror, never a submission mechanism or authority. `POST /jobs/{slug}/apply` may run only after reconciliation has written a verified local `submitted` row. A FreeHire outage, stale remote stage, or mirror error cannot change local status or permit another send.

## Hard gates before scoring
A job must pass all of these before a numeric score is computed:

1. job integrity / identity,
2. positive geographic/work eligibility evidence,
3. campaign role-family intent,
4. central mandatory requirements,
5. known truthful-answer feasibility.

A hard-gate failure cannot be rescued by salary, brand, relocation attractiveness, recency, Easy Apply convenience, or an otherwise high technical score.

## Candidate calibration
Treat the canonical resume as truthful marketing material, not proof of deep specialization in every term it contains.

Do not infer:

- Staff/Principal depth from a Senior title,
- people management from technical ownership,
- formal ML-evaluation/statistical methodology from general semantic checking/evaluation work,
- model-training expertise from LLM application work,
- FDE/consulting depth from having worked on client projects,
- specialist SRE/DevOps identity from having operated production systems,
- specialized domain expertise from one adjacent project.

## Truthfulness
Resume and fit artifacts never invent employer/title/dates, management scope, degree/certification, clearance, metrics, or unsupported technologies. Application-form answers use configured evidence first and the completion-first generated-answer policy when mandatory data is absent. For matching, derive overall engineering tenure from canonical employment history and do not maintain per-technology year counters. Public project evidence may establish real technology capability even when the resume omits it.

## Passwords and authentication
Password creation/autofill is allowed. Prefer existing sessions and LinkedIn OAuth/import first because they are faster and reduce form friction. Passwords should not be the reason an otherwise valid application stalls.

## Score interpretation
Use conservative score bands:

- 85-100: rare near-exact fit
- 78-84: strong fit
- 72-77: reasonable fit
- 68-71: opportunistic stretch
- below 68: usually skip

Default auto-apply threshold: 72 after every true hard blocker/gate passes. A few learnable technical stretches are scoring penalties, not automatic hard failures.

## Application throughput and LinkedIn pacing
- requested count = maximum, never a quota
- **external ATS/company-site applications have no skill-imposed per-run, daily, or concurrency limit**
- external applications continue even when LinkedIn Easy Apply is cooling down or paused
- LinkedIn Easy Apply is governed separately by `references/linkedin-activity-governor.md` and `scripts/linkedin-governor.ps1`
- default Easy Apply safety policy: at most 4 confirmed Easy Apply submissions in a rolling hour, at most 20 confirmed Easy Apply submissions in a rolling 24 hours, and at least 600 seconds between confirmed Easy Apply submissions
- those Easy Apply numbers are conservative skill defaults, not claimed LinkedIn platform limits; they may be tuned later without changing external ATS throughput
- one ordinary corrective retry for form validation
- zero retries after automation/spam/security/rate-limit signals
- one solver-assisted CAPTCHA recovery window; no repeated Submit clicks

## Non-interactive choice policy
Never ask the user to choose among routine application/workflow options and never invoke a question tool. For non-factual safe choices, select **Recommended** when present; otherwise select the first available safe option and continue. Use configured evidence first for factual screening; when a mandatory value remains absent, generate one context-aware answer and continue rather than blocking or skipping. A standalone CAPTCHA is handled through the installed solver and a bounded wait without closing its tab. Unresolved CAPTCHA/MFA/security/manual-required states are checkpointed and bypassed by moving to other jobs, not turned into an interactive chat prompt.

## Unknown required facts

Do not create `blocked-unknown-fact` or `blocked-protected-fact`. Run `preflight-application.ps1` when an answer plan exists, then call `resolve-application-answer.ps1`. It uses configured identity, education, employment, compensation, notice/start timing, and demographic-decline facts. Any unresolved required question returns `needs-semantic-answer` for one generated contextual answer. Repeating the same normalized question more than twice returns `loop-detected`, after which the applicator answers directly without another resolver call.

For numeric expected or current compensation, prefer the posting's lower quartile. If the posting has no band, call `get-market-salary.ps1`: use FreeHire country + category + seniority p25 when at least the configured sample count exists, then broader country/category/seniority and country-wide bands, then global category bands. Convert year/month/day/hour consistently. Use the profile's configured local/global numbers only when the market API has no usable band.
Try configured/profile facts, non-conflicting FreeHire values, saved application values, and legitimate decline options first. If none resolves a mandatory field, generate one context-aware answer and continue.


## Verified public project evidence

Follow `candidate-evidence-policy.md`. Screening answers use verified public project evidence first when the question asks whether the candidate has used/built/worked with a technology or project capability, then use the completion-first generated-answer policy for unresolved mandatory fields. Fit maps and resumes must not convert generated form answers into canonical evidence.
