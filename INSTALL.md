# Install Job Apply Autopilot V4

V4 keeps the canonical LaTeX resume generator from V3 and fixes the real-world judgment issues found in the second campaign:

- broader realistic engineering search lanes instead of AI-only,
- positive eligibility evidence required before auto-apply,
- explicit relocation/sponsorship evidence for foreign auto-apply,
- conservative EXACT/DIRECT/ADJACENT evidence scoring,
- selection-first resume tailoring,
- LinkedIn OAuth/import before password account creation,
- immediate circuit breakers for spam/automation/rate-limit signals,
- compile-time fit-map + tailoring-audit enforcement.

## 1. Replace the installed skill

Extract `job-apply-autopilot-v4.zip`, then run PowerShell from the extracted folder:

```powershell
$src = ".\job-apply-autopilot-v4"
$dst = "$HOME\.config\opencode\skills\job-apply-autopilot"

if (Test-Path $dst) {
    $backup = "$HOME\.config\opencode\skills\job-apply-autopilot-backup-$(Get-Date -Format yyyyMMdd-HHmmss)"
    Move-Item $dst $backup
}

Copy-Item -Recurse -Force $src $dst
```

Expected skill file:

```text
~/.config/opencode/skills/job-apply-autopilot/SKILL.md
```

## 2. Verify canonical resumes

```powershell
$skill = "$HOME\.config\opencode\skills\job-apply-autopilot"
& "$skill\scripts\verify-canonical.ps1"
```

Both canonical `.tex` files should report `OK`.

## 3. Check MiKTeX CLI

```powershell
pdflatex --version
latexmk -v
```

If `latexmk` is unavailable/broken, the compile script falls back to two direct `pdflatex` passes.

## 4. Keep your existing job-search workspace

Do **not** wipe the V3 workspace if it already contains your application history. V4 can continue using it for deduplication.

```powershell
mkdir "$HOME\job-search" -Force
cd "$HOME\job-search"
& "$skill\scripts\init-workspace.ps1"
```

Runtime files:

```text
.job-apply-autopilot/
  applications.jsonl
  relocation-watchlist.jsonl
  domain-circuit-breakers.jsonl
  generated/
```

## 5. BrowserOS neo permissions

If BrowserOS neo already works in OpenCode, keep the existing connection. Example permission config:

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

## 6. OAuth behavior

V4 checks ATS authentication in this order:

```text
existing ATS session
→ LinkedIn OAuth / Apply with LinkedIn
→ Import profile/resume from LinkedIn
→ other already-authenticated OAuth
→ generate/autofill password account
```

It should not spend several minutes creating a candidate profile when a visible `Continue with LinkedIn` path can do the same job.

OAuth/import success does not prove geographic eligibility; the job still needs positive hiring-location evidence.

## 7. Recommended default command

This uses the full realistic profile rather than an AI-only campaign:

```text
Use job-apply-autopilot. Find and apply to up to 15 credible high-fit engineering jobs across my normal profile: backend/software, backend-platform, Python/Node, and practical applied-AI roles. Search Pakistan, explicitly worldwide remote roles, and verified visa-sponsorship/relocation opportunities. Use LinkedIn OAuth/import first when ATS sites offer it. Generate a fresh canonical-LaTeX resume for every accepted job. Do not infer worldwide eligibility from a Remote label, do not inflate adjacent experience, and do not lower standards to hit the target.
```

You can also simply say:

```text
Use job-apply-autopilot. Apply to jobs.
```

The skill's defaults now cover the broad engineering lanes.

## 8. Useful focused commands

Backend/software only:

```text
Use job-apply-autopilot. Apply to up to 12 backend/software roles that fit my profile, Pakistan or explicitly worldwide remote, plus verified relocation/sponsorship opportunities.
```

Applied AI only:

```text
Use job-apply-autopilot. Apply to up to 10 practical Applied AI / AI Application / LLM-agent roles. Avoid ML research and deep model-training infrastructure roles.
```

Relocation hunter:

```text
Use job-apply-autopilot. Hunt for credible engineering roles with explicit visa sponsorship, immigration support, international hiring, or relocation assistance. Apply only when the technical fit is reasonable and the support is verified for the exact role.
```

Dry run:

```text
Use job-apply-autopilot. Dry run only: find 30 opportunities across my normal engineering profile and show the integrity, eligibility, mandatory-requirement and calibrated-fit decisions. Submit nothing.
```

## 9. Per-job resume artifacts

Each accepted job gets its own clean canonical-derived folder:

```text
.job-apply-autopilot/generated/<job-id>-<slug>/
  assessment.json
  job.json
  fit-map.json
  tailoring-audit.json
  canonical-source.tex
  resume.tex
  resume.pdf
  resume.log
```

`compile-resume.ps1` now refuses to compile an application-ready resume until:

- all hard gates are marked passed,
- `fit-map.json` is complete with a score,
- `tailoring-audit.json` is complete,
- no unsupported terms are listed,
- `canonical-source.tex` still matches the canonical SHA-256 recorded at scaffold time.

## 10. Circuit-breaker behavior

If an ATS says the application is possible spam/automation, or LinkedIn/ATS produces a rate-limit/security warning, V4 stops submitting on that domain for the current run and moves on. It does not click Submit four times.
