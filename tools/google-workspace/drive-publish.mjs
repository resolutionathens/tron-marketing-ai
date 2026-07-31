#!/usr/bin/env node
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

function usage(message) {
  if (message) process.stderr.write(`drive-publish: ${message}\n`);
  process.stderr.write('usage: drive-publish.mjs create-doc --folder-id ID --name NAME --source-file FILE\n');
  process.stderr.write('       drive-publish.mjs upload --folder-id ID --name NAME --mime-type TYPE --source-file FILE\n');
  process.stderr.write('       drive-publish.mjs update --file-id ID --name NAME --mime-type TYPE --source-file FILE\n');
  process.exit(2);
}

function fail(message) {
  throw new Error(message);
}

function parseArgs(argv) {
  const action = argv.shift();
  if (!['create-doc', 'upload', 'update'].includes(action)) usage('action must be create-doc, upload, or update');
  const values = {};
  const allowed = new Set(['folder-id', 'file-id', 'name', 'mime-type', 'source-file']);
  while (argv.length) {
    const flag = argv.shift();
    if (!flag?.startsWith('--')) usage(`unexpected argument ${flag}`);
    const key = flag.slice(2);
    if (!allowed.has(key)) usage(`unknown flag ${flag}`);
    const value = argv.shift();
    if (!value || value.startsWith('--')) usage(`${flag} requires a value`);
    if (values[key]) usage(`${flag} may be supplied only once`);
    values[key] = value;
  }
  for (const key of ['name', 'source-file']) {
    if (!values[key]) usage(`--${key} is required`);
  }
  if (action === 'update') {
    if (!values['file-id']) usage('--file-id is required for update');
    if (values['folder-id']) usage('update accepts only an explicit --file-id destination');
  } else {
    if (!values['folder-id']) usage(`--folder-id is required for ${action}`);
    if (values['file-id']) usage(`--file-id is valid only for update`);
  }
  if (action === 'create-doc') {
    if (values['mime-type']) usage('create-doc always creates a Google Doc and does not accept --mime-type');
  } else if (!values['mime-type']) {
    usage(`--mime-type is required for ${action}`);
  }
  const source = values['source-file'];
  if (!fs.existsSync(source) || !fs.statSync(source).isFile()) usage(`--source-file does not name a readable file: ${source}`);
  return { action, values };
}

function isAuthFailure(stderr) {
  return /auth|oauth|credential|login|token/i.test(stderr || '');
}

function runGws(args, context) {
  const result = spawnSync('gws', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  if (result.error?.code === 'ENOENT') fail('Google Workspace CLI (gws) is not installed');
  if (result.status !== 0) {
    if (isAuthFailure(result.stderr)) fail('Google Workspace authentication failed; run gws auth login with the supported Workspace identity');
    fail(context);
  }
  try {
    return JSON.parse(result.stdout);
  } catch {
    fail('Google Workspace returned invalid JSON');
  }
}

function validateFolder(folderId) {
  const params = JSON.stringify({ fileId: folderId, fields: 'id,mimeType,trashed', supportsAllDrives: true });
  const folder = runGws(['drive', 'files', 'get', '--params', params], `could not validate Drive folder ${folderId}`);
  if (folder.id !== folderId || folder.mimeType !== 'application/vnd.google-apps.folder' || folder.trashed !== false) {
    fail(`Drive destination ${folderId} is not an active folder`);
  }
}

function publishResult(action, file, expectedId) {
  const fileId = String(file.id || '');
  const { mimeType, name, webViewLink: url } = file;
  if (!fileId || !mimeType || !name || !url) fail('Google Drive response omitted required destination metadata');
  if (expectedId && fileId !== expectedId) fail(`Google Drive updated unexpected file ${fileId}`);
  process.stdout.write(`${JSON.stringify({ ok: true, action, fileId, mimeType, name, url })}\n`);
}

function removeWorkspace(workspace, uploadPath) {
  try { if (uploadPath && fs.existsSync(uploadPath)) fs.unlinkSync(uploadPath); } catch {}
  try { if (workspace && fs.existsSync(workspace)) fs.rmdirSync(workspace); } catch {}
}

const { action, values } = parseArgs(process.argv.slice(2));
let workspace;
let uploadPath;
try {
  workspace = fs.mkdtempSync(path.join(os.tmpdir(), 'drive-publish-'));
  uploadPath = path.join(workspace, path.basename(values['source-file']));
  fs.copyFileSync(values['source-file'], uploadPath);

  const fields = 'id,mimeType,name,webViewLink';
  if (action !== 'update') validateFolder(values['folder-id']);

  if (action === 'update') {
    const params = JSON.stringify({ fileId: values['file-id'], fields, supportsAllDrives: true });
    const metadata = JSON.stringify({ name: values.name, mimeType: values['mime-type'] });
    const file = runGws(['drive', 'files', 'update', '--params', params, '--json', metadata, '--upload', uploadPath], `could not update Drive file ${values['file-id']}`);
    publishResult(action, file, values['file-id']);
  } else {
    const mimeType = action === 'create-doc' ? 'application/vnd.google-apps.document' : values['mime-type'];
    const params = JSON.stringify({ fields, supportsAllDrives: true });
    const metadata = JSON.stringify({ name: values.name, parents: [values['folder-id']], mimeType });
    const file = runGws(['drive', 'files', 'create', '--params', params, '--json', metadata, '--upload', uploadPath], `could not create file in Drive folder ${values['folder-id']}`);
    publishResult(action, file);
  }
} catch (error) {
  process.stderr.write(`drive-publish: ${error.message}\n`);
  process.exitCode = 1;
} finally {
  removeWorkspace(workspace, uploadPath);
}
