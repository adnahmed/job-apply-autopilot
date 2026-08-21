# Install Job Apply Autopilot V6.0.0

V6 upgrades an existing campaign in place. Do not delete `<workspace>\.job-apply-autopilot`. Terminate any active V5 background campaign process before installing; V6 does not start or manage OS background processes.

From the campaign workspace:

```powershell
$zip  = ".\job-apply-autopilot-v6.0.0.zip"
$temp = Join-Path $env:TEMP "job-apply-autopilot-v6.0.0"
$dst  = "$HOME\.config\opencode\skills\job-apply-autopilot"

Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
Expand-Archive -LiteralPath $zip -DestinationPath $temp -Force
$src = Join-Path $temp "job-apply-autopilot-v6.0.0"

if (Test-Path -LiteralPath $dst) {
    $backupRoot = "$HOME\.config\opencode\skill-backups"
    New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
    $backup = Join-Path $backupRoot "job-apply-autopilot-backup-$(Get-Date -Format yyyyMMdd-HHmmss)"
    Move-Item -LiteralPath $dst -Destination $backup
}

Copy-Item -LiteralPath $src -Destination $dst -Recurse -Force
Get-ChildItem -LiteralPath $dst -Recurse -File | Unblock-File -ErrorAction SilentlyContinue

pwsh -NoProfile -ExecutionPolicy Bypass -File "$dst\scripts\install-subagents.ps1"
pwsh -NoProfile -ExecutionPolicy Bypass -File "$dst\scripts\verify-subagents.ps1"
pwsh -NoProfile -ExecutionPolicy Bypass -File "$dst\scripts\verify-canonical.ps1"

Push-Location "$HOME\.config\opencode"
npm install --save-exact opencode-goal-plugin@0.8.1
Pop-Location

pwsh -NoProfile -ExecutionPolicy Bypass -File "$dst\scripts\init-workspace.ps1" -Workspace (Get-Location).Path
pwsh -NoProfile -ExecutionPolicy Bypass -File "$dst\scripts\session-state.ps1" -Workspace (Get-Location).Path
```

The npm command downloads the plugin but does not activate it. Merge the `plugin` and `command.goal` entries from `opencode-config-snippet.jsonc` into `$HOME\.config\opencode\opencode.json`, preserving other entries. The plugin options must include:

```json
{
  "maxTurns": 9007199254740991,
  "maxDurationMs": 9007199254740991,
  "maxTokens": 9007199254740991,
  "noProgressTokenThreshold": 1,
  "noProgressTurnsBeforePause": 9007199254740991,
  "noToolCallTurnsBeforePause": 0,
  "noInterruptOnUserMessage": true,
  "noContinueWhileChildrenActive": true,
  "budgetWrapupRatio": 0.9999999999999999,
  "maxPromptFailures": 9007199254740991,
  "persistState": true
}
```

Confirm OpenCode can see the merged configuration:

```powershell
opencode debug config
opencode debug agent goal
```

## Start a continuous campaign

BrowserOS neo, its signed-in profile, network access, and OS keep-awake behavior are managed outside this repository. Restart OpenCode from the campaign workspace and create one session goal:

```text
/goal "Use job-apply-autopilot. Keep discovering, assessing, tailoring, and submitting net-new job applications until I explicitly run /goal pause or /goal stop." --max-turns 9007199254740991 --max-duration-ms 9007199254740991 --max-tokens 9007199254740991 --no-progress-threshold 1 --no-progress-turns 9007199254740991 --constraints "never duplicate a submission; verify ambiguous side effects before retrying; never bypass CAPTCHA, MFA, security, eligibility, or truthfulness safeguards"
```

Use `/goal status`, `/goal pause`, and `/goal stop` for lifecycle control. Persisted goals load paused after an OpenCode restart; restore BrowserOS if needed, then run `/goal resume`. Do not create a second persistence loop.

## Resolve verification quarantine

List isolated ambiguous applications:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "$dst\scripts\resolve-application-quarantine.ps1" -Action List -Workspace (Get-Location).Path
```

For a returned generated work-item path, use one action:

```powershell
# Permit another authoritative verification pass; never authorizes Submit.
pwsh -NoProfile -ExecutionPolicy Bypass -File "$dst\scripts\resolve-application-quarantine.ps1" -Action Reverify -WorkItemDir '<path>' -Workspace (Get-Location).Path

# Record the user's knowledge of the prior side effect.
pwsh -NoProfile -ExecutionPolicy Bypass -File "$dst\scripts\resolve-application-quarantine.ps1" -Action ConfirmSubmitted -WorkItemDir '<path>' -Proof '<what confirms it>' -Workspace (Get-Location).Path
pwsh -NoProfile -ExecutionPolicy Bypass -File "$dst\scripts\resolve-application-quarantine.ps1" -Action ConfirmAbsent -WorkItemDir '<path>' -Proof '<what confirms absence>' -Workspace (Get-Location).Path

# Reopen only a guarded proven pre-submit/cancelled or verified-absent blocker.
pwsh -NoProfile -ExecutionPolicy Bypass -File "$dst\scripts\resolve-application-quarantine.ps1" -Action RetryApplication -WorkItemDir '<path>' -Workspace (Get-Location).Path

# Close with an explicitly unknown outcome; this never claims submission or absence.
pwsh -NoProfile -ExecutionPolicy Bypass -File "$dst\scripts\resolve-application-quarantine.ps1" -Action Abandon -WorkItemDir '<path>' -Proof '<why it remains unknowable>' -Workspace (Get-Location).Path
```

No runtime data or legacy ledger row is automatically migrated by installation.

## Expected V6 behavior

- One goal owns continuation; workers never create goals and a coordinator continuation is withheld while child workers remain active.
- Every continuation reruns `session-state.ps1`; runnable generated and queue work remains visible together and is dispatched in parallel waves.
- Assessor, research, resume, external ATS, and email work is limited only by host capacity; LinkedIn Easy Apply remains serial under its persistent governor.
- The eight-job intake floor refills discovery without delaying ready work, and complete JDs route through `source_pending` before assessment.
- Assessment is local/web-free unless one bounded decision-changing research branch is explicitly requested.
- Claims suppress duplicate stage owners, expire after abandonment, and are cleared by completed transitions.
- Assessment, promotion, compilation, outbound reservation, terminal outcome writing, and result reconciliation are idempotent boundaries.
- Missing or ambiguous outbound receipts never authorize a retry. Authoritative absence proof is channel-specific; unavailable verification becomes isolated quarantine.
- Quarantined jobs create no ledger row, do not count as submitted/skipped, and do not consume discovery capacity.
- Semantic company/title dedupe prevents repost or new-ID duplicate submissions; reports distinguish `submitted_unique` from raw `submitted_rows`.
- Standalone CAPTCHA recovery gets one installed-solver window; MFA, security, automation, and repeated challenge signals remain route-local stops.
- BrowserOS connection loss stops browser calls, not local work or unrelated jobs. When no useful local work remains, the goal blocks until BrowserOS restoration and `/goal resume`.
- Malformed assessments route to deterministic repair; terminal application progress without a result routes only to outcome repair.
- Installation backups remain outside the auto-discovered skills root, and canonical resume sources remain immutable.
