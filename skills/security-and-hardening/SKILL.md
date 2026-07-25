---
name: security-and-hardening
model: sonnet
effort: medium
description: "Assess and harden code that crosses trust boundaries. Use for user input, authentication, authorization, sessions, secrets, file uploads, webhooks, external APIs, server-side URL fetches, dependency changes, or AI features: 'security review', 'harden this', 'threat model', 'check auth', 'validate this webhook', 'prevent SSRF', or 'secure this endpoint'. Requires explicit approval before risky auth, CORS, privilege, or data-handling changes."
allowed-tools:
  - Bash
  - Read
scout:
  surface: developer
  effects: [report]
---

# Security And Hardening

Treat external input, browser and API responses, configuration, logs, uploaded files, and model output as
untrusted data. Start with a compact threat model before proposing controls.

## Threat model

For the changed feature, identify:

1. Trust boundaries: requests, forms, webhooks, files, queues, third-party APIs, URL fetches, and LLM
   prompts or output.
2. Assets: credentials, PII, tenant data, privileged actions, money movement, and service availability.
3. Abuse cases: spoofing, tampering, repudiation, disclosure, denial of service, and privilege escalation.
4. The smallest controls that address the credible risks.

## Always verify

- Validate untrusted input at system boundaries using an explicit schema or allowlist.
- Parameterize database queries and encode output. Do not send untrusted input to a shell, SQL query, file
  path, or HTML sink without appropriate validation and encoding.
- Check authorization for every protected action, not merely authentication.
- Keep secrets out of source, logs, prompts, browser storage, and error responses. If a secret may have
  been committed, stop and direct rotation before cleanup.
- Review dependency additions and lockfile changes. Use the package manager's native audit at the actual
  installation boundary; do not run forced audit remediation automatically.
- Restrict server-side URL fetches to approved HTTPS destinations, reject private or reserved addresses,
  and do not follow redirects unless the design explicitly supports safe handling.
- Treat model output as data. Validate structured output, scope tools to least privilege, cap cost and
  recursion, and require confirmation for destructive actions.

## Approval gates

Ask the user before changing authentication or session flows, authorization or roles, CORS policy, rate
limits, sensitive-data categories, external integrations, file-upload behavior, privilege grants, or
production security settings. In dispatched work, report the proposed change and stop at these gates.

## Verification

Report the trust boundaries, abuse cases considered, controls added or verified, commands run, and residual
risk. Where applicable, verify headers, authorization failure paths, validation failures, audit findings,
and no secret exposure in the staged diff. This skill reports and guides changes; it does not commit,
deploy, rotate credentials, or alter production access on its own.
