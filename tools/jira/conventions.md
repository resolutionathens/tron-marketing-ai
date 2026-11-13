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

## Assignee

Assign every MD-project ticket to its creator on creation with `--assignee '@me'`. This routes a
ticket **you** create to you, and a **teammate's** ticket to them — which is correct even in the
repos shared with the wider team (`marketing-pages`, `marketing-dynamic-landing-pages`). Don't
hard-code a specific person's email here; `@me` is the whole point.

This table is canonical — it mirrors the `repoForSummaryPrefix` test fixture in the SCOUT
(`tron-os`) repo. If you change a prefix here, it must change there too, and vice versa.

If it's not clear which repo a ticket belongs to, ask the user rather than guessing a prefix.

## Dependency links (Blocks, Relates)

Create, delete, and replace issue links only through `tools/jira/jira-link.sh`, never with raw
`acli jira workitem link create/delete`. **acli's success message prints the reverse of what it
stores:** `link create --out A --in B --type Blocks` stores "A is blocked by B" and then prints
"(A Blocks B)". Its help calls `--out` the outward work item, so both the help and the success line
lead you to the wrong direction, and a "fix" based on them stores the reverse (MD-3397).

The helper takes the direction in plain words, maps it to the right flags, reads the link back from
Jira, and exits `3` naming both issues if the stored direction is reversed:

```bash
L="$PLUGIN_ROOT/tools/jira/jira-link.sh"
bash "$L" create "MD-3396 blocks MD-3268"           # also: "<A> is blocked by <B>", "<A> relates to <B>"
bash "$L" show MD-3268                              # every link on an issue: id + plain words
bash "$L" delete 126430 "MD-3268 is blocked by MD-3396"
bash "$L" replace 126430 "MD-3268 blocks MD-3396"   # correct a link in place
```

`delete` and `replace` take the link id from `show`, plus the statement (or, for `replace`, the two issues and link type) that id
must be. The helper refuses (exit `4`) when the id is a different link, so a correction cannot remove
an unrelated link on the same issue. Never pick an id from `acli jira workitem link list`: it omits
the other issue's key, so two Blocks links on one issue look identical. To cross-check by hand, the
issue changelog (`/rest/api/3/issue/<KEY>/changelog`) says "This work item blocks X" or "is blocked
by X" in plain words.
