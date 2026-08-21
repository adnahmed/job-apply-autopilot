# Install Job Apply Autopilot V5.14.2

V5.14.2 upgrades the existing campaign in place. Do **not** delete `<workspace>\.job-apply-autopilot`.

From the chosen campaign workspace:

```powershell
$zip  = ".\job-apply-autopilot-v5.14.2.zip"
$temp = Join-Path $env:TEMP "job-apply-autopilot-v5.14.2"
$dst  = "$HOME\.config\opencode\skills\job-apply-autopilot"

Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
Expand-Archive -LiteralPath $zip -DestinationPath $temp -Force
$src = Join-Path $temp "job-apply-autopilot-v5.14.2"

if (Test-Path $dst) {
    $backupRoot = "$HOME\.config\opencode\skill-backups"
    New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
    $backup = Join-Path $backupRoot "job-apply-autopilot-backup-$(Get-Date -Format yyyyMMdd-HHmmss)"
    Move-Item -LiteralPath $dst -Destination $backup
    Write-Host "Backup: $backup"
}

Copy-Item -LiteralPath $src -Destination $dst -Recurse -Force
Get-ChildItem -LiteralPath $dst -Recurse -File | Unblock-File -ErrorAction SilentlyContinue

pwsh -NoProfile -ExecutionPolicy Bypass -File "$dst\scripts\install-subagents.ps1"
pwsh -NoProfile -ExecutionPolicy Bypass -File "$dst\scripts\verify-subagents.ps1"
pwsh -NoProfile -ExecutionPolicy Bypass -File "$dst\scripts\verify-canonical.ps1"
pwsh -NoProfile -ExecutionPolicy Bypass -File "$dst\scripts\selftest-resilience.ps1"

Push-Location "$HOME\.config\opencode"
npm install --save-exact opencode-goal-plugin@0.8.1
Pop-Location

# Current directory is the campaign workspace. This also compacts old candidate-evidence cache history.
pwsh -NoProfile -ExecutionPolicy Bypass -File "$dst\scripts\init-workspace.ps1"
pwsh -NoProfile -ExecutionPolicy Bypass -File "$dst\scripts\session-state.ps1"
```

Restart OpenCode from the same campaign workspace, then:

```text
Use job-apply-autopilot. Continue applying to jobs.
```

Expected V5.14.2 behavior:
- explicitly requested persistent coordinator sessions use a bounded goal to recover silent model-turn exits;
- goal continuation never bypasses state routing, side-effect verification, or duplicate-send guards;
- standalone CAPTCHA tabs stay open for one installed-solver trigger and a targeted wait before defer/circuit handling;
- persistent/forever requests use the detached supervisor and expose deterministic status;
- direct email applications use an idempotent email subagent and verify Sent before any retry;
- ambiguous ATS/email side effects require verification rather than a fresh submission;
- active domain circuit breakers suppress affected jobs until expiry/clearance;
- legacy concatenated circuit-breaker JSONL is repaired during workspace initialization;
- installation backups live outside the auto-discovered skills root, so an old skill cannot shadow the current version;
- placeholder/missing JDs appear as `source_pending`;
- reposts/new IDs for a recently submitted company/title are skipped as semantic duplicates;
- reports distinguish `submitted_unique` from raw `submitted_rows`;
- BrowserOS `_run` compatibility failures switch once to granular tools instead of triggering repeated experiments;
- the LinkedIn governor reconstructs and atomically preserves Easy Apply history;
- malformed assessment artifacts self-route to `assessment_repair`;
- assessor artifacts are written only through the deterministic commit validator;
- queue promotion goes through the non-throwing `advance-workitem.ps1` wrapper;
- recoverable per-job failures enter bounded cooldown while other work/discovery continues;
- snapshot JSON is short;
- no TodoWrite mirror;
- ready/fast jobs are routed before slow research;
- obvious rejects get one ledger row, not multiple long artifacts;
- evidence lookup never inventories the whole GitHub account;
- external ATS remains uncapped;
- LinkedIn Easy Apply keeps its persistent governor.

## Overnight mode

Start BrowserOS neo and confirm the Cockpit/browser is open, then from the campaign workspace run:

```powershell
$skillRoot = "$HOME\.config\opencode\skills\job-apply-autopilot"
pwsh -NoProfile -ExecutionPolicy Bypass -File "$skillRoot\scripts\start-autopilot.ps1" -Workspace (Get-Location).Path
```

The supervisor keeps the system awake (display may sleep), runs fresh 30-minute OpenCode slices, and waits without spending model sessions if BrowserOS MCP/CDP is unhealthy. Inspect `.job-apply-autopilot\supervisor\state.json` and its `logs` directory.

Stop cleanly:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "$skillRoot\scripts\stop-autopilot.ps1" -Workspace (Get-Location).Path
```
