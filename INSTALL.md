# Install Job Apply Autopilot V5.10

V5.10 keeps the trusted parallel/external-apply architecture, authoritative continuation snapshot, persistent LinkedIn Easy Apply governor, and uncapped external ATS/company-site throughput. It adds dynamic first-party candidate evidence lookup, a reusable evidence cache, global-tenure + capability matching instead of years-per-skill gating, and interview-likelihood scoring that tolerates a few learnable stretches.

## 1. Replace the installed skill

Extract `job-apply-autopilot-v5.10.zip`, then run PowerShell from the extracted folder:

```powershell
$src = ".\job-apply-autopilot-v5.10"
$dst = "$HOME\.config\opencode\skills\job-apply-autopilot"

if (Test-Path $dst) {
    $backup = "$HOME\.config\opencode\skills\job-apply-autopilot-backup-$(Get-Date -Format yyyyMMdd-HHmmss)"
    Move-Item $dst $backup
}

Copy-Item -Recurse -Force $src $dst
Get-ChildItem -LiteralPath $dst -Recurse -File | Unblock-File -ErrorAction SilentlyContinue
```

Do **not** delete the `.job-apply-autopilot` directory inside your chosen workspace; keep the existing queue, ledgers, watchlist and generated artifacts.

## 2. Install/reinstall the trusted subagents

Always invoke packaged PowerShell scripts through `pwsh`:

```powershell
$skill = "$HOME\.config\opencode\skills\job-apply-autopilot"
pwsh -NoProfile -ExecutionPolicy Bypass -File "$skill\scripts\install-subagents.ps1"
pwsh -NoProfile -ExecutionPolicy Bypass -File "$skill\scripts\verify-subagents.ps1"
```

Installed hidden workers:

```text
job-autopilot-assessor
job-autopilot-evidence
job-autopilot-eligibility
job-autopilot-resume
job-autopilot-external-apply
```

All five remain trusted writers for their assigned job artifacts. `job-autopilot-external-apply` additionally has BrowserOS and final-submit authority for external ATS/company-site applications. LinkedIn Easy Apply stays coordinator-owned. External ATS workers have no skill-imposed concurrency cap.

Restart OpenCode after installing the agent definitions.

## 3. OpenCode permissions

If BrowserOS neo already works, keep the existing MCP configuration. The primary agent needs the skill, Task workers, and BrowserOS:

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "permission": {
    "skill": { "job-apply-autopilot": "allow" },
    "task": { "job-autopilot-*": "allow" },
    "browseros-neo_*": "allow"
  }
}
```

## 4. Verify canonical resumes

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "$skill\scripts\verify-canonical.ps1"
```

Both canonical `.tex` sources should report `OK`.

## 5. Initialize/upgrade the workspace

```powershell
# Run this from the workspace directory you chose for the campaign.
# The current directory is the workspace; do not substitute a hardcoded path.
$workspace = (Get-Location).Path
pwsh -NoProfile -ExecutionPolicy Bypass -File "$skill\scripts\init-workspace.ps1" -Workspace "$workspace"
```

For continuation sessions, V5.10 uses one authoritative, stage-aware state decision instead of reconstructing campaign state manually:

```powershell
$workspace = (Get-Location).Path
pwsh -NoProfile -ExecutionPolicy Bypass -File "$skill\scripts\session-state.ps1" -Workspace "$workspace"
```

The JSON returns one `next_action` (`reconcile`, `resume-generated`, `process-queue`, or `discover`), `action_paths`, and stage-aware `actions`. The coordinator follows `actions[].stage` directly instead of opening directories merely to rediscover whether assessment, eligibility research, resume generation, or application routing is pending. In particular, `next_action: "discover"` means it must begin job discovery immediately—no queue/generated enumeration, ledger tailing, Glob search, alternate-path probing, or inspection of `session-state.ps1`.

The coordinator treats `<current-directory>\.job-apply-autopilot` as the single runtime tree. The current directory at skill start is authoritative; it must not scan home directories or guess alternate workspace locations.

V5.10 runtime structure:

```text
.job-apply-autopilot/
  queue/
    <job-id>-<slug>/
      job.json
      source.md
      assessment.json
      fit-map.json
      eligibility-research.json      # optional
      candidate-evidence-research.json # optional live technical evidence
  generated/
    <job-id>-<slug>/
      job.json
      assessment.json
      fit-map.json
      tailoring-audit.json
      canonical-source.tex
      resume.tex
      resume.pdf                      # compile intermediate
      resume.precompact.tex           # only if compact fallback used
      Adnan_Ahmed_Khan_<Company>_<Role>.pdf
      resume-artifact.json            # exact PDF path/name/hash to upload
      application-progress.json       # external ATS checkpoint
      application-result.json         # external ATS terminal result
  domain-circuit-breakers/            # reactive marker files
  applications.jsonl
  relocation-watchlist.jsonl
  domain-circuit-breakers.jsonl
  campaign-stats.json
  linkedin-activity-state.json       # persistent rolling Easy Apply governor
  candidate-evidence.json            # reusable verified public technical evidence cache
```

## 6. Live candidate evidence

V5.10 does not hardcode a project list. Candidate GitHub/LinkedIn identities are read from `canonical/canonical-facts.yaml`; when a technical gap would otherwise cause rejection, `job-autopilot-evidence` dynamically discovers current first-party repositories/deployments/public posts relevant to that requirement.

Evidence workers write per-job reports only. Merge a completed report sequentially:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "$skill\scripts\merge-candidate-evidence.ps1" `
  -EvidenceFile "<queue-job>\candidate-evidence-research.json"
```

Then re-run the assessor. Overall engineering tenure is derived from canonical employment history; the skill does not maintain years-per-technology counters.

## 7. Resume compilation

MiKTeX CLI should expose `pdflatex`; `latexmk` is optional. The compiler automatically falls back to two direct `pdflatex` passes if `latexmk` exists but fails.

```powershell
pdflatex --version
latexmk -v
```

Resume workers call:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "$skill\scripts\compile-resume.ps1" `
  -TexPath "<generated-job>\resume.tex" `
  -StrictOnePage `
  -AutoCompact
```

If a first compile is over one page, `-AutoCompact` permits one layout-only fallback learned from the successful Conquer run: preserve `resume.precompact.tex`, remove `\vfill`, and tighten itemized spacing to 2pt. It never changes factual content. If the result is still over one page, compilation fails rather than shrinking indefinitely.

The application-facing file is **not** generic `resume.pdf`. The compiler creates a unique professional file plus `resume-artifact.json`; LinkedIn/ATS workers must upload that exact artifact.

## 8. ATS eligibility adapters

Read-only adapter guidance lives in:

```text
references/ats-eligibility-adapters.md
```

Observed high-value patterns include:

- Workable public widget data: exact requisition repeated across a closed country list.
- Ashby public job-board posting API: exact role location such as `Remote (Europe)`.
- Lever: exact job location/scope plus screening evidence; an address field accepting Pakistan is not by itself eligibility proof.

Use official structured evidence before opening an application when it can settle the geographic gate cheaply.

## 9. BrowserOS playbook

Real-world browser techniques are persisted in:

```text
references/browseros-playbook.md
```

It covers:

- recovering LinkedIn Easy Apply drafts,
- surfacing hidden file inputs,
- verifying the unique selected resume filename,
- covered-button interaction fallbacks,
- Lever field setter workaround,
- known unavailable CDP DOM methods,
- timeout behavior.

## 10. External ATS checkpointing

`job-autopilot-external-apply` now has a larger step budget and maintains `application-progress.json` after important stages. If a worker is re-dispatched, it resumes from the last verified state. If the last checkpoint is `submit-clicked`, it verifies success before ever clicking Submit again.

This prevents a worker step limit from causing duplicate submissions or forcing the coordinator to reconstruct the entire flow.


## 11. LinkedIn Easy Apply governor

LinkedIn Easy Apply is deliberately separate from external ATS throughput. External ATS/company-site applications have **no skill-imposed per-run, daily, or concurrency limit**.

Check the persistent governor:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "$skill\scripts\linkedin-governor.ps1" `
  -Action Status `
  -Workspace "$workspace"
```

After a **confirmed** Easy Apply submission:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "$skill\scripts\linkedin-governor.ps1" `
  -Action RecordEasyApply `
  -Workspace "$workspace"
```

Default skill-owned Easy Apply pacing is 4 confirmed submissions per rolling hour, 20 per rolling 24 hours, and at least 600 seconds between confirmed submissions. These are conservative job-apply-autopilot defaults, not claimed LinkedIn platform limits. If the governor pauses Easy Apply, the coordinator continues external applications and other campaign work.

On a LinkedIn 429/security/CAPTCHA/MFA/account-restriction signal, record it with `-Action RecordSignal -SignalType <type>`. Ordinary rate-limit/security warnings create a 24-hour LinkedIn cooldown; CAPTCHA/MFA/account restrictions create a manual LinkedIn block. External ATS remains unaffected.

## 11. Batch dedupe helper

Instead of grepping the ledger or enumerating queue/generated folders during discovery, batch candidate IDs through:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "$skill\scripts\dedupe-jobs.ps1" `
  -JobIdsCsv "4450000001,4450000002,4450000003" `
  -Workspace "$workspace"
```

Only unseen IDs should become new work items.

## 12. Campaign analytics

Refresh analytics after meaningful new outcomes:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "$skill\scripts\update-campaign-stats.ps1" `
  -Workspace "$workspace"
```

This writes:

```text
.job-apply-autopilot/campaign-stats.json
```

New work items can record `-DiscoveryLane` and `-SearchQuery`; that metadata is carried into generated job folders. Analytics can shift future discovery effort toward productive lanes, but never relaxes integrity, eligibility, truth, or fit gates.

## 13. Recommended command

```text
Use job-apply-autopilot. Continue applying to jobs.
```

## V5.10 workspace-safe initialization

When the shell is already in the chosen campaign workspace, prefer omitting `-Workspace` entirely:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "$dst\scripts\init-workspace.ps1"
pwsh -NoProfile -ExecutionPolicy Bypass -File "$dst\scripts\session-state.ps1"
```

All workspace-aware scripts also defensively treat an explicitly empty `-Workspace` value as the caller's current directory.
