# FreeHire Zero-Credit Integration Map

FreeHire is a deterministic accelerator and one discovery source. LinkedIn and browser discovery remain independent. The local canonical facts, TeX resumes, send guard, and application ledger are authoritative.

## Authentication and transport

Every request uses `scripts/freehire-client.ps1`. Credential precedence is `FREEHIRE_TOKEN`, `FREEHIRE_API_KEY`, then the official CLI file at `%USERPROFILE%\.freehire\creds.json`. Tokens are never accepted as command arguments, emitted, cached, or logged.

The runtime does not depend on the `freehire` binary or PATH. The CLI remains useful for manual `auth login`, status, and diagnostics. A missing or rejected credential degrades authenticated features to unavailable without stopping public discovery or any local/browser stage.

The client allowlists method/path pairs. Unknown endpoints and `CostClass=credit` return `policy-blocked` before network access. Do not bypass this client with direct authenticated HTTP calls.

## Automatic zero-credit calls

- Public discovery: `GET /agent/jobs/search`, `/jobs/facets`, `/jobs/{slug}`, `/similar`, `/copies`, `/apply-form`, `/jobs/find`, and `/insights/salary`.
- Deterministic fit: `GET /jobs/{slug}/match`, `POST /me/match-text`, and `POST /market/coverage`. These are evidence and priority signals, never pass/fail decisions.
- Candidate-authored data: `GET /me/autofill-profile` and `/me/screening-answers`. Local canonical values win; missing local fields may use non-conflicting FreeHire values with provenance.
- URL intake: `POST /jobs/resolve` only after local dedupe and only for public HTTP(S) vacancy URLs. Never send authenticated, private, local-network, or user-info URLs.
- Tracking: `POST /jobs/{slug}/apply` and `PATCH /jobs/{slug}/track` only after the local ledger records verified submission.
- Mail: `GET /me/gmail`, `POST /me/gmail/sync`, and `GET /me/inbox` only when Gmail is already connected and `mail_mode` is `optional-exact-match`.
- Cost audit: `GET /me/credits`, `/me/credits/history`, and `/me/usage`.

`GET /jobs/{slug}/match-analysis` may read an analysis that already exists. It never triggers analysis and is always stored as non-authoritative external evidence.

## Permanently excluded automatic calls

- `POST /jobs/{slug}/match-analysis` and its streaming variant.
- CV create, tailor, autopilot, edit, or render flows.
- Assistant sessions/messages/autopilot and speech.
- Experience-bank writes or merges.
- Referral requests/offers, Talent Network visibility, subscriptions, notifications, ghost reports, moderation, and job submissions.
- Gmail connect/disconnect, deletion, suggested-link acceptance, or unlinked-message application creation.

These surfaces consume credits, duplicate canonical state, require a browser session, make unrelated external assertions, or do not accelerate verified applications.

## Discovery and matching workflow

Cache facets before constructing dynamic filters. Geography is one OR group: regions, countries, and cities widen each other. Check `meta.ignored_params`; an ignored filter invalidates the claimed slice.

For a FreeHire result, persist its slug and complete source before calling enrichment. For another public source, call `/jobs/find`; if absent, `/jobs/resolve` may import it. A resolved slug unlocks copies, captured questions, match evidence, and remote tracking. If no slug exists, `/me/match-text` supplies deterministic skill coverage.

Prefer direct employer/ATS copies over LinkedIn and aggregators. Reality/ghost signals report observable behavior, not employer intent, and are never sole rejection grounds.

## Mail proof boundary

Only a message with all of the following may resolve an ambiguous reservation:

- deterministic `linked_slug` equal to the work item's stored FreeHire slug;
- stable non-empty `external_id`;
- recognized application signal other than `other`;
- receipt timestamp at or after the local send reservation;
- local send state already `verification-required` or `verification-quarantined`.

The context sync calls the send guard with proof kind `freehire-exact-linked-mail`; the send guard refuses that proof kind from every other caller. Suggested, unlinked, stale, or merely similar messages are telemetry only.

## Caching and failure behavior

Facets, market coverage, candidate data, match results, form captures, and route copies are cached. Identical requests share a content-derived cache key. HTTP 429 opens a short provider circuit; 401, 404, timeouts, malformed data, and provider failures return structured non-throwing statuses to callers. None may create a campaign blocker.

Telemetry stores endpoint path, query-key names, body hash, status, cache use, latency, and sanitized error code. It never stores authorization headers, tokens, request bodies, or raw mail bodies.
