# Validation — Job Apply Autopilot V5.1

Validated on 2026-08-20 before packaging.

## Package integrity

- SKILL frontmatter parses as YAML.
- Skill name remains `job-apply-autopilot`.
- Metadata version is `5`.
- Three packaged agent frontmatters parse as YAML.
- All three agents are `mode: subagent` and `hidden: true`.
- `opencode-config-snippet.jsonc` parses as JSON.
- Canonical SHA-256 values still match `canonical/SHA256SUMS.txt`.
- No known generated ATS password from the previous run is present in the package.

## Parallel architecture checks

- assessor: BrowserOS denied; Task denied; no shell access.
- eligibility researcher: BrowserOS denied; Task denied; web research allowed.
- resume worker: BrowserOS denied; Task denied; only job-resume file work + compile command intended.
- global application/watchlist/circuit-breaker ledgers are coordinator-only by policy.
- browser submissions are serialized by policy.
- queue work items isolate per-job assessment files.
- generated folders isolate per-job resume files.

## OpenCode compatibility basis

OpenCode's current Agents documentation supports:

- `mode: subagent`,
- automatic invocation by primary agents,
- child sessions,
- `hidden: true` programmatic subagents,
- Task permission patterns,
- per-agent permissions,
- `steps` limits,
- subagents inheriting the invoking primary model when no model override is specified.

The packaged workers intentionally omit a `model` override.

## PowerShell note

This ChatGPT container does not include Windows PowerShell/MiKTeX, so the newly added PowerShell queue/install scripts were statically reviewed rather than executed here. The canonical `.tex` files are byte-identical to the already validated V4 sources and their stored SHA-256 hashes still match.

On the target Windows machine, run:

```powershell
$skill = "$HOME\.config\opencode\skills\job-apply-autopilot"
pwsh -NoProfile -ExecutionPolicy Bypass -File "$skill\scripts\verify-canonical.ps1"
pwsh -NoProfile -ExecutionPolicy Bypass -File "$skill\scripts\install-subagents.ps1"
pwsh -NoProfile -ExecutionPolicy Bypass -File "$skill\scripts\verify-subagents.ps1"
```

Then restart OpenCode and run the normal skill command.
