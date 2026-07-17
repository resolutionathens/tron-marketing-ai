# Rubric Consumer Roles

Use the shared ticket rubric consistently across its three consumers:

- `tron:create-ticket` prevents thin new tickets by collecting grounded markers before creation.
- `tron:ticket-lint` checks an existing ticket without changing it.
- `tron:jira-source-discovery` plus `tron:jira-ticket-enricher` repairs an existing thin ticket by gathering sources, drafting a rubric-compliant description, and writing it after approval.
- Scout triage parses the same markers deterministically. Changes to marker semantics belong in `tools/ticket/ticket-rubric.md`, not in an individual consumer skill.
