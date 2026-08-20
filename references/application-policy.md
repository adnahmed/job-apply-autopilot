# Autonomous Application Policy V5.9

## Principle
Quality and eligibility beat volume. Requested application count is a maximum target, never a quota.

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
Never invent or inflate citizenship, residency, work authorization, sponsorship status, employer/title/dates, management scope, degree/certification, experience years, technology depth, domain experience, salary history, clearance, or identity/contact information.

## Passwords and authentication
Password creation/autofill is allowed. Prefer existing sessions and LinkedIn OAuth/import first because they are faster and reduce form friction. Passwords should not be the reason an otherwise valid application stalls.

## Score interpretation
Use conservative score bands:

- 85-100: rare near-exact fit
- 78-84: strong fit
- 72-77: reasonable fit
- 65-71: stretch
- below 65: skip

Default auto-apply threshold: 74 after every hard gate passes.

## Application throughput and LinkedIn pacing
- requested count = maximum, never a quota
- **external ATS/company-site applications have no skill-imposed per-run, daily, or concurrency limit**
- external applications continue even when LinkedIn Easy Apply is cooling down or paused
- LinkedIn Easy Apply is governed separately by `references/linkedin-activity-governor.md` and `scripts/linkedin-governor.ps1`
- default Easy Apply safety policy: at most 4 confirmed Easy Apply submissions in a rolling hour, at most 20 confirmed Easy Apply submissions in a rolling 24 hours, and at least 600 seconds between confirmed Easy Apply submissions
- those Easy Apply numbers are conservative skill defaults, not claimed LinkedIn platform limits; they may be tuned later without changing external ATS throughput
- one ordinary corrective retry for form validation
- zero retries after automation/spam/security/rate-limit signals

## Unknown required facts
Try, in order:
1. profile/canonical facts,
2. truthful saved LinkedIn/application values,
3. N/A / decline / non-disclosure where legitimate,
4. otherwise skip.

Never fabricate to complete a form.
