# BrowserOS Operational Playbook V6.0

Use this reference only when browser work is active or a BrowserOS action fails. It restores the working techniques accidentally removed in V5.11.4.

## Session and tab ownership

- Name the BrowserOS session once.
- Open task-owned tabs with `tabs new`; never reuse a page ID copied from state, logs, another worker, or an earlier worker turn.
- A `page ... is not owned by this agent` response is expected isolation, not a transient error. Open the URL in a new owned tab immediately; do not retry the foreign page.
- Open only task-owned tabs that are useful now and close disposable tabs promptly. There is no skill numeric tab cap, but each worker should normally need one application tab. Never close a tab whose CAPTCHA solver is pending or whose side effect still needs verification.

## Granular tool path

Use the tools and argument schemas available in the current session; do not infer an older API from examples.

Use granular `snapshot`/`read`/`act`/`upload` tools. Do not call free-form `run`; observed output-schema incompatibilities make it less reliable than the granular interface.

For discovery, one targeted page-context extraction is allowed. If it fails, switch to `read` or `snapshot`; do not keep rewriting equivalent extraction code.

Do not call raw CDP methods such as `Page.getFrameTree`, `DOM.getDocument`, `DOM.enable`, `DOM.querySelector`, or `DOM.setFileInputFiles`. They are unavailable in the observed BrowserOS neo environment. Do not use Node globals such as `require`, and do not assume `document` exists outside BrowserOS's page-context evaluation API.

## Connection loss is a browser-route outage

`Unable to connect`, `CDP connection lost`, a failed `tabs list`, or owned tabs suddenly disappearing means the browser route is unavailable. An OAuth/popup click that resets the session or removes the owned tab is the same outage, not permission to repeat the click.

- After the first timeout, make one cheap granular health probe (`tabs list` or `tabs new`).
- If that probe reports connection/CDP loss or the owned tab remains gone, stop browser calls for the worker turn. Do not retry the triggering OAuth/popup interaction or wrap it in `_run`. Continue any already-available local assessment, resume, reconciliation, or logging work.
- Persist the current job as recoverable when needed and return. Do not describe this as campaign completion or market exhaustion.
- After all useful local work is exhausted, block the active session goal with the concrete BrowserOS failure. Restore BrowserOS, then use `/goal resume`.

The MCP server can remain alive while the browser/CDP process is dead. A running `browseros-claw-server` process alone is not proof of health.

## Resume upload

Call `upload` only with a fresh accessibility ref such as `e42` that resolves to an actual `<input type="file">`. Never invent a ref name.

For a persistent hidden input:

1. use a page-context evaluation to remove only that input's hidden class/attribute and give it a clear `aria-label`;
2. snapshot again to obtain a fresh ref;
3. call `upload` with the fresh ref and the exact PDF from `resume-artifact.json`;
4. verify the displayed filename/selected resume before Submit.

If a site opens a native chooser but exposes no persistent file input, BrowserOS's ref-based upload has no agent-native path (upstream issue #2156). Do not experiment with unavailable CDP DOM methods or pretend the tailored file attached.

For LinkedIn only, after one tailored-upload fallback fails, an already uploaded resume may be used only when its identity/content is known to be a truthful canonical resume suitable for the role family. Record `resume_fallback=verified-existing`. If the selected file is unknown or stale, save/defer that job and continue; never claim the tailored artifact was submitted.

## LinkedIn Easy Apply

- Check `linkedin-governor.ps1 -Action Status` before opening a new application.
- A `Continue`/Draft state is resumable, not a new application.
- Verify contact fields and the selected resume immediately before Submit.
- Submit once, verify explicit confirmation or Job Tracker state, call the send guard `MarkSubmitted`, then call `RecordEasyApply -JobId <id>`; reconciliation writes the ledger.
- A governor cooldown never blocks external ATS work or discovery.

## Covered controls and framework fields

When `act` says a target is covered, dismiss the legitimate overlay/banner and use a fresh snapshot. If the target remains covered, use `click_at` only when coordinates and intent are unambiguous. One page-context pointer/mouse event fallback on the exact element is allowed for a framework control. Never synthesize a hidden final form submission.

If a Lever/framework field appends or garbles text, use the native value setter on the exact field and dispatch ordinary `input` and `change` events once, then read it back.

## Timeouts and proof

- Wait for expected text/selector, not repeated fixed sleeps.
- Prefer targeted reads over repeated full-page snapshots.
- Treat a tool diff as verification when it shows the expected state.
- A `/thanks` URL or explicit `Application submitted/sent` message is strong proof. Persist that exact text/URL.
- A standalone CAPTCHA uses `captcha-recovery.md`: keep the tab open, trigger the installed solver once when appropriate, and wait up to 120 seconds for a targeted cleared state. It is not an immediate circuit-breaker by itself.
- MFA, account restriction, spam/automation warnings, attributable 429s, failed solver recovery, and a repeated CAPTCHA remain zero-Submit-retry security signals for the affected domain only.

## Ambiguous side effects

- Before any external Submit or email Send, acquire a reservation through `application-send-guard.ps1`.
- If the browser diff/result is ambiguous after the click, mark the reservation ambiguous and stop. A new worker verifies the real ATS/Sent state first.
- Missing local result/progress files never prove the side effect did not happen.
- Only authenticated ATS tracker absence or an exact authenticated Gmail Sent search may clear an ambiguous reservation. When that evidence is unavailable, quarantine the verification.
- Gmail application email uses the dedicated email worker. Do not inject diagnostic inputs/overlays or toggle formatting modes in Gmail.
