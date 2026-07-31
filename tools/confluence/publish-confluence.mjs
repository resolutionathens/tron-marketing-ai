#!/usr/bin/env node
import fs from 'node:fs';
import { spawnSync } from 'node:child_process';

function usage(message) {
  if (message) process.stderr.write(`confluence-publish: ${message}\n`);
  process.stderr.write('usage: publish-confluence.mjs create --space-id ID --parent-id ID --title TITLE --body-file FILE\n');
  process.stderr.write('       publish-confluence.mjs update --page-id ID --title TITLE --body-file FILE\n');
  process.exit(2);
}

function fail(message, details) {
  const suffix = details ? `: ${details}` : '';
  process.stderr.write(`confluence-publish: ${message}${suffix}\n`);
  process.exit(1);
}

function parseArgs(argv) {
  const action = argv.shift();
  if (!['create', 'update'].includes(action)) usage('action must be create or update');
  const values = {};
  while (argv.length) {
    const flag = argv.shift();
    if (!flag?.startsWith('--')) usage(`unexpected argument ${flag}`);
    const value = argv.shift();
    if (!value || value.startsWith('--')) usage(`${flag} requires a value`);
    const key = flag.slice(2);
    if (!['space-id', 'parent-id', 'page-id', 'title', 'body-file'].includes(key)) usage(`unknown flag ${flag}`);
    if (values[key]) usage(`${flag} may be supplied only once`);
    values[key] = value;
  }
  for (const key of ['title', 'body-file']) {
    if (!values[key]) usage(`--${key} is required`);
  }
  if (action === 'create') {
    if (!values['space-id']) usage('--space-id is required for create');
    if (!values['parent-id']) usage('--parent-id is required for create');
    if (values['page-id']) usage('--page-id is valid only for update');
  } else {
    if (!values['page-id']) usage('--page-id is required for update');
    if (values['space-id'] || values['parent-id']) usage('update accepts only an explicit --page-id destination');
  }
  for (const key of ['space-id', 'parent-id', 'page-id']) {
    if (values[key] && !/^\d+$/.test(values[key])) usage(`--${key} must be a numeric Confluence ID`);
  }
  if (!fs.existsSync(values['body-file']) || !fs.statSync(values['body-file']).isFile()) {
    usage(`--body-file does not name a readable file: ${values['body-file']}`);
  }
  return { action, values };
}

function brokerToken() {
  if (process.env.CONFLUENCE_ACCESS_TOKEN) return process.env.CONFLUENCE_ACCESS_TOKEN;
  const app = process.env.CONFLUENCE_BROKER_APP || 'https://secrets.facilitron.work';
  const result = spawnSync('cloudflared', ['access', 'token', `--app=${app}`], {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'ignore'],
  });
  const token = result.status === 0 ? result.stdout.trim() : '';
  if (!token) fail('could not authenticate with the Atlassian broker; sign in with cloudflared access or set CONFLUENCE_ACCESS_TOKEN');
  return token;
}

async function request(path, token, options = {}) {
  let response;
  try {
    response = await fetch(`${brokerBase}/wiki${path}`, {
      ...options,
      headers: {
        'cf-access-token': token,
        ...(options.body ? { 'content-type': 'application/json' } : {}),
      },
    });
  } catch (error) {
    fail('Atlassian broker request failed', error.message);
  }
  const text = await response.text();
  let payload = {};
  try { payload = text ? JSON.parse(text) : {}; } catch { fail(`Atlassian broker returned invalid JSON (HTTP ${response.status})`); }
  if (!response.ok) fail(`Atlassian broker returned HTTP ${response.status}`, payload.message || payload.error || 'request rejected');
  return payload;
}

function result(action, page) {
  const pageId = String(page.id || '');
  const version = page.version?.number;
  const title = page.title;
  const webui = page._links?.webui;
  if (!pageId || !Number.isInteger(version) || !title || !webui) {
    fail('Confluence response omitted required destination metadata');
  }
  const url = `${siteBase}${webui.startsWith('/') ? '' : '/'}${webui}`;
  process.stdout.write(`${JSON.stringify({ ok: true, action, pageId, version, title, url })}\n`);
}

const { action, values } = parseArgs(process.argv.slice(2));
const brokerBase = (process.env.CONFLUENCE_BROKER_BASE || 'https://secrets.facilitron.work/jira').replace(/\/$/, '');
const siteBase = (process.env.CONFLUENCE_SITE_BASE || 'https://facilitron.atlassian.net/wiki').replace(/\/$/, '');
const token = brokerToken();
const bodyValue = fs.readFileSync(values['body-file'], 'utf8');

if (action === 'create') {
  const page = await request('/api/v2/pages', token, {
    method: 'POST',
    body: JSON.stringify({
      spaceId: values['space-id'],
      status: 'current',
      title: values.title,
      parentId: values['parent-id'],
      body: { representation: 'storage', value: bodyValue },
    }),
  });
  result(action, page);
} else {
  const pageId = values['page-id'];
  const current = await request(`/api/v2/pages/${encodeURIComponent(pageId)}`, token);
  const currentVersion = current.version?.number;
  if (!Number.isInteger(currentVersion)) fail(`existing page ${pageId} has no numeric version`);
  const page = await request(`/api/v2/pages/${encodeURIComponent(pageId)}`, token, {
    method: 'PUT',
    body: JSON.stringify({
      id: pageId,
      status: 'current',
      title: values.title,
      body: { representation: 'storage', value: bodyValue },
      version: { number: currentVersion + 1 },
    }),
  });
  result(action, page);
}
