# Solver-Aware CAPTCHA Recovery

Use this only for a CAPTCHA/challenge page. The user has an external solver installed, so a challenge is not an instruction to close the tab immediately.

## One recovery window

1. Preserve the task-owned tab and its current URL. Do not navigate away or close it.
2. If an ordinary visible checkbox or challenge-start button such as `I'm not a robot`, `Verify`, or `Start` is available, click it once. This may trigger the installed solver.
3. If an image-grid challenge appears (e.g. reCAPTCHA "select all images with..."), do not solve the images yourself. Instead click the audio challenge control (the headphone/audio icon), then click the audio Play button once the audio challenge loads. Do not click image tiles or transcribe/submit the audio answer yourself — this only hands the challenge to the installed solver in its preferred format.
4. Wait up to 120 seconds for a targeted signal that the challenge disappeared, the form returned, navigation completed, or the expected next control appeared. Prefer one selector/text wait over repeated sleeps or clicks.
5. Take a fresh snapshot/read. If the challenge cleared, continue the form from the new state. Recheck the domain circuit immediately before final Submit.

## If it does not clear

- Do not click Submit again, refresh-loop, open alternate challenge endpoints, synthesize tokens, or inspect anti-bot internals.
- Leave the CAPTCHA tab open for the external solver/operator instead of treating it as disposable.
- Record `application-progress.json` stage `captcha-waiting` with the URL and observed challenge text when the worker can checkpoint.
- If Send/Submit definitely has not occurred, call `$HOME\.config\opencode\skills\job-apply-autopilot\scripts\application-send-guard.ps1 -Action CancelBeforeSubmit` with the work item and reservation ID, then call `$HOME\.config\opencode\skills\job-apply-autopilot\scripts\defer-workitem.ps1 -WorkItemDir <work-item> -Stage captcha-waiting -Code captcha-solver-pending`. The defer transition clears the actual active action claim even though `captcha-waiting` is a checkpoint stage.
- If Send/Submit may already have occurred, call `MarkAmbiguous`; the next action is verification, never another Send/Submit.
- A challenge that remains after this window or reappears after clearing counts as failed/repeated recovery. Record the affected domain through `domain-circuit-breaker.ps1 -Action Record` and stop that route.

MFA, account restrictions, explicit automation/security warnings, and attributable 429s do not receive this CAPTCHA recovery allowance; follow the normal security circuit policy immediately.
