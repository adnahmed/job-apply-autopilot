# Job Integrity / Ghost / Bait-and-Switch Policy V4

## Goal
Avoid talent pools, expert marketplaces, ghost/syndicated jobs, misleading redirects, and recruiter posts that do not correspond to a coherent opening.

## Trust classes

### DIRECT_VERIFIED
Official employer posting or official ATS requisition; title/location/responsibilities match.

### DIRECT_REASONABLE
Strong evidence of a real employer opening, though some details may be sourced from LinkedIn before official redirect.

### AGENCY_NAMED_CLIENT
Agency/recruiter names the end client and the exact role remains coherent through the application path. Requires stronger score threshold.

### AGENCY_UNKNOWN_CLIENT
Unknown employer/end-client or generic future-client wording. Skip by default.

### TALENT_POOL
`Join our network`, future opportunities, evergreen database, community/talent cloud, no concrete requisition. Skip.

### EXPERT_MARKETPLACE
Expert/evaluator/data-labeling/RLHF marketplace or project-matching platform presented as a conventional engineering vacancy. Skip unless user explicitly requests this work category.

### JOB_AGGREGATOR_ONLY
Aggregator quick-apply with no verified employer requisition. Prefer direct employer ATS; skip if the real opening cannot be verified.

### IDENTITY_MISMATCH
Title, employer, location, employment type, or core work materially changes after redirect. Skip.

### SUSPICIOUS_REPOST_NETWORK
Repeated generic job copied across many countries/titles or referral networks with no stable employer requisition. Skip/watchlist depending on evidence.

### UNVERIFIABLE
Cannot establish a concrete opening after reasonable verification. Skip.

## Redirect identity fingerprint
Before leaving the source page capture:

- company,
- title,
- location,
- employment type,
- top responsibilities,
- mandatory technologies,
- named client if applicable.

After redirect compare again. Material mismatch -> `IDENTITY_MISMATCH`.

## Ghost/syndication warning signals
Increase suspicion when several are present:

- generic `we are hiring for one of our clients` with no named client,
- identical generic copy posted under many titles/countries,
- evergreen expert network rather than one opening,
- no requisition ID and no employer ATS presence,
- application destination uses substantially different title/work,
- screening questions are for evaluator/data-labeling work while source says software engineering,
- recruiter/referral tracking dominates the destination,
- role is repeatedly reposted without stable employer identity,
- official employer careers search does not contain the opening and source is stale/syndicated.

One signal alone does not prove a ghost job; classify on the combined evidence.

## micro1-style failure pattern
If a source says AI/ML/software engineer but the destination becomes a generic domain-expert/evaluation marketplace with RLHF/content-review/prompt-rating work, classify `IDENTITY_MISMATCH` or `EXPERT_MARKETPLACE` and stop.

Do not rationalize the mismatch because the pay is attractive or some skills overlap.
