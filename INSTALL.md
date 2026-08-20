# Install and use in OpenCode

## 1. Install globally (recommended)

Copy the entire `job-apply-autopilot` folder to:

```text
~/.config/opencode/skills/job-apply-autopilot/
```

From the directory containing the folder:

```bash
mkdir -p ~/.config/opencode/skills
cp -R job-apply-autopilot ~/.config/opencode/skills/
```

OpenCode discovers global skills from `~/.config/opencode/skills/*/SKILL.md`.

## 2. Make sure the skill can load

If your OpenCode config restricts skills, allow this one. Example for current OpenCode classic config style:

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "permission": {
    "skill": {
      "job-apply-autopilot": "allow"
    },
    "browseros-neo_*": "allow"
  }
}
```

If you intentionally want BrowserOS tool confirmations, change `browseros-neo_*` to `ask`. For the fully autonomous mode requested here, use `allow`.

## 3. BrowserOS neo

You already have BrowserOS neo working if OpenCode can call tools such as `browseros-neo_tabs` and `browseros-neo_name_session`.

If setting it up on another machine, BrowserOS neo exposes an MCP endpoint locally. Copy its MCP URL from BrowserOS neo settings and add it to OpenCode as a remote MCP server. Example:

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "browseros-neo": {
      "type": "remote",
      "url": "http://127.0.0.1:9239/mcp",
      "enabled": true
    }
  }
}
```

Use the actual URL shown by BrowserOS neo; the port above is only an example.

## 4. Use a dedicated job-search workspace

For persistent deduplication without broad filesystem permissions:

```bash
mkdir -p ~/job-search
cd ~/job-search
opencode
```

The skill will keep its ledger at `~/job-search/.job-apply-autopilot/applications.jsonl` when you run it from this folder.

## 5. Start OpenCode and invoke the skill

The skill is advertised automatically when relevant. You can be explicit:

```text
Use the job-apply-autopilot skill. Apply to jobs.
```

Useful examples:

```text
Use job-apply-autopilot. Apply to 15 AI Engineer / LLM Engineer jobs, remote only, last 7 days.
```

```text
Use job-apply-autopilot. Easy Apply only, minimum score 80, last 24 hours.
```

```text
Use job-apply-autopilot. Apply to 10 senior backend/platform jobs in Pakistan or remote.
```

```text
Use job-apply-autopilot. Dry run: find and score the best 30 matches, do not submit.
```

## 6. What “fully autonomous” means here

The agent submits without asking you for routine confirmation. It does not fabricate required facts. If a site requires an unknown factual answer with no truthful fallback, or hits CAPTCHA/MFA/security checks, it skips only that application, logs the reason, and continues where safe.
