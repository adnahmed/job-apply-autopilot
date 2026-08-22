---
description: Resolve one generated job's application route.
mode: subagent
hidden: true
temperature: 0.1
steps: 25
permission:
  read: allow
  bash:
    "*": allow
  task: deny
  question: deny
  "browseros-neo_*": allow
---

Accept one normal four-line work-item prompt with:

```
Workspace: <workspace>
Job ID: <job-id>
Kind: generated
Action: route_pending
```

Workflow:

Resolve work item via manifest:
```powershell
$manifest = pwsh -NoProfile -ExecutionPolicy Bypass -File "$HOME\.config\opencode\skills\job-apply-autopilot\scripts\get-workitem-manifest.ps1" `
  -Workspace "<workspace>" `
  -JobId "<job-id>" `
  -Kind generated |
  ConvertFrom-Json
```

Acquire `route_pending` with a 10-minute lease:
```powershell
$claim = pwsh -NoProfile -ExecutionPolicy Bypass -File "$HOME\.config\opencode\skills\job-apply-autopilot\scripts\claim-action.ps1" `
  -Action Acquire `
  -Scope WorkItem `
  -Stage route_pending `
  -WorkItemDir $manifest.work_item `
  -Workspace "<workspace>" `
  -LeaseMinutes 10 |
  ConvertFrom-Json
```

If not acquired (`acquired: false`), return `busy route_pending`. Retain `owner_id`.

Read job + source metadata + current application-route.
Resolve the actual employer/ATS destination.
If direct external:
call `set-application-route.ps1 -Route external`.
If LinkedIn Easy Apply:
call `set-application-route.ps1 -Route linkedin-easy-apply`.
If email:
call `set-application-route.ps1 -Route email`.
If authoritative inspection proves the route is only an aggregator/dead-end
with no employer/ATS destination:
write a terminal non-submission outcome using:
```powershell
write-application-outcome.ps1 `
    -Status skipped-job-quality `
    -Blocker "route-unresolvable-aggregator-only" `
    -ApplyMethod external `
    -Target "<observed-target>"
```
If route resolution exits without a transition that clears the claim, release using the same owner_id:
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "$HOME\.config\opencode\skills\job-apply-autopilot\scripts\claim-action.ps1" `
  -Action Release `
  -Scope WorkItem `
  -Stage route_pending `
  -WorkItemDir $manifest.work_item `
  -Workspace "<workspace>" `
  -OwnerId <owner_id>
```

A dead route worker must not leave the route locked for the default 90-minute claim duration.
Return one canonical line.