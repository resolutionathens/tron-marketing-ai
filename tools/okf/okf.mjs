#!/usr/bin/env node
/**
 * OKF query CLI (MD-1997) — the client half of on-demand mid-task OKF querying.
 *
 * A dispatched worker runs inside the target repo's worktree, NOT inside tron-os, so it
 * cannot import lib/okf-client.ts and the knowledge/ OKF bundle does not travel with it.
 * Its only channel back to the OS is HTTP over TRON_API_URL (the control-plane API that
 * dispatched it, already in its env via lib/tmux.ts). This tool calls the OS-side query
 * surface shipped in MD-1988:
 *
 *   GET  {TRON_API_URL}/api/okf/select?type=&tags=&idPrefix=  → { concepts: [...] }   (cheap: manifest filter, no bodies)
 *   POST {TRON_API_URL}/api/okf/load     { ids: string[] }    → { bodies: { id: md } } (bodies for selected ids only)
 *
 * It reuses the MD-1943 select-then-load shape: filter the manifest first (cheap), then
 * fetch bodies ONLY for the ids you actually want — never the whole bundle. The OS decides
 * local-vs-broker backend behind that HTTP surface (createOkfClientFromConfig); this client
 * does not reimplement query logic and does not read the bundle from disk.
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
 * Exit codes: 0 ok · 2 usage error · 3 no API base URL · 4 HTTP/network error.
 */

const [, , command, ...rest] = process.argv;

const DEFAULT_TIMEOUT_MS = 15000;
const DEFAULT_QUERY_LIMIT = 8;

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

// ── HTTP surface resolution ────────────────────────────────────────────────────

function resolveBase(flags) {
  const raw = flags.apiUrl || process.env.TRON_API_URL;
  if (!raw) {
    die(
      "no control-plane API base URL. Set TRON_API_URL (dispatched workers get it in their env) " +
        "or pass --api-url <url>. Without it, fall back to the playbooks front-loaded at launch.",
      3,
    );
  }
  return raw.replace(/\/+$/, "");
}

function timeoutMs(flags) {
  const n = flags.timeout ? Number(flags.timeout) : DEFAULT_TIMEOUT_MS;
  return Number.isFinite(n) && n > 0 ? n : DEFAULT_TIMEOUT_MS;
}

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

// ── endpoints ──────────────────────────────────────────────────────────────────

async function select(base, { type, tags, idPrefix }, ms) {
  const qs = new URLSearchParams();
  if (type) qs.set("type", type);
  if (tags) qs.set("tags", tags);
  if (idPrefix) qs.set("idPrefix", idPrefix);
  const url = `${base}/api/okf/select${qs.toString() ? `?${qs}` : ""}`;
  const data = await apiFetch(url, { method: "GET" }, ms);
  return Array.isArray(data?.concepts) ? data.concepts : [];
}

async function load(base, ids, ms) {
  const url = `${base}/api/okf/load`;
  const data = await apiFetch(
    url,
    { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ ids }) },
    ms,
  );
  return data?.bodies && typeof data.bodies === "object" ? data.bodies : {};
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
  const base = resolveBase(flags);
  const concepts = await select(base, flags, timeoutMs(flags));
  if (flags.json) process.stdout.write(`${JSON.stringify(concepts, null, 2)}\n`);
  else printConceptTable(concepts);
}

async function cmdLoad(flags, ids) {
  if (ids.length === 0) die("load needs at least one concept id (okf load <id> [<id>...])", 2);
  const base = resolveBase(flags);
  const bodies = await load(base, ids, timeoutMs(flags));
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
  const base = resolveBase(flags);
  const ms = timeoutMs(flags);
  const concepts = await select(base, flags, ms);
  if (concepts.length === 0) {
    if (flags.json) process.stdout.write("{}\n");
    else process.stdout.write("No OKF concepts matched.\n");
    return;
  }
  const limit = flags.limit ? Number(flags.limit) : DEFAULT_QUERY_LIMIT;
  const cap = Number.isFinite(limit) && limit > 0 ? limit : DEFAULT_QUERY_LIMIT;
  const chosen = concepts.slice(0, cap);
  const truncated = concepts.length - chosen.length;
  const bodies = await load(base, chosen.map((c) => c.id), ms);
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
    `okf — query OKF playbooks over the control-plane API (TRON_API_URL) mid-task.\n\n` +
      `Usage:\n` +
      `  okf select [--type T] [--tags a,b] [--id-prefix P] [--json]   preview matches (no bodies)\n` +
      `  okf load <id> [<id>...] [--json]                              fetch bodies for ids\n` +
      `  okf query [--type T] [--tags a,b] [--id-prefix P] [--limit N] [--json]\n` +
      `                                                                select + load matched bodies (capped)\n` +
      `  okf help\n\n` +
      `Global: --api-url <url> (overrides TRON_API_URL), --timeout <ms> (default ${DEFAULT_TIMEOUT_MS}).\n` +
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
