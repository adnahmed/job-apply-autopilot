# Canonical Per-Job Resume Tailoring V4 — Selection First

## Goal
Create a fresh, credible, ATS-readable resume for each accepted job without turning adjacent experience into a new specialist identity.

## Immutable source
Every job starts from exactly one untouched canonical source:

- `canonical/ai-applied-canonical.tex`
- `canonical/backend-platform-canonical.tex`

Never start from another generated resume.

The job folder must preserve `canonical-source.tex` unchanged.

## Canonical evidence
`canonical/canonical-facts.yaml` is the claim whitelist and truth ceiling.

A canonical keyword being present does not automatically prove deep expertise, years of specialist experience, formal methodology, or a specialist career identity.

## Tailoring order
Default to the least-transformative operation that improves relevance:

1. select relevant canonical bullets,
2. reorder bullets,
3. reorder supported skills,
4. select/reorder projects,
5. remove irrelevant content,
6. use exact supported terminology aliases,
7. shorten wording while preserving meaning,
8. only then lightly rewrite for clarity.

Substantial rewriting is exceptional, not the default.

## Headline calibration
Use restrained market-facing headlines supported by the actual background.

Preferred examples:
- `Senior Backend Engineer`
- `Backend & Platform Engineer`
- `Software Engineer — Backend & Platform`
- `Python / Backend Engineer`
- `Software Engineer — Applied AI`
- `Applied AI Engineer`
- `AI Application Engineer`

Avoid manufactured combinations such as:
- `LLM Evaluation & Production Infrastructure Expert`
- `Distributed AI Systems Architect`
- `Staff AI Platform Engineer`

Do not mirror Staff/Principal/Lead/Research titles merely because the target JD uses them.

## Summary
Use 2-4 compact lines. Prefer canonical language and concrete facts.

Good summary ingredients:
- actual broad role identity,
- 3-5 directly supported technologies/capabilities,
- 1-2 quantified production outcomes.

Avoid adjective-heavy claims like `expert`, `world-class`, `deep`, `leading`, `specialist` unless the canonical source itself explicitly supports that characterization.

## Skills
Reorder only supported skills.

Exact aliases are fine:
- Postgres -> PostgreSQL
- Node -> Node.js
- K8s -> Kubernetes

Do not insert unsupported JD technologies.

## Experience bullets
Prefer canonical bullet text verbatim or minimally shortened.

A rewrite must preserve:
- technology truth,
- scope,
- causal meaning,
- numerical values,
- ownership level,
- team/leadership implications.

Do not transform:
- `built semantic mismatch checks` into `led formal LLM evaluation methodology`,
- `owned a platform overhaul` into `set organization-wide architecture strategy`,
- `worked on client projects` into `forward-deployed consulting leadership`.

## Projects
Select projects only when they provide direct evidence for central JD needs. Do not use project names to imply professional years of specialist experience.

## ATS terminology rule
Use exact JD terms only when evidence class is `EXACT` or `DIRECT`.

For `ADJACENT`, use the canonical terminology, not the employer's stronger/specialized term.

Example:
- JD formal ML evaluation + canonical semantic mismatch workflow -> keep `semantic mismatch/evaluation workflow`; do not rewrite to `statistical model evaluation framework`.

## Tailoring audit
Create `tailoring-audit.json` in every generated folder with:

- canonical source,
- headline chosen,
- canonical claim IDs used,
- bullets removed,
- bullets reordered,
- aliases introduced,
- materially rewritten sentences and supporting IDs,
- explicit `unsupported_terms_added: []`.

If `unsupported_terms_added` is not empty, fix the resume before compile.

## One-page optimization
If over one page:
1. remove least relevant project,
2. remove least relevant bullet,
3. compress skills,
4. shorten summary,
5. reduce spacing slightly,
6. only then small font adjustments.

Never shrink into unreadability.

## Final audit before upload
Ask:

- Did the headline overstate seniority or specialization?
- Did an ADJACENT requirement become a DIRECT-sounding claim?
- Did I add unsupported technology or domain terms?
- Did I change employer/title/dates?
- Did I imply people management?
- Did I change numbers?
- Did I use a previous generated resume as source?

Any `yes` -> correct before applying.
