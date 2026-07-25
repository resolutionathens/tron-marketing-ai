---
name: code-review-and-quality
model: sonnet
effort: medium
description: "Review a code change before merge for correctness, readability, architecture, security, performance, and verification evidence. Use when asked to review code, inspect a diff, check PR quality, assess a feature before merge, or find risks in an implementation: 'review this change', 'code review', 'is this ready to merge', 'check this diff', or 'review my PR'. Complements OpenRouter PR review and does not create or merge PRs."
allowed-tools:
  - Bash
  - Read
  - Skill
scout:
  surface: developer
  effects: [report]
---

# Code Review And Quality

Review the change against its ticket, source material, and repository conventions before judging style.
Read tests before implementation where they exist. Report findings first, ordered by severity and with
file and line references when available.

## Review axes

1. **Correctness:** Does the change meet acceptance criteria, preserve edge cases, and handle error paths?
   Are tests behavioral and sufficient to catch a regression?
2. **Readability:** Are names, control flow, and module responsibilities clear? Prefer the smallest
   correct change. Flag indirection, dead code, silent fallbacks, and conditionals bolted onto unrelated
   flows.
3. **Architecture:** Does the change follow established patterns and keep feature logic in its owning
   layer? Favor a small interface at a clean seam, with locality and testability, over shallow pass-through
   abstractions or duplicate helpers.
4. **Security:** Check trust boundaries, validation, authorization, secrets, dependency changes, and
   external data handling. Delegate a deeper assessment to `tron:security-and-hardening` when relevant.
5. **Performance:** Look for unbounded work, N+1 access, unnecessary rendering, payload growth, and hot
   paths. Use `tron:site-audit` or the available performance tooling for measured web performance work.
6. **Verification:** Confirm the author ran appropriate tests, build checks, manual or browser verification,
   and CI checks. Evidence matters more than an assertion that the change works.

## Findings and verdict

Use these labels:

- `Critical`: security exposure, data loss, broken behavior, or release blocker.
- `Required`: a defect or material regression that must change before merge.
- `Optional`: a concrete improvement that is not required for correctness.
- `Nit`: a minor preference that does not need action.
- `FYI`: context only.

For every material finding, state the risk and propose a specific remedy. Do not bury a correctness or
security issue beneath cosmetic comments. If no findings exist, say so and name residual testing gaps.

## Boundaries

- Do not rubber-stamp a change because tests pass.
- Do not require unrelated cleanup or a preferred rewrite when the current change improves code health.
- Keep review comments about code and evidence, not people.
- This skill complements independent PR review where available. It does not post a review, create a PR,
  merge, commit, or deploy.
