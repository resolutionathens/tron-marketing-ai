#!/usr/bin/env node
import { execFileSync } from 'node:child_process';

const brokerApp = (process.env.FIGMA_BROKER_APP || 'https://secrets.facilitron.work').replace(/\/$/, '');
const brokerBase = (process.env.FIGMA_BROKER_BASE || brokerApp).replace(/\/$/, '');

function fail(message, code = 1) {
  console.error(`figma-inspect: ${message}`);
  process.exit(code);
}

function parseUrl(input) {
  let url;
  try { url = new URL(input); } catch { fail(`invalid Figma URL: ${input}`, 2); }
  if (!/(^|\.)figma\.com$/i.test(url.hostname)) fail(`expected a figma.com URL, got ${url.hostname}`, 2);
  const match = url.pathname.match(/^\/(?:design|file)\/([A-Za-z0-9_-]+)/);
  if (!match) fail('URL must contain /design/<file-key> or /file/<file-key>', 2);
  const rawNodeId = url.searchParams.get('node-id');
  const nodeId = rawNodeId ? rawNodeId.replace('-', ':') : null;
  return { fileKey: match[1], nodeId };
}

function accessToken() {
  if (process.env.FIGMA_INSPECT_ACCESS_TOKEN) return process.env.FIGMA_INSPECT_ACCESS_TOKEN;
  try {
    return execFileSync('cloudflared', ['access', 'token', `--app=${brokerApp}`], {encoding:'utf8', stdio:['ignore','pipe','ignore']}).trim();
  } catch {
    fail(`could not authenticate with the Figma broker; run cloudflared access login ${brokerApp}`, 3);
  }
}

async function brokerJson(path, token, { optional = false } = {}) {
  let response;
  try {
    response = await fetch(`${brokerBase}${path}`, {headers:{'CF-Access-Token':token}, signal:AbortSignal.timeout(15000)});
  } catch (error) {
    if (optional) return null;
    fail(`broker request failed for ${path}: ${error.message}`, 4);
  }
  if (!response.ok) {
    if (response.status === 401 || response.status === 403) {
      fail(`Figma authorization was rejected (HTTP ${response.status}); connect your Figma account at ${brokerApp}/figma/oauth/start`, 3);
    }
    if (optional) return null;
    const detail = (await response.text()).slice(0, 300).replace(/\s+/g, ' ').trim();
    fail(`Figma broker returned HTTP ${response.status} for ${path}${detail ? `: ${detail}` : ''}`, 4);
  }
  try { return await response.json(); } catch { fail(`Figma broker returned invalid JSON for ${path}`, 4); }
}

const implementationKeys = new Set([
  'id', 'name', 'type', 'visible', 'locked', 'characters', 'absoluteBoundingBox', 'size',
  'layoutMode', 'primaryAxisSizingMode', 'counterAxisSizingMode', 'primaryAxisAlignItems',
  'counterAxisAlignItems', 'layoutWrap', 'itemSpacing', 'counterAxisSpacing', 'paddingLeft',
  'paddingRight', 'paddingTop', 'paddingBottom', 'layoutAlign', 'layoutGrow', 'layoutPositioning',
  'minWidth', 'maxWidth', 'minHeight', 'maxHeight', 'constraints', 'clipsContent', 'opacity',
  'blendMode', 'fills', 'strokes', 'strokeWeight', 'strokeAlign', 'cornerRadius', 'rectangleCornerRadii',
  'effects', 'style', 'styles', 'componentId', 'componentProperties', 'variantProperties', 'children'
]);

function implementationView(value) {
  if (Array.isArray(value)) return value.map(implementationView);
  if (!value || typeof value !== 'object') return value;
  const isDesignNode = typeof value.id === 'string' && typeof value.type === 'string';
  return Object.fromEntries(Object.entries(value)
    .filter(([key]) => !isDesignNode || implementationKeys.has(key))
    .map(([key, child]) => [key, implementationView(child)]));
}

async function inspect(input) {
  const { fileKey, nodeId } = parseUrl(input);
  const token = accessToken();
  const status = await brokerJson('/figma/oauth/status', token);
  if (status?.connected !== true) {
    fail(`connect your Figma account at ${brokerApp}/figma/oauth/start before inspecting this design`, 3);
  }

  let payload;
  let fileMetadata;
  let document;
  if (nodeId) {
    payload = await brokerJson(`/figma/v1/files/${encodeURIComponent(fileKey)}/nodes?ids=${encodeURIComponent(nodeId)}`, token);
    fileMetadata = await brokerJson(`/figma/v1/files/${encodeURIComponent(fileKey)}?depth=1`, token);
    document = payload?.nodes?.[nodeId]?.document;
    if (!document) fail(`node ${nodeId} was not returned for Figma file ${fileKey}`, 1);
  } else {
    payload = await brokerJson(`/figma/v1/files/${encodeURIComponent(fileKey)}`, token);
    fileMetadata = payload;
    document = payload?.document;
    if (!document) fail(`Figma file ${fileKey} did not include a document`, 1);
  }

  let renderedReference = null;
  if (nodeId) {
    const image = await brokerJson(`/figma/v1/images/${encodeURIComponent(fileKey)}?ids=${encodeURIComponent(nodeId)}&format=png&scale=2`, token, {optional:true});
    renderedReference = image?.images?.[nodeId] || null;
  }

  console.log(JSON.stringify({
    ok: true,
    source: {fileKey, nodeId},
    document: implementationView(document),
    components: fileMetadata.components || {},
    componentSets: fileMetadata.componentSets || {},
    styles: fileMetadata.styles || {},
    renderedReference
  }));
}

const [command, input] = process.argv.slice(2);
if (command === 'parse-url' && input) console.log(JSON.stringify(parseUrl(input)));
else if (command === 'inspect' && input) await inspect(input);
else fail('usage: figma-inspect.mjs parse-url|inspect <figma-file-or-node-url>', 2);
