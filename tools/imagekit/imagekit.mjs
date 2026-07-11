#!/usr/bin/env node

import fs from 'fs';
import os from 'os';
import path from 'path';
import { spawnSync } from 'child_process';

// Primary path: the Cloudflare-Access-fronted broker at secrets.facilitron.work,
// which proxies the ImageKit REST API 1:1. Fallback path: ImageKit's public API
// directly, authenticated with IMAGEKIT_PRIVATE_KEY. The broker origin has
// intermittently failed the TLS handshake for some workers (LibreSSL "tlsv1
// alert protocol version"), which used to force a manual by-hand direct call
// (CCAL-1973/1974); we now fall through to the direct API automatically. All
// bases are env-overridable so this fallback is testable without the real hosts.
const BROKER_BASE = process.env.IMAGEKIT_BROKER_BASE || 'https://secrets.facilitron.work/imagekit/api/v1';
const BROKER_UPLOAD = process.env.IMAGEKIT_BROKER_UPLOAD || 'https://secrets.facilitron.work/imagekit/upload/api/v1';
const BROKER_APP = process.env.IMAGEKIT_BROKER_APP || 'https://secrets.facilitron.work';
const DIRECT_BASE = process.env.IMAGEKIT_DIRECT_BASE || 'https://api.imagekit.io/v1';
const DIRECT_UPLOAD = process.env.IMAGEKIT_DIRECT_UPLOAD || 'https://upload.imagekit.io/api/v1';

const [,, command, ...rest] = process.argv;

// ── Helpers ────────────────────────────────────────────────────────────────

// Cloudflare Access token for the broker. IMAGEKIT_ACCESS_TOKEN short-circuits
// cloudflared (used by tests and by workers who already hold a token). Returns
// null — rather than dying — on failure, so the caller can fall back to direct.
function getToken() {
  if (process.env.IMAGEKIT_ACCESS_TOKEN) return process.env.IMAGEKIT_ACCESS_TOKEN;
  const result = spawnSync(
    'cloudflared', ['access', 'token', `--app=${BROKER_APP}`],
    { encoding: 'utf-8', timeout: 15000 }
  );
  if (result.status !== 0 || !result.stdout) return null;
  return result.stdout.trim();
}

// ImageKit private key for the direct-API fallback: env first, then ~/.env
// (the plain dotenv workers keep their global secrets in).
function getPrivateKey() {
  if (process.env.IMAGEKIT_PRIVATE_KEY) return process.env.IMAGEKIT_PRIVATE_KEY;
  try {
    const envFile = path.join(os.homedir(), '.env');
    const line = fs.readFileSync(envFile, 'utf-8')
      .split('\n')
      .find((l) => l.startsWith('IMAGEKIT_PRIVATE_KEY='));
    if (line) return line.slice('IMAGEKIT_PRIVATE_KEY='.length).trim().replace(/^['"]|['"]$/g, '');
  } catch {}
  return null;
}

function directAuthHeader() {
  const key = getPrivateKey();
  if (!key) {
    die('Broker unreachable and IMAGEKIT_PRIVATE_KEY is not set (checked env and ~/.env); cannot fall back to the direct ImageKit API.');
  }
  return 'Basic ' + Buffer.from(`${key}:`).toString('base64');
}

// Map a broker URL onto its direct-API equivalent (paths mirror 1:1).
function toDirectUrl(url) {
  if (url.startsWith(BROKER_UPLOAD)) return DIRECT_UPLOAD + url.slice(BROKER_UPLOAD.length);
  if (url.startsWith(BROKER_BASE)) return DIRECT_BASE + url.slice(BROKER_BASE.length);
  return url;
}

// A thrown fetch() (DNS/TLS/refused connection) means the broker is unreachable
// and we should fall back — as opposed to an HTTP error status, which is a real
// upstream response and is surfaced by handleResponse().
function isBrokerUnreachable(err) {
  const s = `${err?.message || ''} ${err?.cause?.message || ''} ${err?.cause?.code || ''}`.toLowerCase();
  return err instanceof TypeError ||
    /tls|ssl|handshake|alert|certificate|econnrefused|enotfound|econnreset|etimedout|eai_again|fetch failed|network|und_err/.test(s);
}

let announcedFallback = false;
function noteFallback(reason) {
  if (announcedFallback) return;
  announcedFallback = true;
  console.error(`imagekit: ${reason}; falling back to the direct ImageKit API (IMAGEKIT_PRIVATE_KEY).`);
}

// Broker-first client with automatic direct-API fallback. Each request tries the
// broker; on a connectivity/TLS failure (or a missing Access token) it retries
// the same call against the direct ImageKit API with Basic auth.
function client() {
  const token = getToken();
  let brokerDown = token === null;
  if (brokerDown) noteFallback('Cloudflare Access token unavailable (cloudflared missing or not logged in)');

  async function request(method, url, { headers = {}, body } = {}) {
    if (!brokerDown) {
      try {
        const res = await fetch(url, { method, headers: { ...headers, 'CF-Access-Token': token }, body });
        return await handleResponse(res, method);
      } catch (err) {
        if (!isBrokerUnreachable(err)) throw err;
        brokerDown = true;
        noteFallback(`broker unreachable (${err.message || err})`);
      }
    }
    const res = await fetch(toDirectUrl(url), { method, headers: { ...headers, Authorization: directAuthHeader() }, body });
    return await handleResponse(res, method);
  }

  return {
    get(url, params = {}) {
      const qs = new URLSearchParams();
      for (const [k, v] of Object.entries(params)) {
        if (v !== undefined && v !== null) qs.set(k, String(v));
      }
      const full = qs.toString() ? `${url}?${qs}` : url;
      return request('GET', full);
    },
    post(url, body, isFormData = false) {
      const headers = {};
      if (!isFormData) headers['Content-Type'] = 'application/json';
      return request('POST', url, { headers, body: isFormData ? body : JSON.stringify(body) });
    },
    delete(url, body) {
      return request('DELETE', url, {
        headers: { 'Content-Type': 'application/json' },
        body: body ? JSON.stringify(body) : undefined,
      });
    },
  };
}

async function handleResponse(res, method) {
  const text = await res.text();
  if (!res.ok) {
    let msg = `Broker error (${res.status})`;
    try { const j = JSON.parse(text); msg = j.message || j.error || msg; } catch {}
    die(msg);
  }
  try { return JSON.parse(text); } catch { return text; }
}

function parseFlags(args) {
  const flags = {};
  const positional = [];
  for (let i = 0; i < args.length; i++) {
    if (args[i].startsWith('--')) {
      const key = args[i].slice(2);
      const val = args[i + 1] && !args[i + 1].startsWith('--') ? args[++i] : true;
      flags[key] = val;
    } else {
      positional.push(args[i]);
    }
  }
  return { flags, positional };
}

function out(data) {
  console.log(JSON.stringify(data, null, 2));
}

function die(msg) {
  console.error(`Error: ${msg}`);
  process.exit(1);
}

// ── Commands ───────────────────────────────────────────────────────────────

async function cmdUpload(flags, positional) {
  const filePath = positional[0];
  if (!filePath) die('Usage: upload <file-path> [--name <name>] [--folder <path>] [--tags <t1,t2>] [--useUniqueFileName <true|false>]');
  if (!fs.existsSync(filePath)) die(`File not found: ${filePath}`);

  const fd = new (await import('node:buffer')).File(
    [await fs.promises.readFile(filePath)], flags.name || filePath.split('/').pop()
  );
  const form = new FormData();
  form.append('file', fd);
  form.append('fileName', flags.name || filePath.split('/').pop());
  if (flags.folder) form.append('folder', flags.folder);
  if (flags.tags) form.append('tags', flags.tags);

  // Default to exact filenames and overwrite existing files — without these
  // ImageKit appends a random suffix (e.g. file_aB3xK.pdf) by default, which
  // breaks the exact-filename lookups the content skills rely on. Pass
  // --useUniqueFileName true to opt back into ImageKit's unique-suffix behavior.
  const useUniqueFileName = flags.useUniqueFileName !== undefined
    ? String(flags.useUniqueFileName) === 'true'
    : false;
  form.append('useUniqueFileName', String(useUniqueFileName));
  form.append('overwriteFile', 'true');

  const b = client();
  const res = await b.post(`${BROKER_UPLOAD}/files/upload`, form, true);
  out(res);
}

async function cmdList(flags) {
  const params = {};
  if (flags.path) params.path = flags.path;
  if (flags.type) params.type = flags.type;
  if (flags.limit) params.limit = parseInt(flags.limit);
  if (flags.skip) params.skip = parseInt(flags.skip);
  if (flags.sort) params.sort = flags.sort;
  if (flags.order) params.order = flags.order;
  if (flags.tags) params.tags = flags.tags;
  if (flags.name) params.searchQuery = `name:"${flags.name}"`;

  const b = client();
  const res = await b.get(`${BROKER_BASE}/files`, params);
  out(res);
}

async function cmdSearch(flags, positional) {
  const query = positional[0];
  if (!query) die('Usage: search <query> [--limit <n>]');
  const b = client();
  const res = await b.get(`${BROKER_BASE}/files`, { searchQuery: `name:"${query}"`, ...(flags.limit ? { limit: parseInt(flags.limit) } : {}) });
  out(res);
}

async function cmdGet(flags, positional) {
  const fileId = positional[0];
  if (!fileId) die('Usage: get <fileId>');

  const b = client();
  const res = await b.get(`${BROKER_BASE}/files/${fileId}/details`);
  out(res);
}

async function cmdMetadata(flags, positional) {
  const fileId = positional[0];
  if (!fileId) die('Usage: metadata <fileId>');

  const b = client();
  const res = await b.get(`${BROKER_BASE}/files/${fileId}/metadata`);
  out(res);
}

async function cmdDelete(flags, positional) {
  const fileId = positional[0];
  if (!fileId) die('Usage: delete <fileId>');

  const b = client();
  await b.delete(`${BROKER_BASE}/files/${fileId}`);
  console.log(`Deleted ${fileId}`);
}

async function cmdBulkDelete(flags, positional) {
  if (positional.length === 0) die('Usage: bulk-delete <fileId1> <fileId2> [...]');

  const b = client();
  const res = await b.post(`${BROKER_BASE}/files/batch/deleteByFileIds`, { fileIds: positional });
  out(res);
}

async function cmdCopy(flags, positional) {
  const [sourceFilePath, destinationPath] = positional;
  if (!sourceFilePath || !destinationPath) die('Usage: copy <sourceFilePath> <destinationPath>');

  const b = client();
  const res = await b.post(`${BROKER_BASE}/files/copy`, { sourceFilePath, destinationPath });
  out(res);
}

async function cmdMove(flags, positional) {
  const [sourceFilePath, destinationPath] = positional;
  if (!sourceFilePath || !destinationPath) die('Usage: move <sourceFilePath> <destinationPath>');

  const b = client();
  const res = await b.post(`${BROKER_BASE}/files/move`, { sourceFilePath, destinationPath });
  out(res);
}

async function cmdRename(flags, positional) {
  const [filePath, newFileName] = positional;
  if (!filePath || !newFileName) die('Usage: rename <filePath> <newName> [--purge]');
  const params = { filePath, newFileName };
  if (flags.purge) params.purgeCache = true;

  const b = client();
  const res = await b.post(`${BROKER_BASE}/files/rename`, params);
  out(res);
}

async function cmdCreateFolder(flags, positional) {
  const [folderName, parentFolderPath] = positional;
  if (!folderName || !parentFolderPath) die('Usage: create-folder <folderName> <parentPath>');

  const b = client();
  const res = await b.post(`${BROKER_BASE}/folders`, { folderName, parentFolderPath });
  out(res);
}

async function cmdDeleteFolder(flags, positional) {
  const folderPath = positional[0];
  if (!folderPath) die('Usage: delete-folder <folderPath>');

  const b = client();
  const res = await b.delete(`${BROKER_BASE}/folders/${encodeURIComponent(folderPath)}`);
  out(res);
}

async function cmdCopyFolder(flags, positional) {
  const [sourceFolderPath, destinationPath] = positional;
  if (!sourceFolderPath || !destinationPath) die('Usage: copy-folder <sourcePath> <destinationPath>');

  const b = client();
  const res = await b.post(`${BROKER_BASE}/folders/copy`, { sourceFolderPath, destinationPath });
  out(res);
}

async function cmdMoveFolder(flags, positional) {
  const [sourceFolderPath, destinationPath] = positional;
  if (!sourceFolderPath || !destinationPath) die('Usage: move-folder <sourcePath> <destinationPath>');

  const b = client();
  const res = await b.post(`${BROKER_BASE}/folders/move`, { sourceFolderPath, destinationPath });
  out(res);
}

async function cmdUsage(flags) {
  const now = new Date();
  const startDate = flags.start || new Date(now.getFullYear(), now.getMonth(), 1).toISOString().split('T')[0];
  const endDate = flags.end || now.toISOString().split('T')[0];
  const qs = new URLSearchParams({ startDate, endDate });

  const b = client();
  const res = await b.get(`${BROKER_BASE}/account/usage?${qs}`);
  out(res);
}

async function cmdAddTags(flags, positional) {
  const tags = positional[0]?.split(',');
  const fileIds = positional.slice(1);
  if (!tags || fileIds.length === 0) die('Usage: add-tags <tag1,tag2> <fileId1> [fileId2...]');

  const b = client();
  const res = await b.post(`${BROKER_BASE}/files/addTags`, { tags, fileIds });
  out(res);
}

async function cmdRemoveTags(flags, positional) {
  const tags = positional[0]?.split(',');
  const fileIds = positional.slice(1);
  if (!tags || fileIds.length === 0) die('Usage: remove-tags <tag1,tag2> <fileId1> [fileId2...]');

  const b = client();
  const res = await b.post(`${BROKER_BASE}/files/removeTags`, { tags, fileIds });
  out(res);
}

async function cmdPurge(flags, positional) {
  const url = positional[0];
  if (!url) die('Usage: purge <url>');

  const b = client();
  const res = await b.post(`${BROKER_BASE}/files/purge`, { url });
  out(res);
}

async function cmdPurgeStatus(flags, positional) {
  const requestId = positional[0];
  if (!requestId) die('Usage: purge-status <requestId>');

  const b = client();
  const res = await b.get(`${BROKER_BASE}/files/purge/${requestId}`);
  out(res);
}

// ── Main ───────────────────────────────────────────────────────────────────

try {
  const { flags, positional } = parseFlags(rest);

  switch (command) {
    case 'upload':      await cmdUpload(flags, positional); break;
    case 'list':        await cmdList(flags); break;
    case 'search':      await cmdSearch(flags, positional); break;
    case 'get':         await cmdGet(flags, positional); break;
    case 'metadata':    await cmdMetadata(flags, positional); break;
    case 'delete':      await cmdDelete(flags, positional); break;
    case 'bulk-delete': await cmdBulkDelete(flags, positional); break;
    case 'copy':        await cmdCopy(flags, positional); break;
    case 'move':        await cmdMove(flags, positional); break;
    case 'rename':      await cmdRename(flags, positional); break;
    case 'create-folder':   await cmdCreateFolder(flags, positional); break;
    case 'delete-folder':   await cmdDeleteFolder(flags, positional); break;
    case 'copy-folder':     await cmdCopyFolder(flags, positional); break;
    case 'move-folder':     await cmdMoveFolder(flags, positional); break;
    case 'usage':       await cmdUsage(flags); break;
    case 'add-tags':    await cmdAddTags(flags, positional); break;
    case 'remove-tags': await cmdRemoveTags(flags, positional); break;
    case 'purge':       await cmdPurge(flags, positional); break;
    case 'purge-status': await cmdPurgeStatus(flags, positional); break;

    default:
      console.log(`ImageKit CLI - Available commands:
  upload        Upload a file
  list          List assets
  search        Search files by name
  get           Get file details
  metadata      Get file metadata
  delete        Delete a file
  bulk-delete   Delete multiple files
  copy          Copy a file
  move          Move a file
  rename        Rename a file
  create-folder Create a folder
  delete-folder Delete a folder
  copy-folder   Copy a folder
  move-folder   Move a folder
  usage         Account usage stats
  add-tags      Add tags to files
  remove-tags   Remove tags from files
  purge         Purge CDN cache
  purge-status  Check purge status

Connectivity:
  Requests go through the Cloudflare Access broker (secrets.facilitron.work) by
  default. If the broker is unreachable (e.g. a TLS handshake failure) or no
  Access token is available, the CLI automatically falls back to the direct
  ImageKit API and prints a one-line notice on stderr. The fallback needs
  IMAGEKIT_PRIVATE_KEY (read from the environment or ~/.env); without it, the
  command errors instead of silently doing nothing.`);
  }
} catch (err) {
  console.error(err.message || err);
  process.exit(1);
}