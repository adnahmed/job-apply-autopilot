# V6.10.0 — Durable Pre-Submit Intent, Resumable Reservations, and Idempotent Submission Commit

- fixed work-item claims being ignored when scheduler stage changed mid-worker
- separated safe in-progress reservations from possible-submit states
- added durable pre-submit/send intent state (`side-effect-intent`)
- made crashed pre-submit applications safely resumable (`resume-reservation`)
- added idempotent local submission-result commit retry (`commit-application-submission.ps1`)
- prevented persistence failures from causing a second browser Submit
- added explicit external verification-only workflow (`application_verification` action)
- applied side-effect-intent protocol to email and LinkedIn submission paths
- shortened email application claim lease from 45 to 15 minutes
- fixed semantic answer bank documentation: `application-semantic-answers.json` vs `application-answer-plan.json`

# V6.9.0 — Semantic Answer Bank, Explicit Final Submission, Shortened Claims, Enrichment Sync

- fixed undefined ProfilePath in application preflight
- stopped preflight resolver failures from masquerading as ready
- added persistent per-job semantic application answer bank
- added explicit final Submit -> MarkSubmitted applicator transaction
- shortened external application stale-claim recovery with periodic renewal
- synchronized late asynchronous FreeHire enrichment into promoted generated items
- hardened route resolver failure handling

# V6.8.0 — Bounded Dispatch, Parallel Route Resolution, and Continuous Discovery

- Fixed resume workers exhausting the 10-step ceiling before compilation by increasing steps to 40 and adding one-call resume context loading via `get-resume-context.ps1`
- Shortened stale resume claim lease from 30 to 10 minutes; shortened LinkedIn discovery lease from 60 to 15 minutes (matching FreeHire)
- Changed LinkedIn discovery to smaller continuous batches (target 4 instead of 8) with immediate claim release after each batch
- Moved FreeHire discovery into a normal background worker (`job-autopilot-freehire-discovery`) instead of a detached PowerShell process
- Bounded scheduler dispatch waves to 8 actions per turn via `$maxDispatchActionsPerSnapshot` with `dispatch_manifest` metadata; coordinator reruns state after each wave
- Removed coordinator canonical-resume adjudication: assessor writes `canonical_resume` (ai|backend) to `assessment.json`; `advance-workitem.ps1` reads it automatically
- Moved route resolution into parallel background workers (`job-autopilot-route-resolver`) instead of coordinator-browser serial work
- Prevented confirmed aggregator-only routes from looping forever as `route_pending`: route resolver writes terminal `skipped-job-quality` outcome with `route-unresolvable-aggregator-only` blocker
- Added `canonical_resumes` to `assessment-schema.json` with allowed values `ai` and `backend`
- Changed passed assessment next_stage from `coordinator_adjudication_pending` to `promotion_pending`; assessor immediately calls `advance-workitem.ps1`
- Added `route_pending` to stages cleared by `write-application-outcome.ps1`
- Removed `scripts/start-freehire-discovery.ps1` (no longer needed; background Task provides async boundary)
- Fixed resume worker double-acquiring resume_pending and busying itself
- Fixed missing Has-Property helper in get-resume-context.ps1
- Made get-resume-context the single resume identity/claim/context entrypoint
- Released resume claims immediately on context validation errors
- Removed redundant generated-directory scanning from resume context loading
- Stopped recompiling already verified ready resume artifacts
- Made route-resolver claim lease explicit at 10 minutes
- Removed stale shared-discovery compact metadata

# V6.7.0 — Dedupe & Enrichment Pipeline Optimization

- Removed duplicate FreeHire quality evaluation: discovery now relies on single authoritative check inside `finalize-discovered-workitem.ps1` → `new-workitem.ps1` → `check-job-quality.ps1`.
- Removed redundant new-workitem filesystem scan: exact-ID and semantic dedupe now single-sourced from `dedupe-jobs.ps1`; `existing` returned for exact matches, `duplicate` for semantic.
- Moved FreeHire enrichment off the discovery/finalization critical path: `finalize-discovered-workitem.ps1` now creates work item + writes route synchronously, then launches `start-freehire-enrichment.ps1` asynchronously; returns `enrichment_status: started` immediately.
- Removed non-authoritative match-analysis from normal enrichment hot path: saves one FreeHire API round-trip per job.
- Avoided duplicate FreeHire copy lookups: enrichment now reuses `source-metadata.json.copies` when present.
- Changed ATS answer resolution to one resolver invocation per page: `resolve-application-answer.ps1` now supports batch mode (`-QuestionsJson`); `resolve-application-page.ps1` and `preflight-application.ps1` use it; a 20-field page requires one PowerShell call instead of 20.
- Reduced external applicator runaway step budget: `steps: 120` → `70`.
- Preflight semantic answers generated once and reused during live page resolution.

# V6.6.0 — Asynchronous Parallel Discovery & Page-Level Batch Resolution

- Made FreeHire discovery asynchronous: coordinator launches `start-freehire-discovery.ps1` and immediately continues scheduling; FreeHire runs as detached background process with its own source-specific claim.
- Parallelized independent FreeHire search lanes (home-country, global-remote, sponsorship) using `ForEach-Object -Parallel -ThrottleLimit 3`; lanes run concurrently, merge after all return.
- Routed FreeHire persistence through atomic `finalize-discovered-workitem.ps1` only; removed direct `new-workitem.ps1`, `set-application-route.ps1`, `enrich-freehire-workitem.ps1`, and source file writes from discovery script.
- Added page-level batch application answer resolution: `resolve-application-page.ps1` resolves all visible ATS page fields in one PowerShell call; external applicator uses single page resolution + one semantic pass + one batched fill + one validation per page.
- Removed candidate-specific geography (Pakistan, Islamabad, PK, etc.) from executable logic in `discover-freehire.ps1`, `resolve-application-answer.ps1`; replaced with profile-derived values (`candidate.location.country_code`, `local_location_tokens_csv`, `local_unlabeled_numeric`, `local_currency`, `local_period`, `local-market-default`).
- Added `Test-LocalJobLocation` helper using profile-configured location tokens for generic local-market detection.
- Fixed stale shared-discovery scheduler accounting: `claims_active` now sums source-specific active claims; `next_action` derived from emitted actions (`dispatch`, `await-active-claims`, `idle`).
- Added active FreeHire and LinkedIn discovery claims to `state.claims` output with `discovery_source` field.
- FreeHire lanes now use dynamic home-country from `profile.yaml` (`candidate.location.country_code`); no hardcoded `PK` or Pakistan geography.

# V6.5.0 — Continuous Parallel Pipeline

- Enabled coordinator continuation while child workers remain active (`noContinueWhileChildrenActive: false`, `minDelayMs: 5000`).
- Enabled background `job-autopilot-*` Task workers with `background=true`; coordinator schedules new work immediately without waiting for child completion.
- Separated FreeHire and LinkedIn discovery claims (`discovery-action-claim.freehire.json`, `discovery-action-claim.linkedin-browser.json`); sources never share a claim and never block each other.
- Made FreeHire and LinkedIn independently restartable; each source acquires/renews/releases its own claim.
- Removed LinkedIn batch-size workaround (`linkedinDiscoveryBatchTarget=3` → `8`); small batch no longer needed for coordinator unblocking.
- Enabled continuous discovery alongside assessment, resume, and application work; active discovery workers never suppress downstream consumers.
- FreeHire discovery acquires its own claim at startup and releases on completion.
- LinkedIn discovery acquires claim at startup, renews after each persisted job/lane, releases on completion.
- Added `discovery_sources` to scheduler state with independent availability and targets per source.

# V6.4.0 — Continuous Discovery and Completion-First Answers

- Split continuous discovery into an executable FreeHire action and a dedicated BrowserOS LinkedIn discovery subagent with independent per-source targets, so both launch with the worker wave and a full FreeHire result cannot suppress LinkedIn.
- Added the configured candidate phone and routed mandatory current compensation through the expected-compensation resolver.
- Removed all new `blocked-protected-fact` production paths. Unknown identity, legal, authorization, compensation, and sensitive questions now require one context-aware generated answer and continue; legacy results remain readable only.
- Made discovery a permanent claimed fast-wave action that launches immediately alongside assessment, resume, and application work regardless of pipeline depth.
- Replaced brittle per-command PowerShell permission patterns with broad worker PowerShell access scoped by worker instructions and work-item claims.
- Added hydrated semantic job fingerprints, within-batch dedupe, employer/body identity checks, unnamed-client enforcement, final aggregator-route rejection, and `skipped-closed` outcomes.
- Added component-summed assessment scores, explicit identity checks, requirement importance, evidence/ATS-keyword enforcement, and up to eight distinct reason codes.
- Switched browser workers to granular BrowserOS tools and added a non-destructive session-export JSON sanitizer for PII and token material.

# V6.3.0 — Zero-Credit FreeHire Acceleration

- Added one guarded FreeHire client with official CLI/environment credential discovery, content-addressed caching, request coalescing, sanitized latency telemetry, provider cooldowns, and a method/path allowlist that blocks credit-consuming or unknown endpoints before network access.
- Added deterministic per-work-item enrichment across FreeHire, LinkedIn, and browser discoveries: public URL find/resolve, catalogue copies, captured application questions, no-LLM job matching, arbitrary-text matching, and read-only cached match analysis.
- Added cached candidate autofill and screening values with strict local-canonical-first precedence, plus daily facet/market-coverage evidence for discovery-lane allocation.
- Prioritized otherwise-equal assessment work by deterministic match coverage while explicitly retaining the assessor as the only fit/eligibility decision-maker.
- Added best-effort FreeHire tracking only after verified local reconciliation; the local ledger remains authoritative and remote failure never rolls it back.
- Added optional exact-link Gmail reconciliation. Only post-reservation, slug-linked employer messages with stable IDs and recognized signals may confirm an ambiguous send through a caller-bound send-guard proof kind.
- Expanded campaign analytics with API latency/cache/auth/error metrics, enrichments, cross-source resolutions, remote mirrors, mail proof counts, and credit-history anomalies.
- Kept TeX resumes authoritative and permanently excluded automatic match-analysis creation, CV tailoring, assistant/autopilot, experience writes, referrals, Talent Network, ghost reports, and other paid or unrelated side effects.
- Added release assertions for the zero-credit, public-URL, local-authority, and exact-mail boundaries. They are packaged but were not executed for this change.

# V6.2.0 — Runtime Contract Enforcement

- Preserved uncapped non-LinkedIn worker fan-out while replacing 90-minute default worker claims with explicit 20/30/45-minute stage leases and a 15-minute discovery lease.
- Added a deterministic work-item manifest so workers receive exact canonical, runtime evidence, and optional artifact paths without probing or guessing.
- Made assessment commits return all schema errors in one response, documented the exact worker payload, and enforced the 72 threshold plus the narrow 68-71 exception in both commit and promotion paths.
- Removed required-field `0`, `No`, and `Not applicable` guesses; added canonical identity resolution, protected-fact blocking, semantic-answer handoff, application preflight, and a per-claim repeated-question circuit breaker.
- Added structured `created`/`existing`/`duplicate`/`rejected` work-item creation so exact-ID rediscovery cannot overwrite source metadata or inflate discovery counts.
- Made semantic title identity insensitive to word order, ranked direct ATS/employer copies ahead of aggregators, and persisted aggregator-only targets as unresolved routes.
- Added compact continuation state and moved installed-agent backups outside the auto-discovered agent directory with an explicit restart warning for cached definitions.
- Extended campaign statistics with assessment/route/preflight state, recoverable retry totals, and repeated answer-resolution/loop-guard counts so long-session bottlenecks are visible without reprocessing raw session exports.
- Added non-sending resilience assertions for structured idempotency, manifest location, aggregate assessment errors, score enforcement, safe answer resolution, and reordered-title dedupe; they are packaged but were not executed for this change.

# V6.1.1 — FreeHire API and Salary Reliability Fix

- Fixed a PowerShell syntax error that prevented the new quality gate from running.
- Fixed country-code array casting that reduced `DE` to `D` and caused silent global salary fallback.
- Replaced ignored FreeHire query parameters with the documented singular facets, exclusions, and posted-date sorting; collapsed 21 category requests into three composite lane requests.
- Correctly unwrapped public API `data` envelopes and added targeted `/similar`, `/copies`, and `/apply-form` use.
- Added cached dynamic local salary p25 resolution through `/insights/salary`, sample thresholds, progressive fallbacks, and period conversion.
- Changed ghost/repost/fake-freshness data from automatic rejection into exposed evidence-only reality signals; explicit employer overrides remain only for confirmed exceptions.

# V6.1.0 — Fast Routes and Deterministic Answers

- Added keyless FreeHire discovery across Pakistan, global-remote, sponsorship, category, and seniority lanes with full source metadata and optional apply-form capture.
- Added enforceable job-quality gates before queue creation and send reservation, including the micro1 and Crossing Hurdles denylist.
- Added structured education dates and employer-acceptance salary defaults in profile data plus deterministic form-answer resolution.
- Stopped creating `blocked-unknown-fact`; retained it only for legacy terminal compatibility and introduced protected-fact blocking.
- Replaced source/domain route guesses with explicit application route sidecars and a route-pending stage.
- Added fast/research scheduler waves, ISO timestamp normalization, latency and FreeHire campaign metrics, and larger bounded assessor/research budgets.

# V6.0.0 — Goal-Only Reliability Hardening

- Made the session goal plugin the sole persistence owner and enabled its child-session continuation gate.
- Removed all packaged OS-process lifecycle and browser-health commands.
- Added stage-scoped expiring claims for work items and discovery.
- Made assessment commits first-writer-safe with expected prior status and a work-item lock.
- Made promotion and resume compilation idempotent, reusing valid outputs under work-item locks.
- Added deterministic terminal application blocker outcomes and `application_outcome_repair` routing.
- Restricted and serialized discovery/assessment decision logging.
- Added structured channel-compatible absence proof to the send guard.
- Added non-ledger verification quarantine and the user-facing quarantine resolution command.
- Exposed quarantine, outcome repair, and claim metadata in session state.
- Updated every worker to use exact installed paths, claim before work, follow the BrowserOS one-strike rule, and return canonical status lines.
- BrowserOS and OS lifecycle management are now external; restoration is followed by `/goal resume`.

# V5.15.1 — Reliability Hotfix

- Restored deterministic canonical-facts, shared-evidence, and commit-script locators to the assessor after V5.15 prompt compaction removed them; restored its compact payload contract and raised its bounded local step budget.
- Fixed `application-send-guard.ps1` verification grace under locale-sensitive PowerShell JSON timestamp conversion. Deadlines now derive from the original reservation, persist durably, and never slide forward on retry.
- `session-state.ps1` suppresses grace-deferred verification until its stored deadline and emits exact two-line `worker_prompt` values for worker actions.
- Applicators now yield immediately on verification grace, stop after one BrowserOS connection-loss probe, and require authoritative account/Sent evidence before clearing an ambiguous reservation.
- Documented the exact defer command and prohibited coordinator-side assessor completion or prompt augmentation.

# V5.15.0 — Compact Uncapped Pipeline Edition

- Removed every skill-level worker concurrency cap except serialized LinkedIn Easy Apply; assessor, unified research, resume, external ATS, and email waves use runtime capacity.
- Scheduler concurrency is expressed as `default: unbounded` and `linkedin_easy_apply: 1`; it carries no per-worker limit table.
- Kept the assessor local/web-free and merged the two web-heavy eligibility/evidence workers into one optional research finalizer.
- The research finalizer reuses existing reports first, performs only one bounded decision-changing lookup when missing, and commits final pass/fail without a third reassessment call.
- Preserved the eight-requirement fit-map ceiling and the resume worker's completion budget while enforcing minimal tailoring and one direct incomplete-artifact retry.
- `session-state.ps1` now exposes all runnable cross-stage actions at once instead of hiding queue work whenever generated work exists.
- Preserved the established `next_action` enum and compact state output; each action carries its own dispatch target without duplicated path batches.
- Added an 8-job intake floor with `discovery_needed` / `discovery_slots`; ready work runs first and discovery captures multiple complete JDs per pass.
- Supervisor slices require each worker wave to be emitted together with exact two-line worker prompts.

# V5.14.2 — Goal-Guarded Continuation Edition

- Integrated `opencode-goal-plugin` as an optional coordinator continuation layer for explicitly requested persistent campaigns.
- Each supervised slice creates one continuous goal only when none is active; submission counts, empty queues, blocked routes, and slice boundaries are not completion conditions.
- Goal continuations must rerun `session-state.ps1`; ledger truth, ambiguous-side-effect verification, send guards, and worker isolation remain authoritative.
- This recovers silent `finish: unknown` model turns while retaining the existing fresh-slice supervisor as the outer reliability boundary.
- Installation now distinguishes interactive `/goal` activation from automatic supervisor activation and includes the required OpenCode config merge and verification commands.
- Goal limits use the plugin's maximum safe integer, tool-free auto-pause is disabled, and ordinary messages steer rather than interrupt; `/goal pause` and `/goal stop` remain the only deliberate controls.

# V5.14.1 — Solver-Aware CAPTCHA Edition

- Standalone CAPTCHAs now preserve the task-owned tab, trigger an installed external solver once through an ordinary visible control, and wait up to 120 seconds for a targeted cleared state.
- CAPTCHA presence alone no longer creates an immediate domain circuit; failed/repeated solver recovery still does, while MFA, account restrictions, explicit automation/security warnings, and attributable 429s remain immediate stops.
- Unresolved CAPTCHA tabs remain open and the work item is checkpointed/deferred; ambiguous post-Submit state still routes to verification rather than another side effect.
- Added a reusable `references/captcha-recovery.md` workflow used by external ATS, email, LinkedIn, BrowserOS, and supervisor instructions.

# V5.14.0 — Persistent + Idempotent Edition

- Added `job-autopilot-email-apply`, a narrow direct-email subagent that verifies Gmail Sent before any retry and uses a stable plain-text message path.
- Added `application-send-guard.ps1`, an atomic global reservation/receipt boundary for email and ATS submissions. Ambiguous outcomes become verification-only, and company/title reposts cannot race under different job IDs.
- Added `reconcile-application-result.ps1`, an idempotent result-to-ledger boundary that replaces coordinator-authored JSONL appends.
- Added `domain-circuit-breaker.ps1`, which repairs concatenated legacy JSONL, writes atomic per-domain markers, supports subdomains, and gives CAPTCHA/security blocks a durable expiry.
- `session-state.ps1` now removes active circuit domains from actionable work and exposes `application_verification`, `generated_circuit_blocked`, and `circuit_breakers_active`.
- Promoted queue copies are now shadowed by their generated work item, and fresh terminal skips can no longer be reopened by the legacy reassessment exception.
- Fixed BrowserOS health checks on Windows hosts where `localhost` resolved to IPv6 while BrowserOS listened on IPv4; the supervisor now checks `127.0.0.1` by default.
- Added `get-autopilot-status.ps1`; continuous/forever requests now start or inspect the detached supervisor instead of relying on one finite chat turn.
- Moved installation backups outside the auto-discovered skills root so an old backup cannot shadow the active skill.
- The supervisor now contains slice launch/logging failures and restarts after backoff instead of exiting itself.
- Coordinator policy now forbids declaring a pause/completion while the final state still reports actions.
- Expanded resilience regression coverage for ambiguous sends, duplicate prevention, legacy circuit repair, and active circuit routing.

# V5.13.0 — Net-New Throughput Edition

- Added an unattended OpenCode supervisor (`start-autopilot.ps1` / `run-campaign.ps1` / `stop-autopilot.ps1`) with bounded fresh slices, a single-instance lock, keep-awake support, clean stop markers, and persistent logs/state.
- Added dual BrowserOS health gating: MCP port 9010 and browser CDP port 9110 must both be live. A half-alive MCP server no longer burns agent sessions while the browser process is dead.
- Restored the BrowserOS operational playbook accidentally truncated in V5.11.4, including tab ownership, `_run` one-strike fallback, unavailable CDP methods, hidden-input resume upload, exact filename verification, covered-button fallbacks, Lever native setter workaround, and known unavailable CDP DOM methods.
- Added explicit handling for the upstream transient/no-ref upload limitation tracked by BrowserOS issue #2156.
- `session-state.ps1` now routes placeholder/missing JDs to `source_pending`; it no longer advertises them as fast assessment work.
- Added semantic company/title dedupe for recent submissions and active work items. `new-workitem.ps1` now blocks repost/new-ID duplicates and is idempotent for exact IDs.
- Submission headlines now count unique company/title identities; raw ledger submission rows remain available as audit detail.
- Fixed LinkedIn governor state loss caused by PowerShell JSON timestamps being converted to locale-formatted `DateTime` values before parsing.
- The governor now merges ledger truth on every read, recognizes `easy-apply-submitted` rows even when `source` is only `linkedin`, accepts `-JobId`, avoids double-recording an ID, serializes writers with a lock, and replaces state atomically.
- Expanded the resilience self-test to cover source gating, semantic dedupe, unique metrics, and governor recovery/idempotency.
- Compressed the coordinator prompt into one deterministic hot loop and made net-new submissions the explicit throughput objective.

# V5.12.0 — Deterministic Recovery Edition

- Added `commit-assessment.ps1`: assessor decisions are schema-validated and atomically serialized; coordinator hand-written assessment/fit JSON is forbidden.
- Assessor direct file editing is denied; its only assessment-write path is the deterministic commit script.
- Added `repair-workitem.ps1`: malformed/legacy assessment artifacts are backed up and reset to pending without inventing hard-gate truth.
- `session-state.ps1` now exposes `assessment_repair` for malformed/contradictory passed artifacts.
- Added `advance-workitem.ps1`: one non-throwing coordinator transition boundary that repairs, routes, promotes, and converts promotion exceptions into recoverable job-local state.
- `promote-workitem.ps1` now accepts both `-WorkItemDir` and `-JobId`, so the exact V5.11.4 parameter mistake no longer binder-fails.
- Added an explicit campaign fault-containment rule: recoverable tool/schema/script/browser/resume/worker errors never end the overall run; unaffected jobs and discovery continue.
- Added `defer-workitem.ps1` plus scheduler cooldown awareness (1m/5m/30m) so repeatedly broken queue/generated items cannot monopolize the campaign.
- Preserved CAPTCHA/MFA/security/automation circuit breakers as route/domain-local safety stops with zero bypass.
- Added `selftest-resilience.ps1` regression coverage for the V5.11.4 failure mode.

# V5.11.4

- Removed stale BrowserOS configuration-incident guidance from operational policy.
- Browser automation now follows only generic bounded fallback behavior.
- No campaign behavior depends on historical BrowserOS configuration incidents.

# Changelog

## V5.11.3 — BrowserOS `_run` compatibility correction

- `_run` now has a one-strike session capability breaker: first matching compatibility failure -> stop `_run` retries and continue granularly.
- BrowserOS/OpenCode update or MCP reconnection permits `_run` to be tested again in a future session; no permanent blacklist.


## 5.11.2 — Persistent Discovery

- A dry discovery wave no longer ends `continue applying`; coordinator rotates through the multi-source discovery ladder.
- Requires at least one non-LinkedIn discovery lane before declaring current-market exhaustion.
- Batch dedupe now explicitly happens before opening detail pages whenever result IDs are available.
- Reconcile path is narrowed to `application-result.json` (+ `job.json` only if needed), avoiding script/runtime archaeology.
- Preserves V5.11.1 non-interactive behavior: no question tool; unknown factual form blockers are logged and campaign continues.


- Coordinator never asks the user to choose/confirm/clarify routine campaign decisions.
- Question/interactive-choice tools are prohibited for the campaign.
- For benign non-factual choices: choose `Recommended` when present, otherwise the first safe option.
- Factual screening questions remain truth/evidence-bound; unsupported facts cause N/A/decline/skip, never fabrication or user prompting.
- CAPTCHA/MFA/security/manual-required blockers become terminal per-job/domain states while other jobs continue; no in-chat interruption.
- Applied the same deterministic policy to every packaged subagent.

# V5.11 — Fast Path Edition

- Reworked orchestration around **first useful application latency**: ready/resume/assessment work runs before web-heavy eligibility/evidence research. Fast and slow workers must not share one blocking wave.
- Main `SKILL.md` reduced from ~33 KB to ~12 KB. Packaged subagents no longer load the main skill on every task; each worker has a compact bounded policy.
- Removed routine TodoWrite/checklist mirroring and tool-call narration from campaign policy. Snapshot state is the checklist.
- `session-state.ps1` output is compact: no full `campaign-stats.json`, no duplicate `action_paths`, and actions are tagged `fast`/`slow`.
- Historical technical skips are no longer automatically reopened on every startup/policy upgrade. Fresh applications win.
- Added discovery fast triage: obvious closed/location/agency/identity/specialist rejects can be logged directly without creating a queue directory, assessment, or fit map.
- Added `scripts/log-decision.ps1` for compact safe skip logging.
- Assessors write detailed fit maps only for passed jobs; rejects use short reason codes instead of long JSON case files.
- Candidate evidence is now strictly bounded: max 5 relevant repos + 2 deployments per job, no full-account inventory, no exhaustive proof of absence, stop as soon as decision-changing evidence is found.
- Added `compact-candidate-evidence.ps1`; workspace upgrade removes giant source-check histories and keeps positive reusable claims only.
- Eligibility research now follows first-decisive-evidence semantics and normally stops after at most 2 authoritative sources.
- Resume/external workers lazy-load only files needed for the current stage and return terse status lines.
- Preserves V5.10 global-tenure + capability matching, live public evidence, LinkedIn Easy Apply governor, truth boundaries, and completely uncapped external ATS/company-site throughput.

# V5.10 — Live Evidence + Interview-Likelihood Edition

- Added hidden `job-autopilot-evidence` worker for targeted first-party GitHub/deployment/portfolio/candidate-authored LinkedIn verification whenever a technical gap would otherwise cause a false hard rejection.
- No hardcoded repository/project inventory. Candidate public identities come from canonical facts and relevant current repositories/projects are discovered dynamically.
- Added reusable `.job-apply-autopilot/candidate-evidence.json`, per-job `candidate-evidence-research.json`, and coordinator-owned `scripts/merge-candidate-evidence.ps1`.
- Changed experience matching to a global engineering-tenure band derived from canonical employment history; no separately calculated years for each technology.
- `N+ years <technology>` is assessed as global tenure + verified capability for fit; undocumented exact first-use dates are not a hard rejection.
- Relaxed technical hard gates for interview likelihood: a few learnable gaps become score penalties; true identity/credential/work-auth/management/defining-specialist blockers remain hard gates.
- Auto-apply threshold adjusted from 74 to 72.
- Added policy-version-aware reassessment for existing queue items that were technically skipped under older scoring rules while integrity and eligibility passed; old location/work-auth/identity/security skips stay terminal.
- Preserved V5.9.1 continuation, LinkedIn governor, and completely uncapped external ATS/company-site throughput.

# V5.9.0 — LinkedIn Governor + Durable Continuation Edition

## V5.9.1 — Empty-workspace hardening

- All scripts that accept `-Workspace` now treat `$null`, `""`, or whitespace exactly like an omitted argument and fall back to the caller's current directory.
- Fixes `Join-Path ... Path because it is an empty string` in `init-workspace.ps1` and `Resolve-Path ... LiteralPath because it is an empty string` in `session-state.ps1` when a caller passes an unset `$workspace` variable.
- The authoritative workspace contract is unchanged: the coordinator's initial current working directory is the workspace.


- Removed the old global `max_applications_per_run` and `max_external_applications_per_run` limits. External ATS/company-site applications now have no skill-imposed per-run, per-day, or concurrency maximum.
- Added persistent `linkedin-activity-state.json` plus `scripts/linkedin-governor.ps1`; Easy Apply pacing survives OpenCode restarts.
- Added conservative Easy Apply defaults owned by this skill: 4 confirmed submissions / rolling hour, 20 / rolling 24h, and 600 seconds minimum spacing. These are not claimed LinkedIn limits.
- LinkedIn cooldowns/security pauses no longer stop the campaign; unaffected external ATS applications, assessment, resume work, and discovery continue.
- Added LinkedIn signal handling: 24h cooldown for ordinary rate-limit/security-warning signals; CAPTCHA/MFA/account restriction creates a manual LinkedIn block.
- Added `references/linkedin-activity-governor.md` documenting source-derived Linked Helper safety observations separately from skill-owned defaults.
- `session-state.ps1` is now stage-aware (`actions[].stage`) so a restarted coordinator can dispatch assessors, eligibility research, resumes, application routing, or reconciliation without directory archaeology.
- Fixed generated-job continuation so promoted jobs awaiting a resume are actionable even before `resume-artifact.json` exists.
- Added `scripts/dedupe-jobs.ps1` for batch job-ID dedupe without ledger/queue scans.

# V5.8.0 — Snapshot-Authoritative Continuation Edition

- Makes `session-state.ps1` the authoritative continuation decision instead of merely a descriptive summary.
- Snapshot now returns exactly one `next_action`: `reconcile`, `resume-generated`, `process-queue`, or `discover`.
- Snapshot returns `action_paths`; existing campaign directories outside those paths must not be inspected during normal continuation.
- If `next_action` is `discover`, coordinator must begin discovery immediately and is explicitly forbidden from rescanning queue/generated/ledger state.
- Removes eager coordinator loading of `profile.yaml` and canonical facts at continuation startup; candidate truth remains lazy/stage-owned.
- Forbids reading `session-state.ps1` itself, recursive directory enumeration, ledger tailing, Glob-based campaign rediscovery, or alternate-workspace checks after a successful snapshot.
- Tightens generated-actionability so already-terminal application results do not get reprocessed as unfinished work.

# V5.7.0 — Current-Directory Workspace Edition

- Makes the coordinator's initial current working directory the single authoritative campaign workspace.
- Removes the `$HOME\job-search` fallback and all orchestration examples that hardcoded that convention.
- Forbids workspace discovery/scanning entirely during continuation.
- Defines runtime root as `<coordinator-cwd>\.job-apply-autopilot`.
- Requires subagents to use the absolute queue/generated job path passed by the coordinator rather than their own CWD.
- Keeps scripts portable: `-Workspace` receives the captured coordinator workspace; scripts already default to `(Get-Location).Path` when invoked directly.

# V5.6 — Fast bootstrap and deterministic continuation

- Replaced eager `Load these files first` behavior with lazy, stage-specific reference loading.
- Added deterministic workspace resolution; coordinator must not scan sibling/home folders to guess campaign state.
- Canonical runtime root is always `<workspace>/.job-apply-autopilot`; generated jobs are never read from `<workspace>/generated`.
- Added `scripts/session-state.ps1` to summarize ledger, queue, generated jobs, unreconciled external results, circuit breakers, and campaign stats in one call.
- `Continue applying` now loads only profile + canonical facts, takes one state snapshot, reconciles completed results, resumes actionable work, then returns to discovery.
- Coordinator is explicitly told not to read the full ledger or recursively enumerate directories merely to reconstruct startup state.

# V5.5 — Operational learning from successful real applications

- Added official ATS eligibility adapter guidance. Workable closed-country lists and Ashby exact-role location data can resolve foreign eligibility before opening forms.
- Added persistent BrowserOS playbook from successful Conquer/BTSE flows: Easy Apply draft recovery, hidden-input resume upload, exact filename verification, covered-button fallbacks, Lever native setter workaround, and known unavailable CDP DOM methods.
- Resume compiler now creates a unique professional application PDF plus `resume-artifact.json` SHA-256 manifest; generic `resume.pdf` is compile-only.
- Added one controlled one-page layout fallback (`resume.precompact.tex`, remove `\vfill`, tighten itemize spacing) and working-pdflatex fallback when latexmk is installed but broken.
- External ATS worker step budget increased to 120 and now checkpoints `application-progress.json`; re-dispatch resumes safely and verifies any prior `submit-clicked` state before another submit.
- Added campaign analytics (`update-campaign-stats.ps1`, `campaign-stats.json`) and discovery-lane/search-query metadata to improve search allocation without changing gates.
- Fixed workspace initialization to actually create the shared `domain-circuit-breakers/` marker directory already referenced by workers.
- Preserved V5.4 architecture: all ready external ATS applications can run concurrently through trusted subagents; LinkedIn Easy Apply remains coordinator-owned.

# V5.4 changes

- Added trusted `job-autopilot-external-apply` subagent with BrowserOS access and final-submit authority for external ATS/company-site jobs.
- Removed the skill-level concurrency cap for external applications: dispatch every ready external job concurrently; OpenCode/runtime resources are the only natural limit.
- LinkedIn Easy Apply remains coordinator-owned.
- External workers write per-job `application-result.json`; coordinator merges results into shared ledgers to avoid concurrent JSONL append races.
- Added reactive shared per-domain circuit-breaker markers checked immediately before final Submit; this is not a pre-emptive per-domain concurrency cap.
- Installer/verifier now includes the fourth external-applicator agent and verifies BrowserOS is allowed only for that worker.
- Updated orchestration and anti-automation policies for parallel external submission.

# V5.3 — Trusted worker write + scoring consistency

- Fixed subagent `write`/`edit` failures caused by relative Windows workspace paths not matching the queue/generated permission globs.
- Assessor, eligibility, and resume workers now have trusted direct `edit: allow`; their one-job ownership boundary is enforced by the agent contract and coordinator, while BrowserOS/nested-task restrictions remain.
- Assessor wording now explicitly loads the currently installed V5.3 rules instead of stale `V5` wording.
- Resolved the mandatory-gap contradiction: one learnable central ADJACENT gap can be tolerated only when it is not role-defining and carries no explicit ownership/years requirement. One role-defining missing depth requirement, or two central gaps, still hard-fails.
- Plutus-style `4+ years data-warehouse/governance ownership` remains a legitimate hard failure when canonical evidence only supports ETL/backend work.
- `verify-subagents.ps1` now checks that trusted worker write permissions were actually installed.
- Coordinator Task prompts are now deliberately minimal/evidence-neutral; unsourced “important context” and copied policy summaries are forbidden, preventing stale-policy anchoring and fabricated employer-location context.

# V5.1

- Fixed Windows `AuthorizationManager check failed` when the coordinator invoked packaged `.ps1` files directly.
- All documented/runtime script calls now use `pwsh -NoProfile -ExecutionPolicy Bypass -File ...`.
- Installation unblocks downloaded/extracted skill files with `Unblock-File`.
- `promote-workitem.ps1` now launches its nested scaffold script through a bypassed child `pwsh` process.
- Resume subagent instructions explicitly require the bypassed `pwsh` compile command.
- Clarified that `-ExecutionPolicy Bypass` is a host option, not a script argument.

# V5 change log — Parallel Pipeline Edition

## Parallel orchestration

- Added three hidden OpenCode subagents: `job-autopilot-assessor`, `job-autopilot-eligibility`, and `job-autopilot-resume`.
- Added bounded concurrency: up to 4 assessment workers, 3 eligibility researchers, and 3 resume workers.
- BrowserOS authentication, form filling, uploads, Submit actions, and global ledgers remain coordinator-only and serialized.
- Added `.job-apply-autopilot/queue/` work items so workers never edit the same job directory.
- Added `new-workitem.ps1` and `promote-workitem.ps1` for deterministic queue → generated transitions.
- Added `install-subagents.ps1` to install the packaged agents into `~/.config/opencode/agents/`.
- Added `references/parallel-orchestration.md`.
- Worker agents cannot invoke other subagents, cannot write global ledgers, and cannot use BrowserOS.
- Resume workers only run after the coordinator has passed every hard gate.
- If Task/custom agents are unavailable, V5 falls back to the same pipeline serially.

## Retained V4 safeguards

- Positive foreign-job eligibility evidence remains mandatory.
- LinkedIn OAuth/import remains preferred over password account creation.
- Password generation/autofill remains allowed as fallback.
- Conservative EXACT/DIRECT/ADJACENT/WEAK/NONE evidence scoring remains enforced.
- Canonical LaTeX resumes remain immutable sources; each accepted job receives a fresh independent resume.
- `tailoring-audit.json`, canonical SHA-256 checks, one-page compilation, ghost/identity gates, relocation policy, and domain circuit breakers remain in force.

## V5.2 — Eligibility calibration fix

- Fixed V5 overcorrection that treated nearly all non-literal Pakistan wording as `UNCLEAR`.
- Added `REGION_INCLUDES_PAKISTAN` for explicit Asia/APAC/APJ regional roles unless employer-specific restrictions conflict.
- A direct employer Pakistan job location is positive evidence; Pakistan search placement alone remains weak.
- Verified Pakistan-headquartered employer or Pakistan employing entity tied to an unrestricted remote role can establish `PAKISTAN_ELIGIBLE`.
- Merely having an unrelated Pakistan office is still not enough for a foreign-country role.
- Direct-employer LinkedIn/Easy Apply postings no longer require a duplicate official ATS/careers listing.
- Assessors are forbidden from inventing headquarters/entity/office facts; such metadata must come from captured source text or verified research.