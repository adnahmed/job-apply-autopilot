# Search Strategy V5.14 — Keep Moving

Search for credible interview opportunities, not exhaustive cataloguing. A dry result page is not campaign completion.

Primary lanes come from `profile.yaml`. Prefer recent direct-employer jobs with clear location and concrete responsibilities.

## Card-first fast loop

For each search result page:
1. extract visible job IDs + title/company/location/href with available BrowserOS page-inspection tools when reliable;
2. batch IDs through `scripts/dedupe-jobs.ps1` **before opening details**;
3. drop already-seen IDs immediately;
4. obvious hard reject from card metadata? compact-log and move on;
5. plausible unseen result? read the full JD once;
6. strong eligibility + in-lane? queue for quick assessment;
7. ambiguous geography or one genuinely decision-changing specialist gap? let the local assessor request the unified bounded research worker; never perform broad research during discovery.

Do not create queue directories for obvious country locks, closed roles, unknown-client agencies, talent pools, expert marketplaces, or unrelated role identities.

## Discovery escalation ladder

Do not stop after one dry wave. Rotate in this order, skipping any lane just exhausted in the current cycle:

1. **Pakistan/local** — backend/software/Python/Node/full-stack/applied-AI variants; recent first.
2. **APAC/APJ/Asia remote** — role must include Pakistan geographically unless conflicting text appears.
3. **Worldwide/international** — require role-specific worldwide/global-contractor/international-hiring evidence before submit.
4. **Relocation/sponsorship** — explicit visa/relocation/international-candidate bridge.
5. **Direct employer / ATS outside LinkedIn** — careers pages and official ATS boards for relevant employers; do not stay trapped in LinkedIn search.
6. **Broaden** — title synonyms and wider freshness window (for example 24h -> 7d) while preserving dedupe and eligibility standards.

At least one non-LinkedIn lane is required before declaring current-market exhaustion. `Remote` or Worldwide search placement alone is never eligibility evidence.

Operate in rolling batches, but act on a passed job immediately. Never wait to finish the whole search page before routing a strong job.

Use campaign analytics only to choose the next lane/source. If a source has a strongly negative yield, rotate away sooner; do not lower fit or eligibility standards.

## Browser primitive

Use available BrowserOS tools normally. If one DOM extraction approach fails, switch once to another documented page-inspection method rather than repeatedly experimenting with equivalent approaches.
