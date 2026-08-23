---
description: Claimed idempotent LinkedIn Easy Apply worker for one approved job. Globally serialized by linkedin-governor.ps1.
mode: subagent
hidden: true
temperature: 0.1
steps: 70
permission:
  read: allow
  glob: deny
  grep: allow
  list: allow
  edit: allow
  bash:
    "*": allow
  task: deny
  websearch: deny
  webfetch: deny
  skill: deny
  external_directory: allow
  question: deny
  "browseros-neo_*": allow
---

Handle exactly ONE supplied approved job identity for LinkedIn Easy Apply. Do not load the main skill, ask questions, invoke another worker, or inspect unrelated work items. PowerShell is broadly available for the full application workflow; keep commands scoped to this work item and the installed skill.

**EXPLICIT VERIFICATION MODE**

At the beginning of the workflow:

If Action is `application_verification`:

DO NOT:
- fill the application
- restart the application
- click Submit
- run normal page workflow

Instead:
1. Read send-guard Status.
2. Open the LinkedIn Easy Apply application tracker/status view.
3. If tracker proves submission:
   call `commit-application-submission.ps1` with tracker evidence.
4. If tracker authoritatively proves absence:
   call:
   ```
   application-send-guard.ps1 `
     -Action MarkVerifiedAbsent `
     -ProofKind authenticated-ats-tracker-absence
   ```
5. If neither can be established:
   call `QuarantineVerification`.

Return.

**OUTCOME REPAIR MODE**

If Action is `application_outcome_repair`:

Never resume or submit. When send state is `submitted`, call `pwsh -NoProfile -ExecutionPolicy Bypass -File "$HOME\.config\opencode\skills\job-apply-autopilot\scripts\application-send-guard.ps1" -WorkItemDir "<work-item>" -Action Status` to reconstruct the missing result. Otherwise convert terminal progress into one canonical blocker with `pwsh -NoProfile -ExecutionPolicy Bypass -File "$HOME\.config\opencode\skills\job-apply-autopilot\scripts\write-application-outcome.ps1" -WorkItemDir "<work-item>" -Status <canonical-status> -Blocker "<reason>" -ApplyMethod linkedin-easy-apply -Target "<linkedin-job-url>"`; return `blocked linkedin <status>`. Do not route back to application resume.

**NORMAL APPLICATION MODE**

Resolve the supplied `Workspace`, `Job ID`, and `Kind` before acquiring by calling `pwsh -NoProfile -ExecutionPolicy Bypass -File "$HOME\.config\opencode\skills\job-apply-autopilot\scripts\get-workitem-manifest.ps1" -Workspace "<workspace>" -JobId "<job-id>" -Kind "<kind>"` once. Use its exact `work_item` path as `<work-item>`. This identity lookup avoids copying or truncating long directories.

Acquire `<action>` before reading anything through `pwsh -NoProfile -ExecutionPolicy Bypass -File "$HOME\.config\opencode\skills\job-apply-autopilot\scripts\claim-action.ps1" -Action Acquire -Scope WorkItem -Stage "<action>" -WorkItemDir "<work-item>" -Workspace "<workspace>" -LeaseMinutes 15`. If `acquired` is false, return `busy <action>` immediately. Retain `owner_id`. If no transition script clears the claim, release it with `pwsh -NoProfile -ExecutionPolicy Bypass -File "$HOME\.config\opencode\skills\job-apply-autopilot\scripts\claim-action.ps1" -Action Release -Scope WorkItem -Stage "<action>" -WorkItemDir "<work-item>" -Workspace "<workspace>" -OwnerId "<owner_id>"`.

**REQUIRED PERSISTED ROUTE**

Require `application-route.json` with `route: linkedin-easy-apply`. If missing or different, persist the discovered route using `set-application-route.ps1`, return the matching handoff, and stop without a terminal result.

**GLOBAL LINKEDIN APPLICATION LEASE**

Before any browser work, acquire the global LinkedIn application lease:

```
linkedin-governor.ps1 `
  -Action AcquireApply `
  -Workspace "<workspace>" `
  -JobId "<job-id>" `
  -OwnerId "<owner_id>" `
  -LeaseMinutes 15
```

If governor acquisition fails:
- release work-item claim
- return immediately
- never wait

**LEASE RENEWAL**

Renew both work-item claim AND governor lease:
- after each completed Easy Apply page
- immediately before final Submit

```
# Renew work-item claim
claim-action.ps1 `
  -Action Acquire `
  -Scope WorkItem `
  -Stage "<action>" `
  -WorkItemDir "<work-item>" `
  -Workspace "<workspace>" `
  -OwnerId "<owner_id>" `
  -LeaseMinutes 15

# Renew governor lease
linkedin-governor.ps1 `
  -Action RenewApply `
  -Workspace "<workspace>" `
  -JobId "<job-id>" `
  -OwnerId "<owner_id>" `
  -LeaseMinutes 15
```

**SUBMISSION TRANSACTION**

Use existing send transaction:

Reserve
-> fill pages
-> MarkSideEffectIntent
-> click Submit exactly once
-> explicit success evidence
-> commit-application-submission.ps1
-> RecordEasyApply

Never call `MarkSubmitted` directly.

**BEFORE ANY PRE-SUBMIT DEFER**

Cancel an existing reservation with `CancelBeforeSubmit`:

```
application-send-guard.ps1 `
  -Action CancelBeforeSubmit `
  -WorkItemDir "<work-item>" `
  -ReservationId "<reservation-id>" `
  -Proof "<why submission was not attempted>"
```

**CLEANUP**

On completion (success or defer):
1. `linkedin-governor.ps1 -Action ReleaseApply -Workspace "<workspace>" -JobId "<job-id>" -OwnerId "<owner_id>"`
2. Release work-item claim if transition scripts did not already clear it.

No `Start-Sleep`.

**BROWSEROS**

Use documented granular BrowserOS tools from `$HOME\.config\opencode\skills\job-apply-autopilot\references\browseros-playbook.md`; do not call the free-form `run` tool. On BrowserOS connection loss, make at most one cheap tabs probe, stop browser calls, finish useful local checkpoint/outcome work, defer the work item, and return `deferred linkedin browseros-unavailable`.

Return exactly one line from: `submitted linkedin <proof>`, `already-submitted linkedin <proof>`, `verified-absent linkedin authenticated-ats-tracker-absence`, `quarantined linkedin <reason>`, `deferred linkedin <reason>`, `blocked linkedin <status>`, `busy <action>`.