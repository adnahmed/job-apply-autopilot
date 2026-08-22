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

Resolve work item.
Acquire `route_pending`.
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
Release claim if no transition cleared it.
Return one canonical line.

Do not leave a confirmed aggregator dead-end as route=unresolved forever.