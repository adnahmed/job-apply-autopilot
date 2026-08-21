# Autonomous Application Policy V5.13

## Principle
Quality and eligibility beat volume. Requested application count is a maximum target, never a quota.

## Fault containment
A recoverable per-job failure must never terminate the campaign. Schema mismatch, script invocation mistakes, browser implementation failures, resume-build failures, and worker/tool exceptions are isolated to that job/route. Correct once when deterministic; otherwise leave recoverable state and continue unaffected work. Security/CAPTCHA/MFA controls still stop the affected route, never the rest of the campaign.

Assessment artifacts are committed only through `scripts/commit-assessment.ps1`; promotion is coordinator-driven only through `scripts/advance-workitem.ps1`. Do not hand-author transition JSON.

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
Never invent citizenship, residency, work authorization, sponsorship status, employer/title/dates, management scope, degree/certification, salary history, clearance, or identity/contact information. For matching, derive overall engineering tenure from canonical employment history and do not maintain per-technology year counters. Public project evidence may establish real technology capability even when the resume omits it. Do not fabricate a precise technology-specific duration on a form when no truthful duration can be supported.

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

## Non-interactive choice policy
Never ask the user to choose among routine application/workflow options and never invoke a question tool. For non-factual safe choices, select **Recommended** when present; otherwise select the first available safe option and continue. Factual screening answers must still come from truthful evidence. If none is supportable, use a legitimate decline/N/A when available or skip the job; do not ask the user to resolve it. CAPTCHA/MFA/security/manual-required states are logged and bypassed by moving to other jobs, not turned into an interactive chat prompt.

## Unknown required facts
Try, in order:
1. profile/canonical facts,
2. truthful saved LinkedIn/application values,
3. N/A / decline / non-disclosure where legitimate,
4. otherwise skip.

Never fabricate to complete a form.


## Verified public project evidence

Follow `candidate-evidence-policy.md`. Screening answers may use verified public project evidence when the question asks whether the candidate has used/built/worked with a technology or project capability. For fit/gating, technology-specific year requirements use the global engineering-tenure + capability model rather than per-skill chronology. Do not fabricate a precise per-technology duration, employer usage, production scale, management, or domain ownership when those dimensions are unsupported.
