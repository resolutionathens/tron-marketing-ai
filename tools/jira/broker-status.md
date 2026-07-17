# Jira auth: why acli stays direct (MD-1995)

The org-secret broker (`secrets.facilitron.work`, MD-1994) proxies Jira Cloud REST
1:1 at `/jira/*` — a caller points its Jira base URL at the broker instead of
`facilitron.atlassian.net` and gets the same responses back, authenticated with a
shared `jira-api-token` the broker holds server-side.

`acli` cannot be pointed at that proxy. Checked directly (`acli jira auth login
--help`, `acli config --help`): the only auth methods are `--web` (OAuth) or
`--site/--email/--token`, and `--site` requires the literal Atlassian hostname —
there is no flag or config file for a custom base URL / proxy. `acli`'s Jira
session is also already independent of `JIRA_API_TOKEN`/`ATLASSIAN_EMAIL`: it
authenticates via its own per-user OAuth login (`acli jira auth status` shows
`Authentication Type: oauth`), so those two env vars were never actually in the
request path for any `acli`-based skill.

Routing these skills through the broker would mean bypassing `acli` entirely and
hand-rolling the REST calls it already wraps (search, view, comment, transition,
assign, create) — reintroducing the raw-REST-call approach this repo's worker
rules warn against, for a large surface, to fix an env var these skills don't
read. So the `acli`-based skills (`jira`, `jira-comment`,
`enrich-jira-ticket`, `jira-source-discovery`, `jira-ticket-enricher`, `board-triage`, `start-ticket`, `weekly-update`) stay on
`acli`'s own OAuth session per MD-1995's documented-exception path. Revisit if
`acli` ever adds a custom-host/proxy flag.

What *did* cut over under MD-1995: `tools/confluence/fetch-confluence.sh`'s page-body
and attachment-listing calls, which hit `facilitron.atlassian.net` directly (not
through `acli`) and so could be pointed at the broker's `/jira/*` proxy. The
attachment *download* leg also cut over under MD-2085 — it now routes through the
broker's `/jira/confluence-attachments/*` proxy (instead of hitting `api.atlassian.com`
directly with `JIRA_API_TOKEN`/`ATLASSIAN_EMAIL`).
