# ATS Authentication Policy V4 — OAuth First

## Goal
Minimize application friction. The user permits autonomous password generation/autofill, but OAuth and existing sessions are usually faster and should be attempted first.

## Authentication priority

1. existing authenticated ATS session,
2. `Continue with LinkedIn` / `Sign in with LinkedIn` / `Apply with LinkedIn`,
3. `Import from LinkedIn` / `Use LinkedIn profile` / LinkedIn resume import,
4. another already-authenticated OAuth provider when clearly appropriate,
5. password account creation.

## LinkedIn OAuth detection
Before filling account-creation fields, inspect visible buttons/links and page text for:

- LinkedIn logo/buttons,
- Continue with LinkedIn,
- Sign in with LinkedIn,
- Apply with LinkedIn,
- Import profile from LinkedIn,
- Autofill with LinkedIn,
- Use LinkedIn profile.

If present, use it before creating a password account.

## OAuth consent
The user has authorized autonomous job applications and specifically prefers LinkedIn OAuth. It is acceptable to approve ordinary OAuth access necessary to identify the candidate or import professional profile/contact data.

If a consent screen requests unusual permissions unrelated to applying, such as posting content/messages or broad destructive account access, do not approve those permissions; use password flow instead.

## Password fallback
If no suitable OAuth/import path exists:

- generate a strong unique password,
- autofill it,
- proceed autonomously,
- use browser/password-manager save if naturally offered and safe,
- do not let password creation become a blocker.

The application ledger does not need to contain the password.

## Profile import
When LinkedIn OAuth/import populates fields, verify critical facts before submission:

- name,
- email,
- phone/country,
- location,
- LinkedIn URL,
- work history dates/titles if imported,
- selected resume.

Correct stale or contradictory imported data using the verified profile/canonical facts.

## Do not confuse OAuth success with eligibility
A site allowing LinkedIn OAuth or accepting a profile from Pakistan does not prove the role hires in Pakistan. Eligibility must still pass `eligibility-policy.md`.
