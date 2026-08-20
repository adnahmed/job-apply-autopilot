# Eligibility Evidence Policy V5.2

## Core rule
Do not equate `Remote` with worldwide, but also do not require magic wording such as `Pakistan applicants welcome` when ordinary geographic evidence already makes the candidate eligible.

Classify the exact role's hiring geography using the strongest available evidence. Eligibility is a practical hiring judgment, not a literal-string test.

## Auto-applicable eligibility states

### PAKISTAN_ELIGIBLE
Use when the exact role is reasonably tied to Pakistan. Positive evidence includes any of:
- exact job location is Pakistan / Islamabad / Rawalpindi / Lahore / Karachi or another Pakistan location,
- official employer/ATS posting states the role is Pakistan-based,
- direct employer LinkedIn posting itself lists Pakistan as the job location,
- a verified Pakistan-headquartered employer posts an unrestricted remote role through its own company account,
- the exact role is clearly attached to a verified Pakistan employing entity/team and has no conflicting country restriction.

A company merely having one office in Pakistan is supporting context, not enough by itself for an unrelated foreign-country role.

### REGION_INCLUDES_PAKISTAN
Use when the exact role explicitly allows a broad region that ordinarily includes Pakistan and no narrower country list or work-authorization rule conflicts.

Normally inclusive:
- Asia,
- South Asia,
- APAC / Asia-Pacific,
- APJ / Asia-Pacific-Japan.

Do not treat EMEA, EU, Europe, GCC, North America, LATAM, US, Canada, Australia, India, or another country-specific scope as including Pakistan unless the employer explicitly does so.

If an employer publishes its own definition of APAC/APJ that excludes Pakistan, that employer-specific definition wins.

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

## Evidence that can support, but should not decide alone
These signals become meaningful when combined with the exact role's location and provenance:
- employer has a verified Pakistan legal entity or engineering/hiring operation,
- employer repeatedly advertises engineering roles located in Pakistan,
- direct employer posting was intentionally published with Pakistan as its LinkedIn job location,
- direct employer posting uses APAC/APJ/Asia scope,
- application accepts Pakistan as the working location and no contradictory gate appears.

Do not discard these signals as worthless; weigh them in context.

## Weak / non-decisive evidence
The following are weak and must not establish eligibility by themselves:
- LinkedIn search placement merely because the search location was Pakistan or Worldwide,
- generic `Remote` label with no geographic context,
- company is multinational,
- team biographies span several countries,
- generic office list unrelated to the exact role,
- profile country dropdown contains Pakistan,
- no work-auth question appears,
- no exclusion statement was found,
- pay-transparency text for an unrelated country,
- recruiter/aggregator says worldwide without employer confirmation.

## Direct LinkedIn postings do not require an ATS duplicate
A credible direct-employer LinkedIn posting, including LinkedIn Easy Apply, can be the authoritative requisition source. Do NOT mark eligibility unclear merely because no separate careers-page or ATS copy was found.

Require external verification only when the posting itself is ambiguous, recruiter/aggregator-sourced, internally inconsistent, suspicious, or foreign-country eligibility genuinely remains unclear.

## Country/region locked examples
Treat as ineligible unless explicit sponsorship/relocation bridges the gap:
- `Remote - Australia` / `Remote-first in Australia`,
- `Remote - United States`,
- `Remote - India`,
- `Remote - Spain`,
- `Remote - EU`,
- `Remote - EMEA` unless employer explicitly defines the eligible region to include Pakistan,
- `must reside in ...`,
- `right to work in ... required`.

## Verification sources, strongest first
1. official employer JD / ATS requisition,
2. direct employer LinkedIn posting for the exact role,
3. official employer remote-hiring/location policy,
4. exact application screening text,
5. verified recruiter statement tied to the exact requisition.

Company metadata such as headquarters, legal entities, or office locations must be sourced from the supplied posting or verified research. The assessor must not invent or infer it.

## Unknown state
Use `UNCLEAR` only when a material geographic ambiguity remains after applying the contextual rules above. Do not use `UNCLEAR` merely because the JD omitted the words `Pakistan eligible`.

If genuinely unclear after reasonable verification:
- do not auto-submit,
- if technically attractive, write it to `relocation-watchlist.jsonl`,
- continue campaign without asking the user.

## Redirect recheck
After an external redirect, re-evaluate location eligibility before substantial profile creation or resume generation when practical. If the destination introduces a new location/work-auth restriction, stop immediately.
