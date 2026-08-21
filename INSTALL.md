# Install Job Apply Autopilot V5.15.1

V5.15.1 upgrades the existing campaign in place. Do **not** delete `<workspace>\.job-apply-autopilot`.

From the chosen campaign workspace:

```powershell
$zip  = ".\job-apply-autopilot-v5.15.1.zip"
$temp = Join-Path $env:TEMP "job-apply-autopilot-v5.15.1"
$dst  = "$HOME\.config\opencode\skills\job-apply-autopilot"

Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
Expand-Archive -LiteralPath $zip -DestinationPath $temp -Force
$src = Join-Path $temp "job-apply-autopilot-v5.15.1"

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

The npm command downloads the plugin but does **not** activate it by itself. Merge the `plugin` entry and `command.goal` object from `$dst\opencode-config-snippet.jsonc` into `$HOME\.config\opencode\opencode.json`. Preserve any existing plugins and commands. The resulting config must include:

```json
"plugin": [
  [
    "opencode-goal-plugin@0.8.1",
    {
        "maxTurns": 9007199254740991,
        "maxDurationMs": 9007199254740991,
        "maxTokens": 9007199254740991,
      "noProgressTokenThreshold": 1,
        "noProgressTurnsBeforePause": 9007199254740991,
      "noToolCallTurnsBeforePause": 0,
      "noInterruptOnUserMessage": true,
        "budgetWrapupRatio": 0.9999999999999999,
        "maxPromptFailures": 9007199254740991,
      "persistState": true
    }
  ]
],
"command": {
  "goal": {
    "description": "Set a session-scoped goal and auto-continue until complete.",
    "template": "$ARGUMENTS",
    "agent": "build"
  }
}
```

If `plugin` or `command` already exists, add to it rather than replacing it. Verify activation:

```powershell
opencode debug config
opencode debug agent goal
```

## Interactive use

Restart OpenCode from the campaign workspace. To make one interactive session auto-continue, use `/goal` as the prompt command:

```text
/goal "Use job-apply-autopilot. Keep discovering, assessing, tailoring, and submitting net-new job applications continuously until I explicitly run /goal pause or /goal stop." --max-turns 9007199254740991 --max-duration-ms 9007199254740991 --max-tokens 9007199254740991 --no-progress-threshold 1 --no-progress-turns 9007199254740991 --constraints "never duplicate a submission; verify every ambiguous prior side effect before retrying; never bypass CAPTCHA, MFA, security, eligibility, or truthfulness safeguards"
```

`/goal` creates the active session-scoped goal. The configured goal loop does not pause for ordinary steering messages. Use `/goal status` to inspect it; only `/goal pause` or `/goal stop` intentionally halts it. `/goal resume` starts a fresh local budget window after a safety/provider pause.

Do not type `/goal` when launching overnight mode below. The detached supervisor starts fresh bounded slices, and each slice creates its coordinator goal programmatically when the goal tools are available.

Expected V5.15.1 behavior:
- runnable generated and queue work is exposed together and dispatched in parallel worker waves;
- assessor, unified research, resume, external ATS, and email workers are uncapped by skill policy while LinkedIn remains serial;
- assessment stays local/web-free and one merged research finalizer handles only decision-changing eligibility/evidence uncertainty;
- an 8-job intake floor keeps discovery active without delaying ready work;
- explicitly requested persistent coordinator sessions keep a continuous goal active until `/goal pause` or `/goal stop`;
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
- the unified research finalizer performs at most one decision-critical lookup branch and avoids a third reassessment call;
- obvious rejects get one ledger row, not multiple long artifacts;
- optional evidence lookup never inventories the whole GitHub account;
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
