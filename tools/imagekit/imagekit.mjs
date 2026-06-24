#!/usr/bin/env node

import fs from 'fs';
import { spawnSync } from 'child_process';

const BROKER_BASE = 'https://secrets.facilitron.work/imagekit/api/v1';
const BROKER_UPLOAD = 'https://secrets.facilitron.work/imagekit/upload/api/v1';

const [,, command, ...rest] = process.argv;

// ── Helpers ────────────────────────────────────────────────────────────────

function getToken() {
  const result = spawnSync(
    'cloudflared', ['access', 'token', '--app=https://secrets.facilitron.work'],
    { encoding: 'utf-8', timeout: 15000 }
  );
  if (result.status !== 0 || !result.stdout) {
    die('Failed to get Cloudflare Access token. Is cloudflared installed and authenticated?');
  }
  return result.stdout.trim();
}

function broker() {
  const token = getToken();
  return {
    async get(url, params = {}) {
      const qs = new URLSearchParams();
      for (const [k, v] of Object.entries(params)) {
        if (v !== undefined && v !== null) qs.set(k, String(v));
      }
      const full = qs.toString() ? `${url}?${qs}` : url;
      const res = await fetch(full, { headers: { 'CF-Access-Token': token } });
      return handleResponse(res, 'GET');
    },
    async post(url, body, isFormData = false) {
      const headers = { 'CF-Access-Token': token };
      if (!isFormData) headers['Content-Type'] = 'application/json';
      const res = await fetch(url, {
        method: 'POST',
        headers,
        body: isFormData ? body : JSON.stringify(body),
      });
      return handleResponse(res, 'POST');
    },
    async delete(url, body) {
      const res = await fetch(url, {
        method: 'DELETE',
        headers: { 'CF-Access-Token': token, 'Content-Type': 'application/json' },
        body: body ? JSON.stringify(body) : undefined,
      });
      return handleResponse(res, 'DELETE');
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
  if (!filePath) die('Usage: upload <file-path> [--name <name>] [--folder <path>] [--tags <t1,t2>]');
  if (!fs.existsSync(filePath)) die(`File not found: ${filePath}`);

  const fd = new (await import('node:buffer')).File(
    [await fs.promises.readFile(filePath)], flags.name || filePath.split('/').pop()
  );
  const form = new FormData();
  form.append('file', fd);
  form.append('fileName', flags.name || path.basename(filePath));
  if (flags.folder) form.append('folder', flags.folder);
  if (flags.tags) form.append('tags', flags.tags);

  const b = broker();
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

  const b = broker();
  const res = await b.get(`${BROKER_BASE}/files`, params);
  out(res);
}

async function cmdSearch(flags, positional) {
  const query = positional[0];
  if (!query) die('Usage: search <query> [--limit <n>]');
  const b = broker();
  const res = await b.get(`${BROKER_BASE}/files`, { searchQuery: `name:"${query}"`, ...(flags.limit ? { limit: parseInt(flags.limit) } : {}) });
  out(res);
}

async function cmdGet(flags, positional) {
  const fileId = positional[0];
  if (!fileId) die('Usage: get <fileId>');

  const b = broker();
  const res = await b.get(`${BROKER_BASE}/files/${fileId}/details`);
  out(res);
}

async function cmdMetadata(flags, positional) {
  const fileId = positional[0];
  if (!fileId) die('Usage: metadata <fileId>');

  const b = broker();
  const res = await b.get(`${BROKER_BASE}/files/${fileId}/metadata`);
  out(res);
}

async function cmdDelete(flags, positional) {
  const fileId = positional[0];
  if (!fileId) die('Usage: delete <fileId>');

  const b = broker();
  await b.delete(`${BROKER_BASE}/files/${fileId}`);
  console.log(`Deleted ${fileId}`);
}

async function cmdBulkDelete(flags, positional) {
  if (positional.length === 0) die('Usage: bulk-delete <fileId1> <fileId2> [...]');

  const b = broker();
  const res = await b.post(`${BROKER_BASE}/files/batch/deleteByFileIds`, { fileIds: positional });
  out(res);
}

async function cmdCopy(flags, positional) {
  const [sourceFilePath, destinationPath] = positional;
  if (!sourceFilePath || !destinationPath) die('Usage: copy <sourceFilePath> <destinationPath>');

  const b = broker();
  const res = await b.post(`${BROKER_BASE}/files/copy`, { sourceFilePath, destinationPath });
  out(res);
}

async function cmdMove(flags, positional) {
  const [sourceFilePath, destinationPath] = positional;
  if (!sourceFilePath || !destinationPath) die('Usage: move <sourceFilePath> <destinationPath>');

  const b = broker();
  const res = await b.post(`${BROKER_BASE}/files/move`, { sourceFilePath, destinationPath });
  out(res);
}

async function cmdRename(flags, positional) {
  const [filePath, newFileName] = positional;
  if (!filePath || !newFileName) die('Usage: rename <filePath> <newName> [--purge]');
  const params = { filePath, newFileName };
  if (flags.purge) params.purgeCache = true;

  const b = broker();
  const res = await b.post(`${BROKER_BASE}/files/rename`, params);
  out(res);
}

async function cmdCreateFolder(flags, positional) {
  const [folderName, parentFolderPath] = positional;
  if (!folderName || !parentFolderPath) die('Usage: create-folder <folderName> <parentPath>');

  const b = broker();
  const res = await b.post(`${BROKER_BASE}/folders`, { folderName, parentFolderPath });
  out(res);
}

async function cmdDeleteFolder(flags, positional) {
  const folderPath = positional[0];
  if (!folderPath) die('Usage: delete-folder <folderPath>');

  const b = broker();
  const res = await b.delete(`${BROKER_BASE}/folders/${encodeURIComponent(folderPath)}`);
  out(res);
}

async function cmdCopyFolder(flags, positional) {
  const [sourceFolderPath, destinationPath] = positional;
  if (!sourceFolderPath || !destinationPath) die('Usage: copy-folder <sourcePath> <destinationPath>');

  const b = broker();
  const res = await b.post(`${BROKER_BASE}/folders/copy`, { sourceFolderPath, destinationPath });
  out(res);
}

async function cmdMoveFolder(flags, positional) {
  const [sourceFolderPath, destinationPath] = positional;
  if (!sourceFolderPath || !destinationPath) die('Usage: move-folder <sourcePath> <destinationPath>');

  const b = broker();
  const res = await b.post(`${BROKER_BASE}/folders/move`, { sourceFolderPath, destinationPath });
  out(res);
}

async function cmdUsage(flags) {
  const now = new Date();
  const startDate = flags.start || new Date(now.getFullYear(), now.getMonth(), 1).toISOString().split('T')[0];
  const endDate = flags.end || now.toISOString().split('T')[0];
  const qs = new URLSearchParams({ startDate, endDate });

  const b = broker();
  const res = await b.get(`${BROKER_BASE}/account/usage?${qs}`);
  out(res);
}

async function cmdAddTags(flags, positional) {
  const tags = positional[0]?.split(',');
  const fileIds = positional.slice(1);
  if (!tags || fileIds.length === 0) die('Usage: add-tags <tag1,tag2> <fileId1> [fileId2...]');

  const b = broker();
  const res = await b.post(`${BROKER_BASE}/files/addTags`, { tags, fileIds });
  out(res);
}

async function cmdRemoveTags(flags, positional) {
  const tags = positional[0]?.split(',');
  const fileIds = positional.slice(1);
  if (!tags || fileIds.length === 0) die('Usage: remove-tags <tag1,tag2> <fileId1> [fileId2...]');

  const b = broker();
  const res = await b.post(`${BROKER_BASE}/files/removeTags`, { tags, fileIds });
  out(res);
}

async function cmdPurge(flags, positional) {
  const url = positional[0];
  if (!url) die('Usage: purge <url>');

  const b = broker();
  const res = await b.post(`${BROKER_BASE}/files/purge`, { url });
  out(res);
}

async function cmdPurgeStatus(flags, positional) {
  const requestId = positional[0];
  if (!requestId) die('Usage: purge-status <requestId>');

  const b = broker();
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
  purge-status  Check purge status`);
  }
} catch (err) {
  console.error(err.message || err);
  process.exit(1);
}