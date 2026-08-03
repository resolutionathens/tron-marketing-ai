# The org-secret broker (`secrets.facilitron.work`)

The **org-secret broker** is a Cloudflare-Access-fronted reverse proxy (MD-1858 / MD-1994) that
holds Facilitron's shared credentials **server-side** and proxies a handful of third-party APIs
1:1. A tool points its base URL at the broker instead of the real host and gets the same
responses back, authenticated with a secret the broker holds — so no ImageKit private key, Figma
token, CircleCI token, or Jira token ever has to live on the caller's machine. The broker itself
lives in **tron-os**; this doc is the plugin-side reference for the skills and tools that call it.

## Contents

- [Why it exists](#why-it-exists)
- [Authentication (Cloudflare Access)](#authentication-cloudflare-access)
- [Proxied surfaces](#proxied-surfaces)
- [The broker-first-with-fallback pattern](#the-broker-first-with-fallback-pattern)
- [Consumers in this repo](#consumers-in-this-repo)
- [Env overrides (for tests)](#env-overrides-for-tests)
- [Troubleshooting](#troubleshooting)

## Why it exists

Org-shared API credentials are a liability when they are copied onto every contributor's laptop
and every dispatched worker: they leak, they rotate out of sync, and they show up in `~/.env`
files that outlive the person. The broker centralizes them. Callers authenticate as **themselves**
(their Facilitron Google identity, via Cloudflare Access) and the broker attaches the real
service credential on the far side. Rotating a secret is then a one-place change on the broker,
not a fleet-wide `~/.env` edit.

## Authentication (Cloudflare Access)

One-time SSO login, cached and auto-refreshed:

```bash
cloudflared access login https://secrets.facilitron.work
```

Per request, mint a short-lived token and send it as the `CF-Access-Token` header:

```bash
TOKEN="$(cloudflared access token --app=https://secrets.facilitron.work)"
curl -s -H "CF-Access-Token: $TOKEN" "https://secrets.facilitron.work/<service>/<path>"
```

`cloudflared` is the only local dependency. There is no per-service token to manage — the token is
your Access session, scoped to the whole `secrets.facilitron.work` app (so one token works across
every proxied surface below).

## Proxied surfaces

Each service is mounted under a path prefix and mirrors the upstream API 1:1 — swap the host and
prefix in and every downstream path/query/body is unchanged.

| Prefix | Upstream | Used by |
| --- | --- | --- |
| `/imagekit/*` | ImageKit REST + upload API | `tools/imagekit/imagekit.mjs` (content image pipeline) |
| `/figma/*` | Figma REST API | `tron:figma-inspect` (per-user, read-only inspection), `tron:figma-to-imagekit` (asset export) |
| `/circleci/*` | CircleCI v2 API | `tron:circleci` (`skills/circleci/scripts/circleci.sh`) |
| `/jira/*` | Jira Cloud REST + Confluence page body / listing | `tools/confluence/fetch-confluence.sh` (MD-1995) |
| `/jira/confluence-attachments/*` | Confluence attachment downloads | `tools/confluence/fetch-confluence.sh` (MD-2085) |
| `/knowledge/*` | OKF knowledge bundle | `tools/okf/okf.mjs` direct-broker fallback (MD-2066) |

Not everything is proxied yet. `acli`'s Jira session stays on its own OAuth login and does
**not** route through the broker — see [`tools/jira/broker-status.md`](../jira/broker-status.md) for why.

## The broker-first-with-fallback pattern

Broker-backed tools do not hard-depend on the broker being reachable. Each has a documented
**fallback transport**, so a `cloudflared` outage, a TLS handshake failure, or a missing Access
token degrades gracefully instead of dead-ending:

- **`imagekit.mjs`** — broker first, then the **direct ImageKit API** with `IMAGEKIT_PRIVATE_KEY`
  (from env or `~/.env`). It falls back on any connectivity/TLS error or a missing token and
  prints a one-line notice on stderr (CCAL-1973/1974).
- **`fetch-confluence.sh`** — broker first, then **direct** `facilitron.atlassian.net` with
  `JIRA_API_TOKEN`/`ATLASSIAN_EMAIL` (MD-1995).
- **`okf.mjs`** — here the broker is itself the *fallback*, not the primary: a worker normally
  reaches OKF through the control-plane API (`TRON_API_URL`), and only when that channel is
  absent does it hit the broker's `/knowledge/*` surface directly (MD-2066). The inverse
  direction, same auth mechanism.

The token is resolved **without dying** (returns null on failure) so the caller can choose the
fallback rather than aborting. Copy this shape when adding a new broker-backed tool: try the
broker, catch connectivity failure (or a null token), retry against the direct API with a locally
held credential, and name the actual missing requirement if the fallback also can't proceed.

## Consumers in this repo

- `tools/imagekit/imagekit.mjs` — `/imagekit/*`
- `tools/confluence/fetch-confluence.sh` — `/jira/*` (consumed by `tron:confluence`,
  `tron:news-item`, `tron:guide-item`)
- `tools/okf/okf.mjs` — `/knowledge/*` (fallback; consumed by `tron:okf-query`)
- `skills/circleci/scripts/circleci.sh` — `/circleci/*`
- `skills/figma-to-imagekit/SKILL.md` — `/figma/*`
- `skills/figma-inspect/scripts/figma-inspect.mjs` — `/figma/*` with the caller's connected Figma OAuth identity

## Env overrides (for tests)

Every broker-backed tool makes its hosts env-overridable so the broker path is testable against a
loopback stub — no `cloudflared`, no real broker, fully offline. Conventions per tool:

| Tool | App override | Base override | Token short-circuit |
| --- | --- | --- | --- |
| `imagekit.mjs` | `IMAGEKIT_BROKER_APP` | `IMAGEKIT_BROKER_BASE` / `IMAGEKIT_BROKER_UPLOAD` | `IMAGEKIT_ACCESS_TOKEN` |
| `fetch-confluence.sh` | `CONFLUENCE_BROKER_APP` | `CONFLUENCE_BROKER_BASE` | (Access session) |
| `okf.mjs` | `OKF_BROKER_APP` | `OKF_BROKER_BASE` | `OKF_ACCESS_TOKEN` |
| `figma-inspect.mjs` | `FIGMA_BROKER_APP` | `FIGMA_BROKER_BASE` | `FIGMA_INSPECT_ACCESS_TOKEN` |

Setting the `*_ACCESS_TOKEN` var skips `cloudflared` entirely (hand it a dummy token in tests);
pointing the `*_BASE` var at a loopback server exercises the broker code path without the network.

## Troubleshooting

- **`no Cloudflare Access token` / broker auth error** — your Access session expired. Re-run
  `cloudflared access login https://secrets.facilitron.work`.
- **`cloudflared not found`** — install `cloudflared`; it is the only local dependency for broker
  auth. Tools with a direct-API fallback will use it instead if a local credential is present.
- **TLS handshake failure to the broker** (LibreSSL `tlsv1 alert protocol version`) — a known
  intermittent condition on some workers; see [tron-os broker known
  issues](https://github.com/resolutionathens/tron-os/blob/3086c8402611369e59af12cbbcf5e5de2f00ded0/knowledge/playbooks/org-secret-broker.md#known-issues)
  for details. The fallback path exists precisely for this.
- **Pi harness behavior** — skills run identically under the experimental pi harness.
