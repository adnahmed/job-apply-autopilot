# Autonomous application policy

## Objective
Apply to high-fit jobs end-to-end using BrowserOS neo, including LinkedIn Easy Apply and external ATS sites, without asking the user routine questions.

## Non-negotiable truthfulness
Never invent candidate facts. A fully autonomous run means the agent resolves fields using verified profile data, existing truthful LinkedIn/saved-application data, non-disclosure choices, or skips only the blocked application and continues. It does **not** mean making up a phone number, address, citizenship, work authorization, visa status, security clearance, education, employer, dates, skill duration, or other factual claim.

## Security boundaries
- Never request, reveal, copy, or store account passwords, one-time codes, or recovery secrets in logs.
- Never bypass CAPTCHA, MFA, anti-bot checks, or account-security warnings.
- If a CAPTCHA/MFA/security challenge blocks an application, mark it `blocked-security`, leave that application, and continue with other jobs when safe.
- If LinkedIn or an ATS indicates rate limiting, automation detection, or account restriction risk, end the run cleanly.

## Targeting and quality
- Default to roles matching AI/LLM/agent engineering, senior backend, platform, Python/FastAPI, TypeScript/Node.js, AWS/Kubernetes, distributed systems, RAG, Graphiti/Neo4j.
- Prefer remote roles, Pakistan roles, and Islamabad roles.
- Do not apply to internship, unpaid, volunteer, or commission-only jobs.
- Do not apply twice to the same company/title/location combination or same canonical job URL.
- Score before applying. Minimum 70/100.

### Match score
- Core technical match: 0-40
- Relevant seniority/scope: 0-15
- AI/agent or backend/platform domain fit: 0-15
- Location/remote compatibility: 0-10
- Experience requirement fit: 0-10
- Recency: 0-5
- Clear compensation or strong company fit: 0-5

Subtract 25 for a hard mismatch such as a mandatory technology/domain with no adjacent experience. Skip below threshold.

## Resume selection
- AI Engineer / LLM / agents / RAG / GenAI -> `resumes/ai-engineer.pdf`
- AI Application Engineer / AI product engineering / integrations -> `resumes/ai-application-engineer.pdf`
- Mixed AI + backend/platform -> `resumes/ai-backend-engineer.pdf`
- Senior Backend / Platform / Distributed Systems -> `resumes/backend-platform-general.pdf`
- Collaboration/SaaS/backend roles close to the Happeo-style profile -> `resumes/backend-platform-happeo.pdf`

Use the closest variant without rewriting the PDF unless the job explicitly requires a text resume and the browser form accepts generated text.

## Application answers
- Use `profile.yaml` as the source of truth.
- Reuse previously saved LinkedIn Easy Apply answers only if they do not conflict with `profile.yaml`.
- Optional demographic/EEO questions: choose the available decline/prefer-not-to-answer option.
- Cover letters and free-text questions: generate concise tailored text based only on verified profile facts and the job description.
- “Why this role/company?”: mention 2-3 concrete responsibilities/technologies from the posting and connect them to verified experience.
- Experience-year questions: answer conservatively. Never state more than the candidate’s total 6+ years; for a technology, infer only from dated jobs/projects where support exists.
- Salary: use posting midpoint when a numeric answer is mandatory. If no range is posted, research a current market median for exact title/location; save the source/assumption in the log. Prefer “Negotiable” when text is allowed.
- Start date/notice: use negotiable if offered, otherwise 30 days after offer.
- Work authorization/sponsorship/citizenship/clearance: use existing verified saved data if present. Never infer these from residence. If mandatory and unknown with no non-disclosure option, skip that application and continue.
- Phone/address: use verified LinkedIn contact info or previously saved application data if present. Never fabricate.

## LinkedIn Easy Apply flow
1. Search with defaults in `profile.yaml`, prioritizing postings from the last 7 days.
2. Open a candidate job in the BrowserOS neo agent session.
3. Capture title, company, location, canonical URL, seniority, description, requirements, date posted, and salary if shown.
4. Check dedupe state and compute match score.
5. If score >= 70 and no hard exclusion, click Easy Apply.
6. Select/upload the best resume variant.
7. Complete every page using verified/autonomous policies.
8. Review only for internal consistency; do not pause for user approval.
9. Submit.
10. Verify success via confirmation state/message, then append the log entry.
11. Continue until run limit, exhaustion of good matches, rate limit, or security warning.

## External ATS flow
1. From LinkedIn or other source, open the external application in the same BrowserOS neo session/group.
2. Identify ATS/provider and company job ID if possible.
3. Create/sign in only when the site supports passwordless/OAuth/session-based access already available. Do not invent credentials or handle secrets.
4. Populate profile/resume, upload the best resume, generate verified free-text responses, and submit.
5. If the ATS requires a new password or security verification not already available, mark `blocked-auth` and continue to the next job.
6. Verify submission confirmation and log it.

## Application logging
Maintain `.job-apply-autopilot/applications.jsonl`, one JSON object per job:

```json
{"timestamp":"ISO-8601","status":"submitted|skipped-low-fit|blocked-auth|blocked-security|blocked-unknown-fact|failed","source":"linkedin-easy-apply|external","company":"...","title":"...","location":"...","job_url":"...","job_id":"...","score":0,"resume":"...","notes":"..."}
```

Before applying, dedupe by canonical URL/job ID and secondarily by normalized company+title+location.
