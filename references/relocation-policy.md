# Relocation and Sponsorship Policy V4

Relocation is a first-class search lane, but **explicit evidence is required for auto-application**.

## Auto-applicable relocation states

### SPONSORSHIP_EXPLICIT
The exact role or official employer policy explicitly offers visa/work-permit sponsorship applicable to the role/location.

### RELOCATION_EXPLICIT
The exact role explicitly offers relocation assistance/package/bonus or overseas relocation support.

### INTERNATIONAL_HIRING_EXPLICIT
The exact role explicitly welcomes international candidates or states that the employer can hire outside the advertised country.

Only these states can auto-apply when relocation is enabled.

## Watchlist-only states

### RELOCATION_POSSIBLE_UNVERIFIED
Attractive foreign role at a company known to hire internationally, but no exact-role evidence of sponsorship/relocation.

### COUNTRY_SCOPE_UNCLEAR
Remote/foreign role with unclear hiring geography.

### COUNTRY_LOCKED_NO_SUPPORT
Role requires local residence/right-to-work and gives no sponsorship/relocation bridge.

The first two may enter `relocation-watchlist.jsonl`; the third is a skip.

## Not relocation evidence
Do not infer relocation from:

- a global company,
- offices in multiple countries,
- employees/team members in multiple countries,
- an ATS accepting the candidate's home-country address,
- LinkedIn `Remote`,
- LinkedIn `Worldwide`,
- salary shown in another country,
- no work-auth question,
- no explicit exclusion found.

## Remote-only campaigns
If user says `remote only`, do not submit non-remote relocation jobs. Keep strong explicit relocation opportunities on the watchlist.

## Default campaigns
If the user does not specify location restrictions, derive local lanes from `profile.yaml` and search both:
- candidate home-country / explicitly worldwide remote,
- verified relocation/sponsorship roles.

## Relocation never repairs weak fit
A glamorous destination or generous relocation package cannot override technical/seniority gates. A relocation role still needs the normal minimum technical score after gates pass.
