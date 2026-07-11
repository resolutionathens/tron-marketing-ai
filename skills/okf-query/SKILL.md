---
name: okf-query
model: haiku
effort: low
description: "Pull OKF playbooks (policies, role overlays, conventions, house rules) by type/tags mid-task, on demand, over the control-plane API — for a running dispatched worker that needs a specific playbook it was not front-loaded with. Use when you're mid-task and need the canonical way this org does something and it isn't already in your standing rules: 'is there a playbook for X', 'what's our convention for X', 'how do we handle X here', 'pull the OKF for X', 'check the standing rules for X', 'fetch the git-flow / release / worktree policy', 'what does the OKF say about X', 'load the role overlay', 'query the knowledge base for X'. Filters the manifest first (cheap), then fetches only the bodies you pick (select then load). Requires TRON_API_URL (dispatched workers have it); read-only."
allowed-tools:
  - Bash
scout:
  surface: false
---

# OKF query — pull playbooks mid-task

OKF (the org knowledge bundle: Policies, Role overlays, and other concept types) is the
canonical source for how this org does things. A dispatched worker gets a slice of it
front-loaded into its standing rules at launch, but not the whole brain. When you're mid-task
and need a playbook you weren't handed, pull it on demand instead of guessing.

You run inside the target repo's worktree, not inside tron-os, so you can't read the bundle
from disk. Your channel back is HTTP over **`TRON_API_URL`** (already in your env). This skill
calls the OS-side query surface (`GET /api/okf/select`, `POST /api/okf/load`) via the bundled
`tools/okf/okf.mjs` CLI. The OS owns the data and query logic; this skill is just the
affordance you invoke.

## When to reach for it

- You need the canonical convention for something and it isn't in your standing rules already.
- You're about to make a judgment call (a git flow, a release step, a naming rule, a voice
  rule) and want to confirm the org has a documented playbook first.
- Do **not** use it to re-fetch rules you were already front-loaded with — check what you have
  first. This is for the gap, not a bulk reload.

## Workflow: select then load

The whole point is fetching only what you need. Two cheap steps:

1. **select** — filter the manifest by `type`, `tags`, and/or `id-prefix`. Returns matching
   concept ids + titles, **no bodies**. Cheap. Use it to see what exists.
2. **load** — fetch the markdown bodies for the specific ids you chose.

For a quick one-shot when you already know the filter is narrow, `query` does both (select,
then load the matches, capped by `--limit`).

## Fast path

Resolve the CLI, then run a command. `TRON_API_URL` comes from your env; the CLI errors
clearly (exit 3) if it's missing, in which case fall back to the playbooks you were launched
with.

```bash
OKF="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/okf/okf.mjs"

# 1) See what playbooks exist for a topic (no bodies — cheap)
node "$OKF" select --tags git                 # all concepts tagged "git"
node "$OKF" select --type Policy              # every Policy
node "$OKF" select --id-prefix role/          # by id prefix

# 2) Load only the bodies you actually want
node "$OKF" load policy/git-flow role/worker

# One-shot when the filter is already narrow (select + load, capped):
node "$OKF" query --type Policy --tags git --limit 4
```

Tag filtering is AND (a concept must carry every tag you list). `query` refuses to run with no
filter so it never pulls the whole bundle.

### Flags

- `--type <T>` — exact OKF type (e.g. `Policy`, `Role`).
- `--tags <a,b>` — comma-separated; concept must carry all of them.
- `--id-prefix <P>` — ids starting with `P`.
- `--limit <N>` — (query) cap bodies loaded; default 8, warns when it truncates.
- `--json` — raw JSON instead of the formatted table / bodies.
- `--api-url <url>` — override `TRON_API_URL`. `--timeout <ms>` — default 15000.

## After you load

Read the returned playbook and apply it to the task at hand — it's authoritative for how the
org wants the thing done. If a playbook contradicts what you were about to do, follow the
playbook (unless your current ticket explicitly overrides it).

## Notes

- **Read-only.** This skill fetches playbooks; it never writes, branches, or commits.
- Reuses the MD-1943 select-then-load pattern and does not reimplement the OKF query logic that
  lives in tron-os `lib/okf-client.ts` — it calls the MD-1988 HTTP surface. See
  [tools/okf/README.md](../../tools/okf/README.md) for the endpoint contract.
- If `TRON_API_URL` is unset (some dispatches don't pass it), the CLI falls back to querying the
  org-secret broker's `/knowledge` surface directly with a `cloudflared` Access token (MD-2066;
  see [tools/broker/README.md](../../tools/broker/README.md)). Only if there's no control-plane
  URL **and** no reachable broker (or the API/broker is unreachable) does it exit non-zero — then
  degrade gracefully to your front-loaded rules rather than blocking.
