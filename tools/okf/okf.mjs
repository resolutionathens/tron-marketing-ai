#!/usr/bin/env node
/**
 * OKF query CLI (MD-1997) — the client half of on-demand mid-task OKF querying.
 *
 * A dispatched worker runs inside the target repo's worktree, NOT inside tron-os, so it
 * cannot import lib/okf-client.ts and the knowledge/ OKF bundle does not travel with it.
 * Its primary channel back to the OS is HTTP over TRON_API_URL (the control-plane API that
 * dispatched it, already in its env via lib/tmux.ts). This tool calls the OS-side query
 * surface shipped in MD-1988:
 *
 *   GET  {TRON_API_URL}/api/okf/select?type=&tags=&idPrefix=  → { concepts: [...] }   (cheap: manifest filter, no bodies)
 *   POST {TRON_API_URL}/api/okf/load     { ids: string[] }    → { bodies: { id: md } } (bodies for selected ids only)
 *
 * It reuses the MD-1943 select-then-load shape: filter the manifest first (cheap), then
 * fetch bodies ONLY for the ids you actually want — never the whole bundle. When TRON_API_URL
 * is present the OS decides local-vs-broker backend behind that HTTP surface
 * (createOkfClientFromConfig); this client does not reimplement query logic and does not read
 * the bundle from disk.
 *
 * Direct-broker fallback (MD-2066): if neither TRON_API_URL nor --api-url is set, the worker
 * has no control-plane channel. Rather than giving up immediately, it tries the org-secret
 * broker (secrets.facilitron.work, MD-1858) directly — the same host the OS uses in broker
 * mode and that tools/imagekit/imagekit.mjs, tron:circleci, and the Confluence fetch already
 * authenticate against (see tools/broker/README.md). It mints a short-lived Cloudflare Access
 * token via `cloudflared access token` and fetches the knowledge bundle over HTTP, then runs
 * the SAME select/load filter locally. Only this last-resort transport differs; the command
 * shape, output, and exit codes are unchanged. All broker hosts/paths are env-overridable so
 * the fallback is testable without the real broker.
 *
 * Zero dependencies: Node 18+ global fetch. Node's fetch sends no Origin header, so the
 * POST /load call passes the control-plane CSRF guard (which only rejects cross-origin
 * browser requests).
 *
 * Commands:
 *   select [--type T] [--tags a,b] [--id-prefix P] [--json]     preview matching concepts (id/type/tags/title), no bodies
 *   load <id> [<id>...] [--json]                                 fetch bodies for the given concept ids
 *   query [--type T] [--tags a,b] [--id-prefix P] [--limit N] [--json]
 *                                                                one-shot: select, then load the matched bodies (capped by --limit)
 *   help                                                         usage
 *
 * Global flags: --api-url <url> (overrides TRON_API_URL), --timeout <ms> (default 15000).
 * Broker fallback env (all optional, all overridable): OKF_BROKER_APP (cloudflared Access app,
 * default https://secrets.facilitron.work), OKF_BROKER_BASE (knowledge surface base, default
 * https://secrets.facilitron.work/knowledge), OKF_ACCESS_TOKEN (short-circuits cloudflared).
 * Exit codes: 0 ok · 2 usage error · 3 no reachable OKF source (no TRON_API_URL/--api-url and no
 * usable broker token) · 4 HTTP/network error.
 */

import { spawnSync } from "node:child_process";

const [, , command, ...rest] = process.argv;

const DEFAULT_TIMEOUT_MS = 15000;
const DEFAULT_QUERY_LIMIT = 8;

// Broker fallback config (MD-2066). All env-overridable so the fallback is testable without
// the real broker, and so the knowledge surface path can be corrected in config rather than
// code if the OS-side layout ever differs. See tools/broker/README.md for the shared pattern.
const BROKER_APP = process.env.OKF_BROKER_APP || "https://secrets.facilitron.work";
const BROKER_BASE = (process.env.OKF_BROKER_BASE || "https://secrets.facilitron.work/knowledge").replace(/\/+$/, "");

// ── arg parsing ──────────────────────────────────────────────────────────────

function parseArgs(argv) {
  const flags = {};
  const positional = [];
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--json") flags.json = true;
    else if (a === "--type") flags.type = argv[++i];
    else if (a === "--tags") flags.tags = argv[++i];
    else if (a === "--id-prefix" || a === "--idPrefix") flags.idPrefix = argv[++i];
    else if (a === "--limit") flags.limit = argv[++i];
    else if (a === "--api-url") flags.apiUrl = argv[++i];
    else if (a === "--timeout") flags.timeout = argv[++i];
    else if (a.startsWith("--")) die(`unknown flag: ${a}`, 2);
    else positional.push(a);
  }
  return { flags, positional };
}

function die(msg, code = 2) {
  process.stderr.write(`okf: ${msg}\n`);
  process.exit(code);
}

function timeoutMs(flags) {
  const n = flags.timeout ? Number(flags.timeout) : DEFAULT_TIMEOUT_MS;
  return Number.isFinite(n) && n > 0 ? n : DEFAULT_TIMEOUT_MS;
}

// Comma-separated tags → trimmed, non-empty array. Shared by the broker manifest filter.
function parseTags(tags) {
  return tags
    ? tags
        .split(",")
        .map((t) => t.trim())
        .filter(Boolean)
    : [];
}

// The select filter, applied locally to a manifest (broker path). Mirrors the OS-side
// routes/okf.ts predicate exactly: type is exact, idPrefix is a prefix, tags are AND. Keeping
// one predicate here is what makes the broker fallback a transport swap, not a behavior change.
function applyManifestFilter(concepts, { type, tags, idPrefix }) {
  const wantTags = parseTags(tags);
  return concepts.filter((c) => {
    if (type && c.type !== type) return false;
    if (idPrefix && !(c.id || "").startsWith(idPrefix)) return false;
    if (wantTags.length) {
      const have = new Set(Array.isArray(c.tags) ? c.tags : []);
      if (!wantTags.every((t) => have.has(t))) return false;
    }
    return true;
  });
}

// ── shared HTTP ────────────────────────────────────────────────────────────────

async function apiFetch(url, init, ms) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), ms);
  let res;
  try {
    res = await fetch(url, { ...init, signal: ctrl.signal });
  } catch (err) {
    const reason = err?.name === "AbortError" ? `timed out after ${ms}ms` : err?.message || String(err);
    die(`request to ${url} failed: ${reason}`, 4);
  } finally {
    clearTimeout(t);
  }
  if (!res.ok) {
    let detail = "";
    try {
      detail = ` — ${(await res.text()).slice(0, 300)}`;
    } catch {
      /* best effort */
    }
    die(`${url} returned HTTP ${res.status}${detail}`, 4);
  }
  try {
    return await res.json();
  } catch {
    die(`${url} returned a non-JSON body`, 4);
  }
}

// ── control-plane API transport (primary — TRON_API_URL / --api-url) ────────────

// Attributes this query/load to the dispatch's memoryUse record server-side (MD-2187),
// matching the OS-authored direct-curl affordance. Omitted entirely when TRON_DISPATCH_ID is
// unset (interactive/non-dispatched use), so unattributed requests are unchanged.
function dispatchHeaders() {
  return process.env.TRON_DISPATCH_ID ? { "x-tron-dispatch-id": process.env.TRON_DISPATCH_ID } : {};
}

async function apiSelect(base, { type, tags, idPrefix }, ms) {
  const qs = new URLSearchParams();
  if (type) qs.set("type", type);
  if (tags) qs.set("tags", tags);
  if (idPrefix) qs.set("idPrefix", idPrefix);
  const url = `${base}/api/okf/select${qs.toString() ? `?${qs}` : ""}`;
  const data = await apiFetch(url, { method: "GET", headers: dispatchHeaders() }, ms);
  return Array.isArray(data?.concepts) ? data.concepts : [];
}

async function apiLoad(base, ids, ms) {
  const url = `${base}/api/okf/load`;
  const data = await apiFetch(
    url,
    {
      method: "POST",
      headers: { "content-type": "application/json", ...dispatchHeaders() },
      body: JSON.stringify({ ids }),
    },
    ms,
  );
  return data?.bodies && typeof data.bodies === "object" ? data.bodies : {};
}

// ── direct-broker transport (MD-2066 fallback — no control-plane channel) ───────

// Cloudflare Access token for the broker, same mechanism as imagekit.mjs / circleci
// (tools/broker/README.md). OKF_ACCESS_TOKEN short-circuits cloudflared (tests, or a worker
// that already holds one). Returns null — rather than dying — so resolveTransport can report
// "no reachable source" and preserve the exit-3 contract.
function getBrokerToken() {
  if (process.env.OKF_ACCESS_TOKEN) return process.env.OKF_ACCESS_TOKEN;
  const result = spawnSync("cloudflared", ["access", "token", `--app=${BROKER_APP}`], {
    encoding: "utf-8",
    timeout: 15000,
  });
  if (result.status !== 0 || !result.stdout) return null;
  return result.stdout.trim();
}

// Fetch text from the broker. Returns null on 404 (a genuinely missing concept body, which the
// caller treats like the OS surface does: absent from the result), dies (exit 4) on any other
// transport/HTTP error, matching the API path's failure semantics.
async function brokerFetchText(url, token, ms) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), ms);
  let res;
  try {
    res = await fetch(url, { headers: { "CF-Access-Token": token }, signal: ctrl.signal });
  } catch (err) {
    const reason = err?.name === "AbortError" ? `timed out after ${ms}ms` : err?.message || String(err);
    die(`broker request to ${url} failed: ${reason}`, 4);
  } finally {
    clearTimeout(t);
  }
  if (res.status === 404) return null;
  if (!res.ok) {
    let detail = "";
    try {
      detail = ` — ${(await res.text()).slice(0, 300)}`;
    } catch {
      /* best effort */
    }
    die(`broker ${url} returned HTTP ${res.status}${detail}`, 4);
  }
  return await res.text();
}

async function brokerFetchJson(url, token, ms) {
  const text = await brokerFetchText(url, token, ms);
  if (text === null) die(`broker ${url} returned HTTP 404 (knowledge bundle not found on broker)`, 4);
  try {
    return JSON.parse(text);
  } catch {
    die(`broker ${url} returned a non-JSON body`, 4);
  }
}

// Broker select: pull the manifest once and filter it locally with the shared predicate.
// Accepts either a bare concepts array or { concepts: [...] } so it tolerates either wrapping.
async function brokerSelect(token, filters, ms) {
  const manifest = await brokerFetchJson(`${BROKER_BASE}/manifest.json`, token, ms);
  const concepts = Array.isArray(manifest) ? manifest : Array.isArray(manifest?.concepts) ? manifest.concepts : [];
  return applyManifestFilter(concepts, filters);
}

// Broker load: fetch each body by id. Ids look like "policy/git-flow"; bodies live at
// {base}/{id}.md. A 404 → the id is simply omitted (same as the OS surface returning only
// found ids), so the CLI's existing missing-id reporting still works. Bodies are fetched
// concurrently so the total wall-clock stays near a single request's timeout rather than
// summing one timeout per id (with the default --limit 8 the sequential version could take
// up to ~8× the timeout); each request still carries its own per-request timeout.
async function brokerLoad(token, ids, ms) {
  const bodies = {};
  const fetched = await Promise.all(
    ids.map((id) => brokerFetchText(`${BROKER_BASE}/${id}.md`, token, ms).then((md) => [id, md])),
  );
  for (const [id, md] of fetched) if (md !== null) bodies[id] = md;
  return bodies;
}

// ── transport resolution ────────────────────────────────────────────────────────

// Pick the transport: the control-plane API when TRON_API_URL/--api-url is available (primary,
// unchanged behavior), otherwise the direct-broker fallback. Dies with exit 3 only when there
// is no reachable OKF source at all (no API base AND no usable broker token).
function resolveTransport(flags, ms) {
  const base = (flags.apiUrl || process.env.TRON_API_URL || "").replace(/\/+$/, "");
  if (base) {
    return {
      select: (filters) => apiSelect(base, filters, ms),
      load: (ids) => apiLoad(base, ids, ms),
    };
  }
  const token = getBrokerToken();
  if (token) {
    return {
      select: (filters) => brokerSelect(token, filters, ms),
      load: (ids) => brokerLoad(token, ids, ms),
    };
  }
  die(
    "no reachable OKF source. Set TRON_API_URL (dispatched workers get it in their env) or pass " +
      "--api-url <url>; or, for the direct-broker fallback, make a Cloudflare Access token available " +
      `(install cloudflared if it is missing, then run: cloudflared access login ${BROKER_APP}; ` +
      "or set OKF_ACCESS_TOKEN directly). " +
      "Without any of these, fall back to the playbooks front-loaded at launch.",
    3,
  );
}

// ── formatting ───────────────────────────────────────────────────────────────

function printConceptTable(concepts) {
  if (concepts.length === 0) {
    process.stdout.write("No OKF concepts matched.\n");
    return;
  }
  const idW = Math.max(2, ...concepts.map((c) => (c.id || "").length));
  const typeW = Math.max(4, ...concepts.map((c) => (c.type || "").length));
  process.stdout.write(`${"ID".padEnd(idW)}  ${"TYPE".padEnd(typeW)}  TAGS / TITLE\n`);
  for (const c of concepts) {
    const tags = Array.isArray(c.tags) && c.tags.length ? `[${c.tags.join(", ")}] ` : "";
    const title = c.title || c.description || "";
    process.stdout.write(`${(c.id || "").padEnd(idW)}  ${(c.type || "").padEnd(typeW)}  ${tags}${title}\n`);
  }
  process.stdout.write(`\n${concepts.length} concept(s). Load bodies with: okf load ${concepts.map((c) => c.id).join(" ")}\n`);
}

function printBodies(concepts, bodies) {
  const byId = new Map(concepts.map((c) => [c.id, c]));
  const ids = Object.keys(bodies);
  if (ids.length === 0) {
    process.stdout.write("No bodies returned (ids not found).\n");
    return;
  }
  for (const id of ids) {
    const meta = byId.get(id);
    const label = meta && meta.type ? `${id} (${meta.type})` : id;
    process.stdout.write(`\n===== ${label} =====\n${bodies[id]}\n`);
  }
}

// ── commands ─────────────────────────────────────────────────────────────────

async function cmdSelect(flags) {
  const t = resolveTransport(flags, timeoutMs(flags));
  const concepts = await t.select(flags);
  if (flags.json) process.stdout.write(`${JSON.stringify(concepts, null, 2)}\n`);
  else printConceptTable(concepts);
}

async function cmdLoad(flags, ids) {
  if (ids.length === 0) die("load needs at least one concept id (okf load <id> [<id>...])", 2);
  const t = resolveTransport(flags, timeoutMs(flags));
  const bodies = await t.load(ids);
  if (flags.json) {
    process.stdout.write(`${JSON.stringify(bodies, null, 2)}\n`);
  } else {
    const concepts = ids.map((id) => ({ id, type: "" }));
    printBodies(concepts, bodies);
    const missing = ids.filter((id) => !(id in bodies));
    if (missing.length) process.stderr.write(`okf: not found: ${missing.join(", ")}\n`);
  }
}

async function cmdQuery(flags) {
  if (!flags.type && !flags.tags && !flags.idPrefix) {
    die("query needs at least one filter (--type, --tags, or --id-prefix) so it does not pull the whole bundle", 2);
  }
  const ms = timeoutMs(flags);
  const t = resolveTransport(flags, ms);
  const concepts = await t.select(flags);
  if (concepts.length === 0) {
    if (flags.json) process.stdout.write("{}\n");
    else process.stdout.write("No OKF concepts matched.\n");
    return;
  }
  const limit = flags.limit ? Number(flags.limit) : DEFAULT_QUERY_LIMIT;
  const cap = Number.isFinite(limit) && limit > 0 ? limit : DEFAULT_QUERY_LIMIT;
  const chosen = concepts.slice(0, cap);
  const truncated = concepts.length - chosen.length;
  const bodies = await t.load(chosen.map((c) => c.id));
  if (flags.json) {
    process.stdout.write(`${JSON.stringify(bodies, null, 2)}\n`);
  } else {
    if (truncated > 0) {
      process.stdout.write(
        `Matched ${concepts.length} concepts; loading the first ${chosen.length} (--limit ${cap}). ` +
          `${truncated} not loaded — narrow with --tags/--id-prefix or raise --limit.\n`,
      );
    }
    printBodies(chosen, bodies);
  }
}

function usage() {
  process.stdout.write(
    `okf — query OKF playbooks mid-task over the control-plane API (TRON_API_URL), with a\n` +
      `direct-broker fallback when no control-plane channel is present.\n\n` +
      `Usage:\n` +
      `  okf select [--type T] [--tags a,b] [--id-prefix P] [--json]   preview matches (no bodies)\n` +
      `  okf load <id> [<id>...] [--json]                              fetch bodies for ids\n` +
      `  okf query [--type T] [--tags a,b] [--id-prefix P] [--limit N] [--json]\n` +
      `                                                                select + load matched bodies (capped)\n` +
      `  okf help\n\n` +
      `Global: --api-url <url> (overrides TRON_API_URL), --timeout <ms> (default ${DEFAULT_TIMEOUT_MS}).\n` +
      `Fallback: with no TRON_API_URL/--api-url, queries the org-secret broker directly using a\n` +
      `cloudflared Access token (OKF_BROKER_APP/OKF_BROKER_BASE/OKF_ACCESS_TOKEN override the hosts).\n` +
      `Select-then-load: filter cheap, then load only the ids you need — never the whole bundle.\n`,
  );
}

// ── dispatch ─────────────────────────────────────────────────────────────────

async function main() {
  if (!command || command === "help" || command === "--help" || command === "-h") {
    usage();
    return;
  }
  const { flags, positional } = parseArgs(rest);
  switch (command) {
    case "select":
      await cmdSelect(flags);
      break;
    case "load":
      await cmdLoad(flags, positional);
      break;
    case "query":
      await cmdQuery(flags);
      break;
    default:
      die(`unknown command: ${command} (try: okf help)`, 2);
  }
}

main();
