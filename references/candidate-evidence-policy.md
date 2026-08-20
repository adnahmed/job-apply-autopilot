# Candidate Evidence Policy V5.11 — Bounded Live Evidence

Canonical professional facts cover employment history, tenure, employer responsibilities, metrics, education, and titles. They are not the complete technology inventory.

First-party GitHub source/config, tied deployments, portfolio artifacts, and attributable candidate-authored LinkedIn material can establish technical/project capability. They do not establish employer usage, employer production scale, people management, work authorization, or unsupported precise years.

## Global tenure

Derive overall engineering tenure from canonical employment dates. Do not count years per technology. For fit, `N+ years <technology>` means global tenure + capability. Do not turn that internal match into a precise technology-years resume/form claim without dated support.

## Evidence scopes

- `professional`: canonical paid-work evidence.
- `verified_project`: first-party source/config/deployment.
- `corroborated_public`: candidate-authored public claim corroborated by artifact.
- `public_self_attested`: attributable candidate-authored claim without artifact corroboration.
- `mixed`: combination.

## Decision-changing refresh only

Do not browse merely because a skill is absent from the resume. Use the runtime cache first.

Request live evidence only when:
1. the job is otherwise viable;
2. one narrow artifact-verifiable capability is the main remaining apply/skip uncertainty; and
3. fresh public evidence could realistically change that decision.

Do not research to prove a negative or to improve a score from 75 to 78.

## Hard research budget

For one job:
- targeted requested capabilities only;
- at most 5 relevant first-party repos total;
- at most 2 tied deployments;
- no full account/repository inventory;
- stop when decision-changing evidence is found;
- unresolved within budget = `UNRESOLVED`, not exhaustive `NONE`.

A common engineering capability left unresolved normally becomes a score/stretch issue. A fundamentally different specialist role may still fail on role identity.

## Resume/application use

Public project evidence can support truthful project/skills claims and binary capability answers. Never transplant project technology into an employer bullet without professional evidence. Never invent exact per-technology duration, employer production scale, management, or work authorization.

## Cache

Reusable positive evidence lives in `.job-apply-autopilot/candidate-evidence.json`. Per-job workers write only `candidate-evidence-research.json`; coordinator merges it with `merge-candidate-evidence.ps1`. Keep cache positive and reusable; do not store giant search histories.
