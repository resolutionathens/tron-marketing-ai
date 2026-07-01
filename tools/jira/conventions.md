# Jira Conventions

## Summary prefixes (MD project)

When creating tickets in the MD project, prefix the summary with an all-caps identifier matching the repo or system the work belongs to. This makes board scanning and agent routing easier.

| Repo / system | Prefix |
|---|---|
| `tron-marketing-ai` (this plugin) | `TRON-PLUGIN:` |
| `scout` / `tron-os` | `SCOUT:` |
| `marketing-pages` | `PAGES:` |
| `marketing-dynamic-landing-pages` | `LLLP:` |
| `mabe-nuxt` | `MABE:` |
| `facilitron-support` | `SUPPORT:` |
| `facilitron-ui` | `UI:` |

Format: `PREFIX: short imperative description` — e.g. `TRON-PLUGIN: build tools/image/image-pipeline.sh`.

This table is canonical — it mirrors the `repoForSummaryPrefix` test fixture in the SCOUT
(`tron-os`) repo. If you change a prefix here, it must change there too, and vice versa.

If it's not clear which repo a ticket belongs to, ask the user rather than guessing a prefix.
