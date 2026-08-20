# V4 change log

## Fixed from real-world campaign review

- Foreign `Remote` roles now require positive eligibility evidence before auto-submit.
- Lack of a location question is explicitly non-evidence.
- Global company / international team / accepted Pakistan address are explicitly non-evidence.
- AIONIX-style `Remote-first in Australia` ambiguity now becomes watchlist, not auto-submit.
- Relocation auto-apply requires explicit sponsorship, relocation, or international-hiring evidence.
- Evidence classes changed to EXACT / DIRECT / ADJACENT / WEAK / NONE.
- Central mandatory requirements cannot be satisfied by adjacent experience.
- 85+ scores are defined as rare; default threshold changed to 74 with stricter calibration.
- Default search broadened to backend/software, backend-platform, Python/Node and practical applied-AI lanes.
- Staff/Principal/FDE/SRE/specialist roles are selective rather than default targets.
- Resume tailoring is selection/reordering-first; specialized branding inflation is prohibited.
- Per-job `tailoring-audit.json` added and compile script enforces it.
- Compile script verifies immutable canonical audit hash.
- LinkedIn OAuth/import is preferred before password ATS account creation.
- Autonomous password generation/autofill remains allowed as fallback.
- First spam/automation/rate-limit/security signal creates a domain circuit breaker; zero anti-bot submit retries.
- `domain-circuit-breakers.jsonl` added to runtime workspace.
