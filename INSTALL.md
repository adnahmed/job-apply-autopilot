# Install Job Apply Autopilot V3 — Canonical Resume Edition

## What changed in V3

Every accepted job now gets a brand-new resume regenerated from one of the two immutable canonical LaTeX files you supplied. Generated resumes never become future templates.

The flow is:

```text
job passes gates
  -> requirement-to-canonical evidence map
  -> copy untouched canonical .tex
  -> tailor working resume.tex to exact JD
  -> MiKTeX compile
  -> one-page / text / truth checks
  -> upload generated resume.pdf
```

## 1. Replace the old skill

Extract `job-apply-autopilot-v3.zip`, then in PowerShell:

```powershell
$src = ".\job-apply-autopilot-v3"
$dst = "$HOME\.config\opencode\skills\job-apply-autopilot"

if (Test-Path $dst) {
    $backup = "$HOME\.config\opencode\skills\job-apply-autopilot-backup-$(Get-Date -Format yyyyMMdd-HHmmss)"
    Move-Item $dst $backup
}

Copy-Item -Recurse -Force $src $dst
```

The important path must exist:

```text
~/.config/opencode/skills/job-apply-autopilot/SKILL.md
```

## 2. Verify the canonical resumes were not altered

```powershell
$skill = "$HOME\.config\opencode\skills\job-apply-autopilot"
& "$skill\scripts\verify-canonical.ps1"
```

It should report `OK` for both canonical `.tex` files.

## 3. Check MiKTeX CLI

```powershell
latexmk -v
pdflatex --version
```

V3 prefers `latexmk` and falls back to two `pdflatex` passes.

## 4. Initialize the workspace

```powershell
mkdir "$HOME\job-search" -Force
cd "$HOME\job-search"
& "$skill\scripts\init-workspace.ps1"
```

Runtime data appears under:

```text
$HOME\job-search\.job-apply-autopilot\
  applications.jsonl
  relocation-watchlist.jsonl
  generated\
```

## 5. Seed deduplication from the sanitized old ledger (optional)

```powershell
Copy-Item `
  "$skill\migration\applications.sanitized.jsonl" `
  "$HOME\job-search\.job-apply-autopilot\applications.jsonl" -Force
```

Do not migrate the old unsanitized ledger because the previous run wrote sensitive free-text data into it.

## 6. BrowserOS neo permission

If your existing BrowserOS neo tools work, keep that connection. Example OpenCode permission config:

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "permission": {
    "skill": {
      "job-apply-autopilot": "allow"
    },
    "browseros-neo_*": "allow"
  }
}
```

## 7. Recommended commands

### Remote AI/LLM applications

```text
Use job-apply-autopilot. Apply to up to 15 high-fit AI Engineer / LLM Engineer jobs, remote only, posted in the last 7 days. Generate a fresh canonical-based resume for every application. Do not lower quality to hit 15.
```

### Remote + sexy relocation opportunities

```text
Use job-apply-autopilot. Apply to up to 15 high-fit AI/LLM engineering jobs, remote or strong relocation opportunities, posted in the last 14 days. Prioritize explicit visa sponsorship, immigration support and relocation assistance. Generate a fresh canonical-based resume for every application.
```

### Relocation hunter

```text
Use job-apply-autopilot. Hunt worldwide for high-fit AI/LLM engineering jobs with visa sponsorship or relocation assistance, last 14 days, minimum score 85. Apply autonomously when sponsorship/relocation is verified and regenerate my resume from canonical LaTeX for each job.
```

### Dry run / quality audit

```text
Use job-apply-autopilot. Dry run only: find 30 AI/LLM opportunities, run integrity, eligibility, relocation and canonical-evidence gates, and show which jobs would receive tailored resumes. Submit nothing.
```

## 8. Canonical resume locations

```text
canonical/ai-applied-canonical.tex
canonical/backend-platform-canonical.tex
canonical/canonical-facts.yaml
```

These files are immutable during campaigns. Every job gets a fresh copy in its own generated folder.

## 9. Per-job generated artifacts

Example:

```text
.job-apply-autopilot/generated/4451234567-example-ai-engineer/
  assessment.json
  job.json
  fit-map.json
  canonical-source.tex
  resume.tex
  resume.pdf
  resume.log
```

`canonical-source.tex` is the untouched audit snapshot. `resume.tex` is the only file the agent tailors.
