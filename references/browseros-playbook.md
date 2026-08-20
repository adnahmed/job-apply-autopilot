# BrowserOS Operational Playbook V5.11.3

## Purpose
Persist browser techniques that have already succeeded in real applications so workers do not rediscover them by trial and error.

## General rule
Prefer ordinary BrowserOS `snapshot`/`act`/`upload` operations. Use `evaluate` for targeted DOM extraction or when a framework-controlled field does not accept reliable input. Never use these techniques to bypass CAPTCHA, MFA, anti-bot, or security controls.

### `_run` compatibility breaker

