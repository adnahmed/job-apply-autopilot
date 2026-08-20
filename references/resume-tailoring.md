# Canonical Per-Job Resume Tailoring — V3

## Goal
Generate a fresh, truthful, ATS-friendly resume for each accepted job from an immutable canonical `.tex` source.

Tailoring can improve relevance and keyword alignment; it cannot guarantee interviews or hiring.

## Immutable source rule
Every job starts from exactly one of:

- `canonical/ai-applied-canonical.tex`
- `canonical/backend-platform-canonical.tex`

Never start from another generated `resume.tex` or `resume.pdf`.

The scaffold must preserve an untouched `canonical-source.tex` beside the working `resume.tex`.

## Evidence rule
Use `canonical/canonical-facts.yaml` as the claim whitelist.

Every material resume claim must be supported by:
- one or more canonical claim IDs, or
- an exact supported skill from the canonical facts list.

Do not introduce technologies just because they appear in the JD.

## Mandatory fit-map before editing
Create `fit-map.json` with each important JD requirement and its canonical evidence.

For every requirement classify:
- importance: mandatory / preferred / context
- evidence strength: direct / strong-adjacent / weak-adjacent / none
- canonical IDs
- ATS keyword allowed: true/false

If multiple central mandatory requirements have `none`, fail the technical gate instead of resume-tuning around the mismatch.

## ATS tailoring strategy
Use the exact employer terminology when the meaning is supported.

Good examples:
- JD says `PostgreSQL`; canonical says `Postgres` -> use `PostgreSQL`.
- JD says `agentic workflows`; canonical has LangGraph agent runtime/orchestration -> use the phrase naturally.
- JD says `hybrid retrieval`; canonical has hybrid graph/vector retrieval -> use exact wording where appropriate.

Bad examples:
- JD says `Django`; canonical has FastAPI -> do not add Django.
- JD says `PyTorch training`; canonical has LLM applications -> do not add PyTorch/model training.
- JD says `CUDA/vLLM/Triton`; canonical has AWS/Kubernetes -> do not add them.

## What may change per job

### Headline
Choose a truthful market-facing headline reflecting the job and canonical background, e.g.:
- AI Engineer | Applied AI, LangGraph & Production Systems
- Applied AI Engineer | Agents, Knowledge Systems & Python
- AI/Backend Engineer | Agentic Systems, FastAPI & AWS
- Senior Backend & Platform Engineer | Python, Node.js, AWS & Distributed Systems

Do not claim an exact formal title at an employer that was never held.

### Summary
Use 2-4 compact lines.
Prioritize:
- target role family,
- 3-5 direct skills/evidence areas,
- 1-2 strongest quantified production outcomes.

Avoid generic adjective-heavy summaries.

### Skills
Reorder supported skills to match the JD priority.
Keep requested supported keywords verbatim when natural.
Remove irrelevant skills before shrinking fonts.

### Experience bullets
Select/reorder/rewrite canonical facts; preserve numbers and causal meaning.
Prefer 4-6 HackOnTech bullets and 1-3 Creative IT Park bullets depending on space.

For AI roles, prioritize H8 and AI-relevant platform/reliability facts.
For platform roles, prioritize H2/H3/H5/H6/H7.

### Projects
Use only projects that add material evidence for the specific JD.

Typical selection:
- agent/tool/browser roles -> P1/P2/P3
- knowledge graph/retrieval -> P1/P3 and P7/P8 if relevant
- orchestration/workflow -> P4 plus H3/H7
- distributed/rendering/platform -> P5/P6 when relevant
- multimodal/NLP -> H8

### Education/languages
Keep concise. Never alter degree or institution.

## One-page optimization order
If the tailored resume exceeds one page:
1. remove least relevant project,
2. remove least relevant bullet,
3. compress skills,
4. shorten summary,
5. reduce vertical whitespace slightly,
6. only then make small font/spacing adjustments.

Do not make the resume unreadably small.

## Per-job output requirements
Each job directory should contain:
- `assessment.json`
- `job.json`
- `fit-map.json`
- `canonical-source.tex`
- `resume.tex`
- `resume.pdf`
- `resume.log`

The application log must record the generated PDF path and canonical source used.

## Final truth audit
Before upload compare `resume.tex` against `canonical-facts.yaml` and ask:
- Did I add any technology not supported?
- Did I inflate years, ownership, leadership, scale, domain expertise, or management?
- Did I change employer/title/dates?
- Did I imply work authorization or relocation status?
- Did I change quantitative outcomes?

If yes, correct it before application.
