# Candidate Public Evidence Policy V5.10

## Purpose

The canonical resumes are curated employment documents, not a complete inventory of everything the candidate has built. Never convert "not present in the resume" into "the candidate has never used it" when a technical requirement can be checked against first-party public artifacts.

The candidate actively updates public technical work. Treat GitHub, deployments, portfolio material, and attributable candidate-authored LinkedIn material as a live evidence surface. Do not hardcode project names in the skill. Resolve candidate identities from `canonical/canonical-facts.yaml` (and profile data only as an operational fallback), then discover current evidence dynamically.

## Source hierarchy

### 1. CANONICAL_PROFESSIONAL
`canonical/canonical-facts.yaml` and the immutable canonical resumes.

Strongest source for:
- employer responsibilities,
- career/employment dates,
- production ownership,
- traffic/scale/latency/cost metrics,
- leadership scope,
- employment titles,
- domain claims tied to paid work.

### 2. VERIFIED_ARTIFACT
A first-party GitHub repository, substantial source/config/manifests inside it, or a live deployment clearly tied to the candidate/repository.

Valid evidence for:
- exact technologies actually used,
- frontend/backend/full-stack project capability,
- architectural patterns visible in code/config,
- deployment/configuration tooling,
- substantial personal/open-source implementation.

A repository name, language badge, README buzzword, lockfile, dependency entry, or untouched starter template alone is insufficient. Prefer actual source structure, imports/components, config, commit/history evidence, and deployed behavior.

### 3. CORROBORATED_PUBLIC
The candidate's public LinkedIn project/profile/post or portfolio claim corroborated by a first-party repository/deployment.

Useful for:
- current project context,
- what the candidate is actively building,
- mapping deployments to repositories,
- project purpose and current direction.

### 4. PUBLIC_SELF_ATTESTED
Candidate-authored LinkedIn/profile/project/post or portfolio material attributable to the exact candidate but not yet artifact-corroborated.

It is legitimate candidate-provided evidence. For a central specialist requirement, prefer corroboration when reasonably available; do not discard it merely because it was not copied into the resume.

### 5. THIRD_PARTY_OR_INFERENCE
Search snippets about other people, generic company pages, likes/reposts, forks without meaningful candidate contribution, or inference from unrelated technologies.

Do not use these to establish candidate capability.

## Fit strength and provenance are separate

Keep fit classes `EXACT`, `DIRECT`, `ADJACENT`, `WEAK`, `NONE` and separately record `evidence_scope`:
- `professional`
- `verified_project`
- `corroborated_public`
- `public_self_attested`
- `mixed`

Examples:
- "experience with React" + substantial first-party React application -> `EXACT` or `DIRECT`, `verified_project`.
- "strong React proficiency" + multiple substantial React applications/deployments -> normally `DIRECT`, `verified_project`.
- "Tailwind experience" + real Tailwind config/classes/components in substantial code -> `EXACT`, `verified_project`.
- "production frontend serving 1M users" + personal Vercel deployment -> frontend capability is supported; the 1M-user scale claim is not.

## Global engineering-tenure model — do not count years per technology

Experience-band matching is global, not a per-skill stopwatch.

1. Derive the candidate's current overall professional software-engineering tenure from canonical employment dates/facts at runtime. Do **not** hardcode a literal total in this policy.
2. Compare a JD's general experience requirement to that global engineering-tenure band.
3. If a JD phrases the requirement as `N+ years with <technology/framework>` or similar, do **not** build a separate chronology for that technology. For fit/gating, separate the question into:
   - **tenure band:** does the canonical overall engineering tenure reasonably meet `N+`? and
   - **capability:** is the technology/capability supported by canonical or verified public evidence?
4. When both are true, treat the experience requirement as viable for interview-likelihood assessment. Do not reject merely because the exact first-use date of that technology is undocumented.
5. This rule does **not** turn the global tenure into a resume/application claim such as `N years of React`. It is an internal matching rule that prevents false negatives from per-technology year accounting.
6. For a form that explicitly demands an exact numeric duration for one technology, use a truthful dated duration when evidence supports one; otherwise do not fabricate a precise technology-specific duration.

This same rule applies to databases, cloud tools, frameworks, frontend technologies, AI libraries, and similar engineering capabilities. Years are an overall professional band; technologies are capability evidence.

## Hard-fail freshness guard

Before an assessor hard-fails a role because an artifact-verifiable technical capability is `WEAK` or `NONE`, ask:

1. Is `.job-apply-autopilot/candidate-evidence.json` present and reasonably fresh?
2. Does it cover this exact capability or a directly relevant project?
3. Has `<queue-dir>/candidate-evidence-research.json` already checked it for this job?

If not, and GitHub/deployment/portfolio/LinkedIn evidence could realistically settle it, return `status: needs-evidence` instead of `failed`.

This guard applies to React, Next.js, CSS/Tailwind, frontend UI implementation, full-stack work, databases, frameworks, infra tooling, AI libraries, and similar artifact-verifiable capabilities.

It is not a reason to investigate or infer citizenship, work authorization, required degree/licence/clearance, people-management history, employer-specific scale, or other facts public code cannot establish.

## Cache and targeted research

Reusable cache:

`.job-apply-autopilot/candidate-evidence.json`

Per-job report:

`<queue-dir>/candidate-evidence-research.json`

The cache accelerates assessment but is not immutable truth. A stale cache means "look for newer evidence"; it does not invalidate previously verified facts.

Default discovery freshness: 7 days. When a hard technical rejection would otherwise occur, targeted refresh overrides normal cache laziness.

## Evidence-worker rules

The evidence worker must:
- resolve exact candidate GitHub/LinkedIn identities from canonical facts rather than a hardcoded repo list,
- search/discover current first-party repositories relevant to the requested capabilities,
- prefer original first-party repositories; forks require meaningful candidate contribution,
- inspect source/config/manifests when retrievable,
- distinguish starter/template boilerplate from implemented application code,
- use deployments as corroboration, not proof of employer production scale,
- use only candidate-authored LinkedIn material; likes/reposts do not count,
- record URLs and concise observed evidence,
- state limitations,
- never infer employer association, people management, traffic/scale, work authorization, or regulated-domain ownership from personal projects.

Do not maintain a static list of projects inside the skill. Newly updated repositories/posts should become useful through live discovery without a skill release.

If public web retrieval cannot access candidate-authored LinkedIn material and the evidence worker marks `linkedin_followup_needed: true`, the **coordinator** may perform a narrow lookup of the exact candidate profile/activity using its already-authenticated LinkedIn session. Keep this coordinator-owned so there is still only one LinkedIn browser actor. Persist only attributable candidate-authored technical evidence into the per-job report/cache; likes/reposts do not count. Do this only when it could change a rejection decision, not as routine startup crawling.

## Shared-cache write discipline

Evidence workers write only their own per-job `candidate-evidence-research.json`.

They **do not** concurrently edit the shared `.job-apply-autopilot/candidate-evidence.json`. After a worker completes, the coordinator merges that result through `scripts/merge-candidate-evidence.ps1`, then re-runs the assessor. This avoids lost updates when several evidence workers run in parallel.

## Resume eligibility of public evidence

A public-evidence claim may be used in a tailored resume only when the per-job evidence report marks `resume_eligible: true` and provides a conservative `allowed_resume_claim`.

Public project evidence may add/select truthful project and skill material. It must not rewrite an employment bullet to imply that project technology was used at an employer unless canonical professional evidence supports that employer association.

Examples:
- Allowed: `Built a React/Next.js application ...` when verified from first-party code.
- Allowed: listing `React`/`Tailwind` in a project or skills context when substantial use is verified.
- Not allowed: `Built React systems at <employer>` without professional evidence tying React to that employer.
- Not allowed: a precise `N years React` claim unless a truthful duration is supported.

## Application answers

For binary capability screening such as `Do you have experience with React?`, substantial verified project evidence can support `Yes`.

For general `N+ years software engineering` screening, use the global tenure derived from canonical employment history.

For JD fit/gating, an `N+ years with React` requirement uses the global-tenure + capability model above; do not reject because React's exact start date is unknown. If the application itself demands a precise numeric technology-specific duration, do not invent one.
