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

Exit codes: `0` ok · `2` usage error · `3` no reachable OKF source (`TRON_API_URL`/`--api-url`
unset **and** no usable broker token) · `4` HTTP / network error.

`query` requires at least one filter (`--type`, `--tags`, or `--id-prefix`) so it never pulls the
whole bundle, and caps loaded bodies at `--limit` (default 8), warning when it truncates.

## Direct-broker fallback (MD-2066)

The primary transport is the control-plane API (`TRON_API_URL`). If a worker's dispatch has **no**
control-plane channel (`TRON_API_URL` and `--api-url` both unset) but does have direct access to
the org-secret broker, the CLI falls back to querying the broker's `/knowledge/*` surface
directly rather than failing outright. It mints a short-lived Cloudflare Access token the same way
the other broker-backed tools do (`cloudflared access token`) and runs the **same** select/load
filter locally over the fetched manifest — so the command shape, output, and exit codes are
unchanged; only the transport differs. See [`tools/broker/README.md`](../broker/README.md) for the
shared broker pattern this reuses.

| Env var | Default | Purpose |
| --- | --- | --- |
| `OKF_BROKER_APP` | `https://secrets.facilitron.work` | `cloudflared` Access app for token minting |
| `OKF_BROKER_BASE` | `https://secrets.facilitron.work/knowledge` | knowledge surface base (manifest + bodies) |
| `OKF_ACCESS_TOKEN` | _(unset)_ | short-circuits `cloudflared` (tests, or a worker that already holds a token) |

The fallback expects the broker to serve `${OKF_BROKER_BASE}/manifest.json` (the concept manifest,
a `[{ id, type, tags, title, … }]` array or `{ concepts: [...] }`) and each body at
`${OKF_BROKER_BASE}/<id>.md`. The base is env-overridable so this layout can be corrected in config
rather than code if the OS-side broker path ever differs.

> The broker path is only exercised when `TRON_API_URL` is absent — which no real dispatch does
> today (`lib/tmux.ts` injects it into every worker). It is verified hermetically (see below); the
> live `/knowledge/*` surface still needs a real-broker confirmation before it is relied on.

## Requirements

- Node 18+ (global `fetch`, `AbortController`). Zero npm dependencies.
- `TRON_API_URL` in the environment (dispatched workers have it) or `--api-url`; **or**, for the
  fallback, a reachable broker plus `cloudflared` (or a preset `OKF_ACCESS_TOKEN`).

Node's `fetch` sends no `Origin` header, so `POST /api/okf/load` passes the control-plane CSRF
guard (which only rejects cross-origin browser requests).

## Test

```bash
bash tools/okf/test-okf.sh   # hermetic: stubs the two endpoints on loopback, no tron-os needed
```
