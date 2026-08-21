# Campaign Analytics V5.7

## Purpose
Use accumulated application outcomes to spend discovery effort where credible eligible jobs are actually found. Analytics may change search allocation, never truth/eligibility/fit standards.

## Runtime artifact
`scripts/update-campaign-stats.ps1` writes:

`.job-apply-autopilot/campaign-stats.json`

The coordinator should refresh it after several new outcomes and before a new discovery batch when the campaign has enough history.

## Track
At minimum:
- total decisions,
- submitted / blocked / skipped counts,
- submission rate,
- status distribution,
- source distribution,
- discovery-lane distribution when available,
- per-lane submitted / skipped / blocked counts,
- ATS-domain successes/blockers when `application-result.json` supplies them.

## Adaptive search allocation
Do not overreact to tiny samples.

After a lane has at least 8 resolved jobs:
- if it produces almost no eligible/submitted jobs and mostly agency/location/role-family rejects, reduce its share of the next discovery batch,
- if it repeatedly produces credible eligible applications, increase its share,
- keep at least occasional exploration of other lanes so the system does not lock into one source.

Examples:
- `Worldwide` searches that mostly produce region-locked roles should lose priority,
- home-country-targeted backend searches that yield direct employers should gain priority,
- relocation searches remain active even with lower volume because their upside differs from ordinary remote searches.

## Never optimize the wrong target
Do not optimize for raw number of submissions. Optimize discovery toward:
1. direct/credible employers,
2. geographic eligibility or genuine relocation bridge,
3. realistic mandatory-requirement fit,
4. successful application completion.

A high skip rate can be healthy if it means the system is rejecting junk early.
