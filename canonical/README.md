# Canonical resume sources

These two files are the immutable starting point for every generated resume:

- `ai-applied-canonical.tex` — AI / applied NLP / knowledge graph / agent-oriented canonical resume.
- `backend-platform-canonical.tex` — backend / platform / distributed systems canonical resume.

Do not edit these files during a campaign. Every accepted job gets its own directory. The scaffold script copies the selected canonical source to both `canonical-source.tex` (audit copy) and `resume.tex` (working copy). Only `resume.tex` may be tailored.

`canonical-facts.yaml` is the claim/evidence index. Tailored wording must remain traceable to one or more claim IDs from that file.
