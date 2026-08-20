# Install Job Apply Autopilot V5.11.1

V5.11.1 upgrades the existing campaign in place. Do **not** delete `<workspace>\.job-apply-autopilot`.

From the chosen campaign workspace:

```powershell
$zip  = ".\job-apply-autopilot-v5.11.1.zip"
$temp = Join-Path $env:TEMP "job-apply-autopilot-v5.11.1"
$dst  = "$HOME\.config\opencode\skills\job-apply-autopilot"

Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
Expand-Archive -LiteralPath $zip -DestinationPath $temp -Force
$src = Join-Path $temp "job-apply-autopilot-v5.11.1"

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

# Current directory is the campaign workspace. This also compacts old candidate-evidence cache history.
pwsh -NoProfile -ExecutionPolicy Bypass -File "$dst\scripts\init-workspace.ps1"
pwsh -NoProfile -ExecutionPolicy Bypass -File "$dst\scripts\session-state.ps1"
```

Restart OpenCode from the same campaign workspace, then:

```text
Use job-apply-autopilot. Continue applying to jobs.
```

Expected V5.11.1 behavior:
- snapshot JSON is short;
- no TodoWrite mirror;
- ready/fast jobs are routed before slow research;
- obvious rejects get one ledger row, not multiple long artifacts;
- evidence lookup never inventories the whole GitHub account;
- external ATS remains uncapped;
- LinkedIn Easy Apply keeps its persistent governor.
