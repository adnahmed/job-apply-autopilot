# Install Job Apply Autopilot V5.4

V5.4 uses trusted OpenCode subagents for parallel assessment, eligibility research, resume generation, and end-to-end external ATS applications. External applications have no skill-imposed numeric concurrency cap; LinkedIn Easy Apply remains coordinator-owned.

## 1. Replace the installed skill

Extract `job-apply-autopilot-v5.4.zip`, then run PowerShell from the extracted folder:

```powershell
$src = ".\job-apply-autopilot-v5.4"
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


V5.4 ships four hidden subagents under `agents/`. Install them globally:

```powershell
$skill = "$HOME\.config\opencode\skills\job-apply-autopilot"
pwsh -NoProfile -ExecutionPolicy Bypass -File "$skill\scripts\install-subagents.ps1"
```

This installs:

```text
~/.config/opencode/agents/job-autopilot-assessor.md
~/.config/opencode/agents/job-autopilot-eligibility.md
~/.config/opencode/agents/job-autopilot-resume.md
~/.config/opencode/agents/job-autopilot-external-apply.md
```

They are `hidden: true`, so they are intended for automatic Task invocation by the primary agent rather than normal `@` autocomplete. Restart OpenCode after installing them so the new agent definitions are loaded.

V5.4 intentionally gives all four packaged workers `edit: allow`. The external applicator additionally has BrowserOS access and final-submit authority for its assigned external ATS job. Assessor, eligibility, and resume workers still deny BrowserOS. Nested Task calls remain denied for every worker.

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

The assessor, eligibility, and resume workers deny BrowserOS. `job-autopilot-external-apply` explicitly allows BrowserOS for external ATS/company-site jobs. LinkedIn Easy Apply remains coordinator-owned.

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
      application-result.json     # external ATS workers
  domain-circuit-breakers/        # reactive per-domain markers
  applications.jsonl
  relocation-watchlist.jsonl
  domain-circuit-breakers.jsonl
```

## 7. How V5.4 parallelizes

The coordinator discovers/dedupes jobs and creates isolated work items. Independent stages fan out across jobs. Once a validated tailored resume exists, routing splits:

```text
Browser discovery / dedupe (coordinator)
        ↓
queue independent jobs
        ↓
assess / eligibility / resume workers fan out
        ↓
validated tailored resumes
        ├── LinkedIn Easy Apply → coordinator
        └── External ATS/company site → one external applicator per ready job
                                      (dispatch ALL ready jobs concurrently)
```

There is **no skill-imposed numeric limit** on concurrent external ATS application workers. OpenCode/runtime/system capacity is the natural limit. Each external worker owns one job, its own BrowserOS tabs, OAuth/login/form/upload/Submit flow, and writes `application-result.json` in that job directory.

Shared JSONL ledgers are still coordinator-written to avoid append races. A reactive domain circuit-breaker marker is checked immediately before final Submit; it does not impose a pre-emptive per-domain concurrency cap.

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


## V5.4 external ATS parallelism

The installer now installs four hidden subagents, including `job-autopilot-external-apply`. External ATS/company-site applications may be submitted end to end by those workers with no skill-imposed numeric concurrency cap. LinkedIn Easy Apply remains coordinator-owned.
