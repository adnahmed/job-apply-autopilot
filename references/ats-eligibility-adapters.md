# ATS Eligibility Adapters V5.5

## Goal
Resolve geographic eligibility as cheaply and accurately as possible using official employer/ATS evidence before spending time on account creation or application forms.

These adapters are read-only heuristics. Endpoint shapes can change. Never treat a failed adapter lookup as evidence that a role is fake or ineligible; fall back to the official job page / eligibility worker.

## Evidence priority
For the exact requisition, prefer:
1. official ATS country/region field or closed allowed-country list,
2. official employer job page location / explicit hiring-region text,
3. explicit sponsorship / relocation / international-contractor language,
4. direct-employer LinkedIn location/region,
5. general company hiring policy.

A closed official country list excluding Pakistan is decisive negative evidence. An official exact-role APAC/APJ/Asia/global scope with no narrower contradiction is positive evidence under `eligibility-policy.md`.

## Workable
Observed official widget endpoint pattern:

`https://apply.workable.com/api/v1/widget/accounts/<company-slug>?details=false`

Procedure:
- identify the exact requisition by title + shortcode / publication metadata,
- inspect repeated country variants for the same exact requisition,
- if the ATS enumerates a finite set of countries and Pakistan is not present, classify `NOT_ELIGIBLE` unless explicit sponsorship/relocation bridges the gap,
- if Pakistan is present, treat it as strong positive evidence.

Do not infer worldwide eligibility merely from `telecommuting=true`.

## Ashby
Observed official posting API pattern:

`https://api.ashbyhq.com/posting-api/job-board/<board-name>`

Procedure:
- match the exact requisition / posting id,
- inspect `location`, `secondaryLocations`, remote/workplace fields, and any explicit region description,
- `Remote (Europe)` / Europe-only evidence excludes Pakistan absent an explicit bridge,
- generic marketing such as `remote-first` or `around the world` does not override an exact requisition location.

## Lever
Lever job pages are often sufficient for identity and location, but a location text box accepting Pakistan during an application is NOT by itself positive eligibility evidence.

Use:
- exact job page location / team / commitment fields,
- explicit remote-region wording,
- explicit international-contractor / sponsorship wording,
- application screening questions only as newly revealed evidence.

LinkedIn OAuth/import can simplify application completion after eligibility has already passed.

## Greenhouse and other ATS
Use the same principle even if the endpoint differs:
- prefer the exact official requisition's structured location/office/country fields,
- treat explicit closed country lists as decisive,
- do not rely on generic company office lists,
- do not probe private/authenticated APIs or anti-bot endpoints.

## When to invoke the eligibility worker
Invoke `job-autopilot-eligibility` when:
- the LinkedIn/job source says EMEA/Europe/UAE/US/etc. and a bridge might exist,
- the source says Remote with no usable scope,
- official ATS identity/location differs from LinkedIn,
- the exact role may have sponsorship/relocation,
- a public ATS adapter may resolve a closed country list.

Do NOT open an Easy Apply/external application merely to discover a country restriction if the official ATS already answers the question.
