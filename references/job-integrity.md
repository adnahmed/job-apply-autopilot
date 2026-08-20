# Job Integrity and Ghost/Talent-Pool Detection

This gate exists to avoid fake, ghost, evergreen, misleading, intermediary, expert-marketplace, and bait-and-switch applications.

## Trust classes

### DIRECT_VERIFIED
Named employer; job exists on employer's official careers/ATS or the application flow is clearly employer-controlled; title/location/responsibilities match.
Default: eligible.

### DIRECT_REASONABLE
Named employer and coherent opening, but official ATS verification is unavailable or unnecessary for Easy Apply. Company/posting signals are normal and internally consistent.
Default: eligible.

### AGENCY_NAMED_CLIENT
Recruiter/agency clearly names the actual client and the role maps coherently to a real opening/client need.
Default: eligible only at score >= 86 and after destination identity recheck.

### AGENCY_UNKNOWN_CLIENT
"Hiring for a client" with no identifiable end-employer, vague project, or generic repeated description.
Default: skip.

### TALENT_POOL
"Join our network", "curated pool", "we'll selectively speak", "future opportunities", "talent community", "bench", "roster", or no specific open requisition.
Default: skip.

### EXPERT_MARKETPLACE
Application is primarily joining an expert/data/evaluation marketplace, model-evaluation pool, annotation network, RLHF contributor network, or generic contract expert roster rather than applying to a specific engineering opening.
Default: skip for software-engineering campaigns.

### JOB_AGGREGATOR_ONLY
Intermediary application that does not lead to a verifiable employer or coherent named-client opening and mainly exists to collect applicant data/alerts.
Default: skip.

### IDENTITY_MISMATCH
Source and destination materially disagree on employer, role family, work type, location, responsibilities, or nature of the opportunity.
Default: hard skip.

### SUSPICIOUS_REPOST_NETWORK
Same generic role repeatedly posted across many locations/titles/companies, highly templated, evergreen, or redirecting to the same unrelated destination.
Default: skip unless independently verified.

### UNVERIFIABLE
Insufficient evidence to determine whether a real current opening exists.
Default: skip.

## Required checks

Before applying, ask:
- Is there a specific role/requisition rather than a generic network?
- Is the employer or named client identifiable?
- Does the destination preserve the same job identity?
- Are primary responsibilities consistent?
- Is the application collecting information for this job or for a general marketplace/talent pool?
- Does the posting repeatedly appear under many locations/titles with identical copy?
- Is the redirect chain reasonable?
- Is the compensation/work type consistent from source to destination?

## Known-pattern caution
Treat expert marketplaces and broad AI-training/evaluation networks as `EXPERT_MARKETPLACE` by default for engineering campaigns unless the destination demonstrates a specific named engineering requisition.

For `micro1.ai` specifically: default to `EXPERT_MARKETPLACE` when the destination is a domain-expert/evaluator/contributor workflow. Do not apply merely because the LinkedIn wrapper used an engineering title. Only override this if a specific end-client engineering requisition with matching title/responsibilities is clearly verified.

Do not turn this into a permanent company blacklist; classify each actual posting and destination.

## Bait-and-switch examples
Hard skip when:
- "AI Machine Learning Engineer" -> "AI Domain Expert" / evaluator / annotation contributor
- named company role -> generic recruiter network signup
- full-time engineering -> hourly expert marketplace task pool
- remote worldwide -> country-resident-only destination
- software engineering -> professional writing / content review / rubric evaluation as primary work
