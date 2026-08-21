# Install Job Apply Autopilot V5.13.0

V5.13.0 upgrades the existing campaign in place. Do **not** delete `<workspace>\.job-apply-autopilot`.

From the chosen campaign workspace:

```powershell
$zip  = ".\job-apply-autopilot-v5.13.0.zip"
$temp = Join-Path $env:TEMP "job-apply-autopilot-v5.13.0"
$dst  = "$HOME\.config\opencode\skills\job-apply-autopilot"

Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
Expand-Archive -LiteralPath $zip -DestinationPath $temp -Force
$src = Join-Path $temp "job-apply-autopilot-v5.13.0"

if (Test-Path $dst) {
    $backup = "$HOME\.config\opencode\skills\job-apply-autopilot-backup-$(Get-Date -Format yyyyMMdd-HHmmss)"
    Move-Item -LiteralPath $dst -Destination $backup
    Write-Host "Backup: $backup"
}

Copy-Item -LiteralPath $src -Destination $dst -Recurse -Force
Get-ChildItem -LiteralPath $dst -Recurse -File | Unblock-File -ErrorAction SilentlyContinue

pwsh -NoProfile -ExecutionPolicy Bypass -File "$dst\scripts\install-subagents.ps1"
pwsh -NoProfile -ExecutionPolicy Bypass -File "$dst\scripts\verify-subagents.ps1"
pwsh -NoProfile -ExecutionPolicy Bypass -File "$dst\scripts\verify-canonical.ps1"
pwsh -NoProfile -ExecutionPolicy Bypass -File "$dst\scripts\selftest-resilience.ps1"

# Current directory is the campaign workspace. This also compacts old candidate-evidence cache history.
pwsh -NoProfile -ExecutionPolicy Bypass -File "$dst\scripts\init-workspace.ps1"
pwsh -NoProfile -ExecutionPolicy Bypass -File "$dst\scripts\session-state.ps1"
```

Restart OpenCode from the same campaign workspace, then:

```text
Use job-apply-autopilot. Continue applying to jobs.
```

Expected V5.13.0 behavior:
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
