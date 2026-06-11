#!/usr/bin/env node

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { execSync } from 'child_process';

// Lazy-install our one dependency on first run. The CLI is vendored in the
// plugin but its node_modules is not committed (keeps the repo lean), so the
// first invocation installs @imagekit/nodejs next to this script. Needs npm +
// network once; subsequent runs find node_modules and skip straight through.
const __dir = path.dirname(fileURLToPath(import.meta.url));
if (!fs.existsSync(path.join(__dir, 'node_modules', '@imagekit', 'nodejs'))) {
  console.error('imagekit: installing dependencies (first run, one time)…');
  execSync('npm install --silent --no-audit --no-fund', { cwd: __dir, stdio: ['ignore', 'ignore', 'inherit'] });
}
const { default: ImageKit } = await import('@imagekit/nodejs');

// Auto-load IMAGEKIT_PRIVATE_KEY from ~/.env if not already set
if (!process.env.IMAGEKIT_PRIVATE_KEY) {
  const envPath = path.join(process.env.HOME, '.env');
  if (fs.existsSync(envPath)) {
    const match = fs.readFileSync(envPath, 'utf-8').match(/^IMAGEKIT_PRIVATE_KEY=(.+)$/m);
    if (match) process.env.IMAGEKIT_PRIVATE_KEY = match[1];
  }
}

const [,, command, ...rest] = process.argv;

function getClient() {
  if (!process.env.IMAGEKIT_PRIVATE_KEY) {
    die('IMAGEKIT_PRIVATE_KEY environment variable is not set. Set it or add it to ~/.env');
  }
  return new ImageKit({ privateKey: process.env.IMAGEKIT_PRIVATE_KEY });
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

try {
  const { flags, positional } = parseFlags(rest);

  switch (command) {
    case 'upload': {
      const filePath = positional[0];
      if (!filePath) die('Usage: upload <file-path> [--name <name>] [--folder <path>] [--tags <t1,t2>]');
      if (!fs.existsSync(filePath)) die(`File not found: ${filePath}`);
      const params = {
        file: fs.createReadStream(filePath),
        fileName: flags.name || path.basename(filePath),
      };
      if (flags.folder) params.folder = flags.folder;
      if (flags.tags) params.tags = flags.tags.split(',');
      out(await getClient().files.upload(params));
      break;
    }

    case 'list': {
      const params = {};
      if (flags.path) params.path = flags.path;
      if (flags.type) params.type = flags.type;
      if (flags.limit) params.limit = parseInt(flags.limit);
      if (flags.skip) params.skip = parseInt(flags.skip);
      if (flags.sort) params.sort = flags.sort;
      if (flags.order) params.order = flags.order;
      if (flags.tags) params.tags = flags.tags.split(',');
      if (flags.name) params.searchQuery = `name="${flags.name}"`;
      out(await getClient().assets.list(params));
      break;
    }

    case 'search': {
      const query = positional[0];
      if (!query) die('Usage: search <query> [--limit <n>]');
      const params = { searchQuery: `name="${query}"` };
      if (flags.limit) params.limit = parseInt(flags.limit);
      out(await getClient().assets.list(params));
      break;
    }

    case 'get': {
      const fileId = positional[0];
      if (!fileId) die('Usage: get <fileId>');
      out(await getClient().files.get(fileId));
      break;
    }

    case 'metadata': {
      const fileId = positional[0];
      if (!fileId) die('Usage: metadata <fileId>');
      out(await getClient().files.metadata.get(fileId));
      break;
    }

    case 'delete': {
      const fileId = positional[0];
      if (!fileId) die('Usage: delete <fileId>');
      await getClient().files.delete(fileId);
      console.log(`Deleted ${fileId}`);
      break;
    }

    case 'bulk-delete': {
      if (positional.length === 0) die('Usage: bulk-delete <fileId1> <fileId2> [...]');
      out(await getClient().files.bulk.delete({ fileIds: positional }));
      break;
    }

    case 'copy': {
      const [sourceFilePath, destinationPath] = positional;
      if (!sourceFilePath || !destinationPath) die('Usage: copy <sourceFilePath> <destinationPath>');
      out(await getClient().files.copy({ sourceFilePath, destinationPath }));
      break;
    }

    case 'move': {
      const [sourceFilePath, destinationPath] = positional;
      if (!sourceFilePath || !destinationPath) die('Usage: move <sourceFilePath> <destinationPath>');
      out(await getClient().files.move({ sourceFilePath, destinationPath }));
      break;
    }

    case 'rename': {
      const [filePath, newFileName] = positional;
      if (!filePath || !newFileName) die('Usage: rename <filePath> <newName> [--purge]');
      const params = { filePath, newFileName };
      if (flags.purge) params.purgeCache = true;
      out(await getClient().files.rename(params));
      break;
    }

    case 'create-folder': {
      const [folderName, parentFolderPath] = positional;
      if (!folderName || !parentFolderPath) die('Usage: create-folder <folderName> <parentPath>');
      out(await getClient().folders.create({ folderName, parentFolderPath }));
      break;
    }

    case 'delete-folder': {
      const folderPath = positional[0];
      if (!folderPath) die('Usage: delete-folder <folderPath>');
      out(await getClient().folders.delete({ folderPath }));
      break;
    }

    case 'copy-folder': {
      const [sourceFolderPath, destinationPath] = positional;
      if (!sourceFolderPath || !destinationPath) die('Usage: copy-folder <sourcePath> <destinationPath>');
      out(await getClient().folders.copy({ sourceFolderPath, destinationPath }));
      break;
    }

    case 'move-folder': {
      const [sourceFolderPath, destinationPath] = positional;
      if (!sourceFolderPath || !destinationPath) die('Usage: move-folder <sourcePath> <destinationPath>');
      out(await getClient().folders.move({ sourceFolderPath, destinationPath }));
      break;
    }

    case 'usage': {
      const now = new Date();
      const startDate = flags.start || new Date(now.getFullYear(), now.getMonth(), 1).toISOString().split('T')[0];
      const endDate = flags.end || now.toISOString().split('T')[0];
      out(await getClient().accounts.usage.get({ startDate, endDate }));
      break;
    }

    case 'add-tags': {
      const tags = positional[0]?.split(',');
      const fileIds = positional.slice(1);
      if (!tags || fileIds.length === 0) die('Usage: add-tags <tag1,tag2> <fileId1> [fileId2...]');
      out(await getClient().files.bulk.addTags({ tags, fileIds }));
      break;
    }

    case 'remove-tags': {
      const tags = positional[0]?.split(',');
      const fileIds = positional.slice(1);
      if (!tags || fileIds.length === 0) die('Usage: remove-tags <tag1,tag2> <fileId1> [fileId2...]');
      out(await getClient().files.bulk.removeTags({ tags, fileIds }));
      break;
    }

    case 'purge': {
      const url = positional[0];
      if (!url) die('Usage: purge <url>');
      out(await getClient().cache.invalidation.create({ url }));
      break;
    }

    case 'purge-status': {
      const requestId = positional[0];
      if (!requestId) die('Usage: purge-status <requestId>');
      out(await getClient().cache.invalidation.get(requestId));
      break;
    }

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
