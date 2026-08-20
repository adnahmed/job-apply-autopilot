---
name: job-apply-autopilot
description: "Fast autonomous job discovery, truthful fit triage, tailored resumes, and submission using BrowserOS. Optimized for low first-application latency: fast path first, research only when decision-changing."
version: 5.11.1
---

# Job Apply Autopilot V5.11.1 — Fast Path + Non-Interactive Edition

Goal: **maximize credible interview opportunities per unit time**. Preserve truth, eligibility, anti-automation safety, and job-specific resumes. Everything else is subordinate to speed.

## 1. Action-first operating rule

Do the next useful campaign action. Do not narrate plans, mirror state into TodoWrite, create prose case files, or inspect state that a script already resolved.

Default pattern:

`discover -> fast triage -> resume -> apply`

Escalate to research only when uncertainty would actually change `apply` vs `skip`.

### No bookkeeping theatre

During a normal autonomous run:
- do **not** use TodoWrite/task checklists to mirror queue state;
- do **not** announce every tool call;
- do **not** write long rejection explanations;
- do **not** read scripts merely to learn their parameters when this skill already gives the invocation;
- do **not** scan directories to verify a successful snapshot;
- do **not** wait for slow research jobs before routing a job that is already ready.

Persist concise machine state; keep reasoning ephemeral.

### Non-interactive autonomy

Never stop to ask the user to choose, confirm, clarify, or approve routine campaign decisions. Do not invoke any question/interactive-choice tool.

When a non-factual choice has multiple safe options:
1. choose the option explicitly marked **Recommended**;
2. otherwise choose the first listed/visible safe option;
3. continue immediately.

This applies to routing, authentication alternatives, benign application preferences, save/continue dialogs, and other workflow choices. For factual screening fields (work authorization, location, years, salary, identity, eligibility, etc.), choose the truthful evidence-supported answer; if no truthful supported answer exists and no legitimate N/A/decline option works, skip that application rather than asking the user or fabricating. Human intervention is only a terminal status for CAPTCHA/MFA/security/manual-required blockers; record it and continue other jobs instead of asking in-chat.

## 2. Workspace + continuation

Coordinator initial CWD is the campaign workspace. Capture once:

```powershell
$workspace = (Get-Location).Path
```

Runtime root: `$workspace\.job-apply-autopilot`.

At start/continue run exactly once:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "$skillRoot\scripts\session-state.ps1" -Workspace "$workspace"
```

Trust its `next_action` and `actions`. Never rescan queue/generated/ledger to double-check it.

Stage handling:
- `application_ready` / `application_resume`: route now.
- `resume_pending`: dispatch resume worker now.
- `coordinator_adjudication_pending`: adjudicate/promote now.
- `assessment_pending` / `reassessment_pending`: quick assessor wave.
- `eligibility_research_pending` / `candidate_evidence_pending`: slow lane; process **after** any ready/fast work.
- `discover`: discover immediately.

**Latency rule:** never place fast assess/resume/application work in the same waiting wave as web-heavy eligibility/evidence research. Route completed jobs before starting slow research.

Historical technical skips from older policy versions are **not automatically reopened at startup**. New work wins. Revisit old skips only when explicitly requested or when the coordinator is otherwise idle and has no fresh discovery/applications to process.

## 3. Fast triage before queue creation

During discovery, classify directly from the job page/JD before creating a work item.

### Obvious skip — log one compact row, no queue directory

Skip immediately when decisive evidence shows:
- closed/removed job;
- country/work-authorization lock with no bridge;
- agency with unknown client / talent pool / expert marketplace / material redirect identity mismatch;
- fundamentally unrelated role identity (research scientist, CUDA/model-training specialist, frontend/mobile-first, people manager, etc.);
- clear required licence/clearance/credential not held.

Use:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "$skillRoot\scripts\log-decision.ps1" `
  -JobId "<id>" -Status "<skip-status>" -ReasonCode "<short-code>" `
  -Company "<company>" -Title "<title>" -JobUrl "<url>" -Source "<source>" `
  -Workspace "$workspace"
```

No assessment.json. No fit-map.json. No research proving what is already decisive.

### Viable / plausible job — queue

Create a work item only when the role is plausibly worth applying to:

```powershell
$workItem = pwsh -NoProfile -ExecutionPolicy Bypass -File "$skillRoot\scripts\new-workitem.ps1" `
  -JobId "<id>" -Company "<company>" -Title "<title>" -JobUrl "<url>" `
  -Location "<location>" -Source "<source>" -DiscoveryLane "<lane>" `
  -SearchQuery "<query>" -Workspace "$workspace"
```

`source.md` should contain concise metadata plus the complete JD. Do not duplicate the JD into extra narrative notes.

Batch dedupe newly discovered IDs with `scripts/dedupe-jobs.ps1`; do not grep the whole runtime.

## 4. Interview-likelihood fit model

Canonical facts are the authority for employment history, overall professional tenure, employer ownership, metrics, education, and titles. Public first-party artifacts are valid evidence of technical/project capability.

### Years

Derive overall software-engineering tenure from `canonical/canonical-facts.yaml` at runtime. **Never maintain years-per-technology counters.**

`N+ years React` is internally evaluated as:
- overall engineering tenure plausibly satisfies `N+`; and
- React capability is supported or reasonably plausible.

Do not invent a precise per-technology duration on a resume/form unless dated evidence supports it.

### Stretch tolerance

A few learnable/adjacent gaps are normal. Missing documentation is uncertainty, not proof of inability.

Hard-skip only:
- legal/work-auth/credential blockers;
- fundamentally different specialist identity;
- role-defining management/leadership requirement with no support;
- several defining capabilities clearly absent after a **bounded** decision-changing check.

Otherwise score and apply when interview likelihood is credible.

Default threshold: 72. Scores 68–71 may still apply opportunistically when eligibility and role identity are strong.

## 5. Assessment fast path

`job-autopilot-assessor` is for viable queued jobs. It must be quick and local: no web, no reading canonical `.tex` resumes, no exhaustive requirement matrix.

It reads:
- `job.json`, `source.md`;
- `canonical/canonical-facts.yaml`;
- runtime `candidate-evidence.json` if useful;
- existing per-job research only when present.

Outputs must be compact:
- `assessment.json`: decision, score, gates, at most 2 short reasons, next stage;
- `fit-map.json`: **passed jobs only**, max 8 central requirements, compact evidence/provenance fields.
- failed jobs may use a minimal fit map or none; one reason code is enough.

Do not request public evidence merely to improve a score. Request it only when one narrow artifact-verifiable capability is genuinely decision-changing.

## 6. Bounded public evidence — depth on demand

Use `job-autopilot-evidence` only for an otherwise viable job whose decision hinges on a technical capability not already covered by canonical facts/cache.

Hard budget:
- targeted capability search only;
- inspect at most 5 relevant first-party repos and 2 tied deployments;
- no full GitHub account inventory;
- no exhaustive proof-of-absence crawl;
- stop as soon as enough evidence exists to make the decision;
- unresolved within budget = `UNRESOLVED`, not fabricated `NONE`.

Evidence worker writes only `<job>/candidate-evidence-research.json`. Coordinator merges positive reusable findings:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "$skillRoot\scripts\merge-candidate-evidence.ps1" `
  -EvidenceFile "<job>\candidate-evidence-research.json" -Workspace "$workspace"
```

Then reassess once. No repeated evidence loop.

For common engineering stack gaps, unresolved evidence normally reduces score rather than killing the application. Specialist-role identity can still hard-fail.

## 7. Eligibility — decisive evidence wins

Positive Pakistan eligibility is required before submit. Valid states include exact Pakistan location, explicit worldwide/international hiring, Pakistan in country list, explicit Asia/APAC/APJ scope without conflict, global contractor wording, sponsorship, or relocation support.

`Remote`, worldwide search placement, global company, international team, address-form acceptance, or absence of a work-auth question are not enough alone.

Do not call eligibility research when `source.md` already contains decisive exact-role evidence.

When research is needed, `job-autopilot-eligibility` uses **first decisive evidence**:
- prefer exact official requisition/JD;
- normally max 2 authoritative sources;
- explicit country lock/no sponsorship = stop immediately and return ineligible;
- explicit eligible country/region/international-hiring language = stop when sufficient;
- if still unclear after bounded check, watchlist and move on.

Do not collect five supporting sources after the decision is settled.

## 8. Scheduling: fastest useful result first

Priority:
1. reconcile confirmed application results;
2. route generated ready jobs;
3. generate resumes for approved jobs;
4. adjudicate/pass quick assessments;
5. assess fresh viable jobs;
6. fresh discovery;
7. slow eligibility/evidence research;
8. historical/reassessment cleanup.

As soon as one job passes, promote/resume/route it. Do **not** wait for every job in the batch.

Use parallel workers only when their expected latency is similar. Never bundle a quick local assessor with web-heavy evidence/eligibility workers if the harness will wait for the whole wave.

## 9. Promotion + resume

After all hard gates pass and score is viable:

```powershell
$jobDir = pwsh -NoProfile -ExecutionPolicy Bypass -File "$skillRoot\scripts\promote-workitem.ps1" `
  -WorkItemDir $workItem -Canonical <ai|backend> -Workspace "$workspace"
```

Dispatch `job-autopilot-resume` immediately.

Resume rules:
- fresh immutable canonical scaffold per job;
- selection/reordering/deletion first;
- supported public-project claims allowed only with provenance;
- no invented employer association, metrics, management, specialist title, or precise technology duration;
- compile one-page PDF through `compile-resume.ps1`;
- output summary should be only status + artifact path.

## 10. Application routing

### LinkedIn Easy Apply

Coordinator-owned only. Check governor before starting:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "$skillRoot\scripts\linkedin-governor.ps1" -Action Status -Workspace "$workspace"
```

After confirmed success record `RecordEasyApply`. Respect rolling pacing and first security/rate-limit signal. Easy Apply cooldown never blocks external ATS work.

### External ATS/company site

Dispatch one `job-autopilot-external-apply` per ready job immediately. **No skill-imposed numeric per-run/day/concurrency limit.** Worker may authenticate, upload, fill, click final Submit, verify success, and write `application-result.json`.

OAuth/existing session first; password generation/autofill allowed when needed.

## 11. Anti-automation

First explicit `possible spam`, automation detection, suspicious activity, account restriction, attributable 429, CAPTCHA, or MFA requiring human interaction:
- stop submit attempts on that domain/run;
- zero security retries;
- record circuit breaker;
- continue unaffected domains.

Ordinary field validation: max 1 corrective retry.

Never bypass CAPTCHA/MFA/security controls.

## 12. Truth boundaries

Optimize for interviews, not perfect documentation. Still never fabricate:
- employer/work history;
- degree/licence/clearance;
- work authorization;
- people management;
- production scale/metrics;
- a technology the evidence actually contradicts.

A reasonable stretch is allowed. A false factual answer is not.

## 13. Minimal logging

Rejected/obvious-skip jobs need only one compact ledger row with `job_id`, status, reason code, and essential identity metadata.

Detailed per-job artifacts exist **only when they serve a later action** (resume/application/recovery). Do not write essays into JSON.

Update campaign analytics after a meaningful batch, not after every single skip.

## 14. Worker prompt contract

Task prompts contain only:
- exact one job directory path;
- requested stage/action.

Do **not** tell packaged workers to load the main skill. Their installed agent files contain their bounded policy and point to the exact reference they need. This avoids repeatedly loading this coordinator document into every subagent.

Workers return terse results: status, score/state if relevant, next action. No markdown tables or long explanations unless a failure cannot be understood from a reason code.
