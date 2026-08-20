# BrowserOS Operational Playbook V5.7

## Purpose
Persist browser techniques that have already succeeded in real applications so workers do not rediscover them by trial and error.

## General rule
Prefer ordinary BrowserOS `snapshot`/`act`/`upload` operations. Use `evaluate` only when the normal interaction is blocked or a framework-controlled field does not accept reliable input. Never use these techniques to bypass CAPTCHA, MFA, anti-bot, or security controls.

## LinkedIn Easy Apply

### Resume upload
LinkedIn may keep old uploaded resumes and may select a stale file with the same generic name. Therefore:
1. compile a unique professional filename for every job,
2. surface the hidden `input[type=file]` only when the ordinary upload control cannot be targeted,
3. snapshot again so BrowserOS can obtain a ref for the surfaced input,
4. upload the unique job-specific PDF,
5. select that exact filename if LinkedIn creates a new resume radio entry,
6. verify the exact filename is selected immediately before Submit.

Observed workaround for a hidden input:
- remove the `hidden` class/attribute only from the relevant Easy Apply file input,
- set a clear `aria-label`,
- make it visible with a small inline box,
- snapshot,
- call `browseros-neo_upload` on the newly visible file-input ref.

Do not attempt CDP `DOM.getDocument` / `DOM.querySelector` / `DOM.setFileInputFiles`; these methods were unavailable in the observed BrowserOS environment.

### Covered buttons / overlays
When `browseros-neo_act` reports that a button/link is covered:
1. inspect the covering element and dismiss a legitimate banner/dialog if possible,
2. otherwise use `click_at` only when the target coordinates are known and the click is safe,
3. if a React/Vue control still does not receive the event, dispatch a normal pointer/mouse sequence on that exact element through `evaluate`,
4. re-snapshot and verify the expected UI state changed.

Never synthesize form submission or hidden security-token requests merely to bypass a blocked final Submit.

### Saved/draft applications
If LinkedIn says `Continue`, `Continue applying`, or Job Tracker shows a Draft:
1. treat it as a resumable Easy Apply flow rather than creating another application,
2. reopen the application modal from the job page,
3. verify contact data,
4. ALWAYS re-upload the current unique tailored PDF even if a resume is already selected,
5. complete remaining questions,
6. submit once,
7. verify through the confirmation UI or Job Tracker.

If LinkedIn shows `Save this application?`, choosing Save is acceptable when the modal must be exited/recovered.

## Lever

### Field-entry reliability
Observed behavior: generic fill operations can append or garble existing values on some Lever fields.

If that occurs, use the native `HTMLInputElement.prototype.value` setter on the exact input and dispatch normal `input` and `change` events. Re-read the field afterward. Do not keep repeating a failing fill action.

### OAuth/import
LinkedIn OAuth/import is preferred when offered. After import, verify important identity fields instead of assuming the imported display name/location is correct.

### Success signal
A `/thanks` page or explicit `Application submitted!` message is a strong confirmation. Persist the confirmation text/URL in `application-result.json`.

## Workable / Ashby / other ATS
Use ordinary controls where possible. If an ATS exposes an official public job-board endpoint that already establishes the exact requisition's location/eligible countries, use that evidence during eligibility research before opening a form.

## Timeouts
Heavy LinkedIn pages and browser download operations can time out. Prefer:
- targeted `read`/`snapshot` rather than repeated full-page reads,
- filesystem resume paths already produced by the resume worker rather than browser downloads,
- one fallback interaction method, then move on instead of cycling through many speculative techniques.
