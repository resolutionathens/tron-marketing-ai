# `tools/okf` — OKF query CLI

The client half of on-demand mid-task OKF querying (MD-1997). Lets a **running worker** pull
OKF playbooks by type / tags mid-task instead of relying only on what was front-loaded into its
standing rules at launch. Consumed by the [`tron:okf-query`](../../skills/okf-query/SKILL.md) skill.

## Why it exists

A dispatched worker runs inside the target repo's worktree (marketing-pages, facilitron-ui,
tron-marketing-ai, …), **not** inside tron-os. It cannot import `lib/okf-client.ts` and the
`knowledge/` OKF bundle does not travel with it. Its only channel back to the OS is HTTP over
`TRON_API_URL` (the control-plane API that dispatched it, already in the worker's env via
`lib/tmux.ts`). This CLI calls the OS-side query surface shipped in MD-1988:

| Endpoint | Shape | Cost |
| --- | --- | --- |
| `GET  {TRON_API_URL}/api/okf/select?type=&tags=&idPrefix=` | `{ concepts: [{ id, type, tags, title, description, timestamp }] }` | cheap — manifest filter, no bodies |
| `POST {TRON_API_URL}/api/okf/load` `{ ids: string[] }` | `{ bodies: { [id]: markdown } }` | bodies for the selected ids only |

It reuses the MD-1943 **select-then-load** shape: filter the manifest first (cheap), then fetch
bodies only for the ids you actually want — never the whole bundle. The OS decides local-vs-broker
backend behind that HTTP surface (`createOkfClientFromConfig`); this client does **not** reimplement
query logic and does **not** read the bundle from disk. Per the OS ↔ Plugin boundary, the OS owns
the data + query logic + HTTP surface (MD-1988); the plugin owns the affordance the worker invokes.

## Usage

```bash
OKF="${CLAUDE_PLUGIN_ROOT:-.}/tools/okf/okf.mjs"

node "$OKF" select --type Policy                     # preview matches (no bodies)
node "$OKF" select --tags git,lifecycle              # AND semantics across tags
node "$OKF" select --id-prefix role/                 # by id prefix
node "$OKF" load policy/git-flow role/worker         # bodies for specific ids
node "$OKF" query --type Policy --tags git --limit 4 # one-shot: select then load matched bodies
node "$OKF" help
```

Global flags: `--api-url <url>` (overrides `TRON_API_URL`), `--timeout <ms>` (default 15000),
`--json` (raw JSON instead of the formatted table / bodies).

Exit codes: `0` ok · `2` usage error · `3` no API base URL (`TRON_API_URL` unset and no `--api-url`)
· `4` HTTP / network error.

`query` requires at least one filter (`--type`, `--tags`, or `--id-prefix`) so it never pulls the
whole bundle, and caps loaded bodies at `--limit` (default 8), warning when it truncates.

## Requirements

- Node 18+ (global `fetch`, `AbortController`). Zero npm dependencies.
- `TRON_API_URL` in the environment (dispatched workers have it) or `--api-url`.

Node's `fetch` sends no `Origin` header, so `POST /api/okf/load` passes the control-plane CSRF
guard (which only rejects cross-origin browser requests).

## Test

```bash
bash tools/okf/test-okf.sh   # hermetic: stubs the two endpoints on loopback, no tron-os needed
```
