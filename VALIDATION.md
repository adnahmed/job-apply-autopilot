# V5.4 validation additions

- Packaged assessor/eligibility/resume definitions use `edit: allow`, avoiding Windows relative/canonical path mismatch failures.
- BrowserOS remains denied for all three subagents; nested Task remains denied.
- Mandatory requirement policy no longer contradicts itself about a single central ADJACENT requirement.
- Role-defining ownership/years gaps still hard fail.
- Task-prompt hygiene forbids coordinator-injected employer/eligibility/fit claims; worker evidence must come from persisted source files.

# V5.2 Validation

Validated policy invariants:
- Pakistan search placement alone is weak evidence.
- Exact Pakistan job location on a direct employer posting is positive evidence.
- Verified Pakistan employer/entity tied to an unrestricted remote role can establish Pakistan eligibility.
- Explicit Asia/APAC/APJ role scope can establish `REGION_INCLUDES_PAKISTAN` unless employer-specific rules conflict.
- EMEA/EU/US/India/Australia remain non-Pakistan scopes absent explicit bridging evidence.
- Direct-employer LinkedIn/Easy Apply does not require a duplicate ATS posting.
- Company HQ/entity facts may not be asserted without supplied or researched evidence.
- Ambiguous foreign roles still become watchlist rather than auto-submit.


## V5.4 orchestration checks
- `job-autopilot-external-apply.md` packaged and installed.
- External applicator has `browseros-neo_*: allow`, `edit: allow`, `task: deny`.
- Other workers retain BrowserOS deny.
- No skill-imposed numeric external-application concurrency limit appears in orchestration policy.
- LinkedIn Easy Apply is explicitly coordinator-owned.
