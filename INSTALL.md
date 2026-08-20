# Install Job Apply Autopilot V5.3

V5.3 keeps the bounded OpenCode subagent pipeline, fixes Windows PowerShell execution-policy handling, and gives the packaged workers trusted direct write permission so Windows path canonicalization cannot block their per-job outputs.

## 1. Replace the installed skill

Extract `job-apply-autopilot-v5.3.zip`, then run PowerShell from the extracted folder:

```powershell
$src = ".\job-apply-autopilot-v5.3"
$dst = "$HOME\.config\opencode\skills\job-apply-autopilot"

if (Test-Path $dst) {
    $backup = "$HOME\.config\opencode\skills\job-apply-autopilot-backup-$(Get-Date -Format yyyyMMdd-HHmmss)"
    Move-Item $dst $backup
}

Copy-Item -Recurse -Force $src $dst

# Remove Mark-of-the-Web from downloaded/extracted skill files.
Get-ChildItem -LiteralPath $dst -Recurse -File | Unblock-File -ErrorAction SilentlyContinue
```

Expected skill file:

```text
~/.config/opencode/skills/job-apply-autopilot/SKILL.md
```

## 2. Install the packaged subagents

> Windows rule: always run packaged `.ps1` files as `pwsh -NoProfile -ExecutionPolicy Bypass -File ...`. `-ExecutionPolicy` belongs to `pwsh`; adding it after `& script.ps1` does not bypass policy.


V5 ships three hidden subagents under `agents/`. Install them globally:

```powershell
$skill = "$HOME\.config\opencode\skills\job-apply-autopilot"
pwsh -NoProfile -ExecutionPolicy Bypass -File "$skill\scripts\install-subagents.ps1"
```

This installs:

```text
~/.config/opencode/agents/job-autopilot-assessor.md
~/.config/opencode/agents/job-autopilot-eligibility.md
~/.config/opencode/agents/job-autopilot-resume.md
```

They are `hidden: true`, so they are intended for automatic Task invocation by the primary agent rather than normal `@` autocomplete. Restart OpenCode after installing them so the new agent definitions are loaded.

V5.3 intentionally gives the three packaged workers `edit: allow`. The user trusts these workers; their one-job directory boundary is enforced by their instructions and by coordinator ownership, not by brittle relative-path permission globs. BrowserOS and nested Task calls remain denied in the worker definitions.

Verify the installation:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "$skill\scripts\verify-subagents.ps1"
```

## 3. OpenCode permissions

If BrowserOS neo already works, keep your existing MCP connection. Merge this permission fragment into `opencode.json` if needed:

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "permission": {
    "skill": {
      "job-apply-autopilot": "allow"
    },
    "task": {
      "job-autopilot-*": "allow"
    },
    "browseros-neo_*": "allow"
  }
}
```

The worker definitions themselves deny BrowserOS. Only the coordinator should drive LinkedIn/ATS pages.

## 4. Verify canonical resumes

```powershell
$skill = "$HOME\.config\opencode\skills\job-apply-autopilot"
pwsh -NoProfile -ExecutionPolicy Bypass -File "$skill\scripts\verify-canonical.ps1"
```

Both canonical `.tex` files should report `OK`.

## 5. Check MiKTeX CLI

```powershell
pdflatex --version
latexmk -v
```

If `latexmk` is unavailable/broken, the compile script falls back to two direct `pdflatex` passes.

## 6. Keep your existing job-search workspace

Do not wipe earlier application history. Initialize/upgrade the runtime directories:

```powershell
mkdir "$HOME\job-search" -Force
cd "$HOME\job-search"
pwsh -NoProfile -ExecutionPolicy Bypass -File "$skill\scripts\init-workspace.ps1" -Workspace "$HOME\job-search"
```

Runtime structure now includes a parallel work queue:

```text
.job-apply-autopilot/
  queue/
    <job-id>-<slug>/
      job.json
      source.md
      assessment.json
      fit-map.json
      eligibility-research.json   # optional
  generated/
    <job-id>-<slug>/
      assessment.json
      fit-map.json
      tailoring-audit.json
      canonical-source.tex
      resume.tex
      resume.pdf
      resume.log
  applications.jsonl
  relocation-watchlist.jsonl
  domain-circuit-breakers.jsonl
```

## 7. How V5 parallelizes

The coordinator harvests a batch of jobs in BrowserOS, then uses Task subagents for independent work:

```text
Browser discovery (1 coordinator)
        ↓
  queue 4-8 jobs
        ↓
assess up to 4 in parallel
        ↓
eligibility research up to 3 in parallel when unclear
        ↓
coordinator final gate decision
        ↓
tailor/compile up to 3 resumes in parallel
        ↓
ATS/OAuth/form/submission one job at a time
```

This avoids parallel Submit clicks, duplicate applications, shared-ledger races, and multiplying LinkedIn/ATS anti-bot traffic.

## 8. OAuth behavior

Authentication order remains:

```text
existing ATS session
→ LinkedIn OAuth / Apply with LinkedIn
→ Import profile/resume from LinkedIn
→ other already-authenticated OAuth
→ generate/autofill password account
```

OAuth success never substitutes for geographic eligibility evidence.

## 9. Recommended command

The simple command remains enough:

```text
Use job-apply-autopilot. Apply to jobs.
```

V5 should automatically use its packaged subagents when Task is available. If Task is unavailable, it performs the same stages serially.
