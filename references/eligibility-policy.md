# Eligibility Evidence Policy V4

## Core rule
A foreign `Remote` label is not enough to auto-apply from Pakistan. Auto-submission requires positive evidence that Pakistan-based candidates can be considered, or explicit immigration/relocation support that can bridge the location gap.

## Auto-applicable eligibility states

### PAKISTAN_ELIGIBLE
Examples:
- role location is Pakistan,
- JD explicitly allows candidates in Pakistan,
- official allowed-country list includes Pakistan.

### WORLDWIDE_EXPLICIT
Examples:
- `work from anywhere`,
- `remote worldwide`,
- `hire anywhere`,
- `candidates globally`,
- official employer policy explicitly says the role can be hired globally.

### GLOBAL_CONTRACTOR_EXPLICIT
Examples:
- company explicitly hires contractors from any country,
- JD says international contractor engagement is available and no conflicting country restriction exists.

### INTERNATIONAL_HIRING_EXPLICIT
Examples:
- `international applicants welcome`,
- `we hire internationally for this role`,
- official recruiting page names broad eligible regions that include Pakistan.

### SPONSORSHIP_EXPLICIT / RELOCATION_EXPLICIT
Examples:
- visa sponsorship,
- work-permit support,
- immigration support,
- relocation package/assistance,
- visa transfer.

## Not positive evidence
The following may be useful context but do not establish eligibility:

- LinkedIn says `Remote`,
- LinkedIn search location was `Worldwide`,
- company is multinational,
- company has a team in AU/IN/US or other countries,
- company has offices in many countries,
- form accepts a Pakistan phone/address,
- profile country dropdown includes Pakistan,
- application has no work-auth question,
- no country exclusion was found,
- the employer mentions pay transparency for a different country,
- a recruiter or aggregator labels the role worldwide without employer confirmation.

## Country/region locked examples
Treat as ineligible unless explicit sponsorship/relocation bridges the gap:

- `Remote - Australia` / `Remote-first in Australia`
- `Remote - United States`
- `Remote - India`
- `Remote - Spain`
- `Remote - EU`
- `Remote - EMEA` when Pakistan is not explicitly included
- `must reside in ...`
- `right to work in ... required`

## Verification sources, strongest first
1. official employer JD / ATS requisition,
2. official employer remote-hiring/location policy,
3. explicit application screening text,
4. verified recruiter statement tied to the exact requisition,
5. LinkedIn source posting.

Do not use the absence of an exclusion as evidence.

## Unknown state
If evidence remains unclear after reasonable verification:

- state = `UNCLEAR`,
- do not auto-submit,
- if technically attractive, write it to `relocation-watchlist.jsonl`,
- continue campaign without asking the user.

## Redirect recheck
After an external redirect, re-evaluate location eligibility before creating a profile or generating a resume when practical. If the destination introduces a new location/work-auth restriction, stop immediately.
