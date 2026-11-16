# Rubric Consumer Roles

Use the shared ticket rubric consistently across its three consumers:

- `tron:create-ticket` prevents thin new tickets by collecting grounded markers before creation, including
  optional `Intent:` only when sources establish the desired outcome.
- `tron:ticket-lint` checks an existing ticket without changing it and reports a missing `Intent:` only as
  advisory.
- `tron:jira-source-discovery` plus `tron:jira-ticket-enricher` repairs an existing thin ticket by gathering
  sources, drafting a rubric-compliant description, and writing it after approval; enrichment never invents
  `Intent:`.
- For product, engineering, bug, data and spike tickets, all three use the pilot template
  (`tools/ticket/pilot-template.md`, rubric-version 5): the Stakeholder is always the user's answer, an
  engineering ticket's brief is its `<KEY>-engineering.md` attachment, and the lint grades the ticket for
  the stage its Jira status maps to, naming each missing field or section.
- Scout triage parses the same markers deterministically. Changes to marker semantics belong in `tools/ticket/ticket-rubric.md`, not in an individual consumer skill.
