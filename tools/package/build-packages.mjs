#!/usr/bin/env node

import {
  cpSync,
  existsSync,
  mkdirSync,
  lstatSync,
  readFileSync,
  readdirSync,
  realpathSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { dirname, join, normalize, relative, resolve, sep } from "node:path";

const root = resolve(new URL("../..", import.meta.url).pathname);
const output = resolve(process.argv[2] || join(root, "dist", "packages"));
const packageMapPath = resolve(
  process.env.TRON_PACKAGE_MAP || join(root, "packages", "package-map.json"),
);
const map = JSON.parse(readFileSync(packageMapPath, "utf8"));
const claudeBase = JSON.parse(readFileSync(join(root, ".claude-plugin", "plugin.json"), "utf8"));
const claudeMarketplaceBase = JSON.parse(
  readFileSync(join(root, ".claude-plugin", "marketplace.json"), "utf8"),
);
const codexBase = JSON.parse(readFileSync(join(root, ".codex-plugin", "plugin.json"), "utf8"));
const codexMarketplaceBase = JSON.parse(
  readFileSync(join(root, ".agents", "plugins", "marketplace.json"), "utf8"),
);

if (output === root || output === resolve(root, "..") || output === "/") {
  throw new Error("package output must be a dedicated directory");
}

function sourceSkills() {
  return readdirSync(join(root, "skills"), { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && existsSync(join(root, "skills", entry.name, "SKILL.md")))
    .map((entry) => entry.name)
    .sort();
}

function validateMap() {
  const actual = sourceSkills();
  const owners = new Map();
  for (const [owner, skills] of Object.entries(map.ownership)) {
    if (!map.packages[owner]) throw new Error(`ownership references unknown package ${owner}`);
    for (const skill of skills) {
      if (owners.has(skill)) throw new Error(`${skill} has multiple owners: ${owners.get(skill)}, ${owner}`);
      owners.set(skill, owner);
    }
  }
  const owned = [...owners].map(([skill]) => skill).sort();
  if (JSON.stringify(actual) !== JSON.stringify(owned)) {
    const missing = actual.filter((skill) => !owners.has(skill));
    const stale = owned.filter((skill) => !actual.includes(skill));
    throw new Error(`ownership must classify every skill exactly once; missing=${missing}; stale=${stale}`);
  }
  for (const [name, pkg] of Object.entries(map.packages)) {
    for (const parent of pkg.extends || []) {
      if (!map.packages[parent]) throw new Error(`${name} extends unknown package ${parent}`);
    }
    for (const skill of pkg.skills) {
      if (!actual.includes(skill)) throw new Error(`${name} references unknown skill ${skill}`);
    }
  }
}

function packageSkills(name, seen = new Set()) {
  if (seen.has(name)) throw new Error(`package extension cycle at ${name}`);
  seen.add(name);
  const pkg = map.packages[name];
  const skills = new Set(pkg.skills);
  for (const parent of pkg.extends || []) {
    for (const skill of packageSkills(parent, new Set(seen))) skills.add(skill);
  }
  return [...skills].sort();
}

function packageResources(name, seen = new Set()) {
  if (seen.has(name)) throw new Error(`package extension cycle at ${name}`);
  seen.add(name);
  const pkg = map.packages[name];
  const resources = new Set(pkg.resources);
  for (const parent of pkg.extends || []) {
    for (const resource of packageResources(parent, new Set(seen))) resources.add(resource);
  }
  return [...resources].sort();
}

function assertContainedSource(source) {
  const resolvedRoot = `${realpathSync(root)}${sep}`;
  const resolvedSource = realpathSync(source);
  if (!resolvedSource.startsWith(resolvedRoot)) throw new Error(`resource escapes repository: ${source}`);
  const walk = (path) => {
    if (["node_modules", ".git"].includes(path.split(sep).at(-1))) return;
    const stat = lstatSync(path);
    if (stat.isSymbolicLink()) {
      throw new Error(`package resources may not contain symlinks: ${path}`);
    }
    if (stat.isDirectory()) {
      for (const entry of readdirSync(path)) walk(join(path, entry));
    }
  };
  walk(source);
}

function copyPath(source, destination) {
  assertContainedSource(source);
  mkdirSync(dirname(destination), { recursive: true });
  cpSync(source, destination, {
    recursive: true,
    filter: (path) => !["node_modules", ".git"].includes(path.split(sep).at(-1)),
  });
}

function validateResource(resource, packageName) {
  const normalized = normalize(resource);
  if (
    normalized !== resource ||
    resource.startsWith("/") ||
    resource.split("/").includes("..") ||
    !/^(agents|tools)\//.test(resource)
  ) {
    throw new Error(`${packageName} has unsafe resource path ${resource}`);
  }
  const absolute = resolve(root, resource);
  if (!absolute.startsWith(`${root}${sep}`) || !existsSync(absolute)) {
    throw new Error(`${packageName} resource is missing or outside the repository: ${resource}`);
  }
  assertContainedSource(absolute);
}

function manifest(base, name, description) {
  return {
    ...base,
    name: `tron-${name}`,
    description: `Facilitron ${name} package: ${description}`,
    keywords: [...new Set([...(base.keywords || []), name, "role-scoped"])],
    skills: "./skills/",
  };
}

function codexMarketplace(name) {
  const packageName = `tron-${name}`;
  return {
    ...codexMarketplaceBase,
    interface: {
      ...codexMarketplaceBase.interface,
      displayName: `Tron ${name[0].toUpperCase()}${name.slice(1)}`,
    },
    plugins: codexMarketplaceBase.plugins.map((plugin, index) => index === 0 ? {
      ...plugin,
      name: packageName,
      source: { source: "local", path: "." },
    } : plugin),
  };
}

function claudeMarketplace(name, description) {
  const packageName = `tron-${name}`;
  return {
    ...claudeMarketplaceBase,
    plugins: claudeMarketplaceBase.plugins.map((plugin, index) => index === 0 ? {
      ...plugin,
      name: packageName,
      source: ".",
      description: `Facilitron ${name} package: ${description}`,
    } : plugin),
  };
}

const ownerBySkill = new Map(
  Object.entries(map.ownership).flatMap(([owner, skills]) => skills.map((skill) => [skill, owner])),
);
const skillSets = new Map(
  Object.keys(map.packages).map((name) => [name, new Set(packageSkills(name))]),
);

function rewriteNamespace(dir, packageName) {
  const walk = (path) => {
    for (const entry of readdirSync(path, { withFileTypes: true })) {
      const child = join(path, entry.name);
      if (entry.isDirectory()) walk(child);
      else if (/\.(md|json|sh|mjs|js|ts)$/.test(entry.name)) {
        let text;
        try { text = readFileSync(child, "utf8"); } catch { continue; }
        const rewritten = text.replace(/\btron:([a-z0-9-]+)/g, (reference, skill) => {
          const owner = ownerBySkill.get(skill);
          if (!owner) throw new Error(`${relative(root, child)} references unknown skill ${reference}`);
          const target = skillSets.get(packageName).has(skill) ? packageName : owner;
          return `tron-${target}:${skill}`;
        });
        if (rewritten !== text) writeFileSync(child, rewritten);
      }
    }
  };
  walk(dir);
}

function rewritePackageIdentity(dir, packageName) {
  const hook = join(dir, "hooks", "check-update.sh");
  const text = readFileSync(hook, "utf8");
  writeFileSync(
    hook,
    text
      .replaceAll("tron plugin", `tron-${packageName} plugin`)
      .replaceAll("tron@tron", `tron-${packageName}@tron`),
  );
}

function validateHandoffs(dir) {
  const walk = (path) => {
    for (const entry of readdirSync(path, { withFileTypes: true })) {
      const child = join(path, entry.name);
      if (entry.isDirectory()) walk(child);
      else if (/\.(md|json|sh|mjs|js|ts)$/.test(entry.name)) {
        let text;
        try { text = readFileSync(child, "utf8"); } catch { continue; }
        for (const match of text.matchAll(/\btron-([a-z0-9-]+):([a-z0-9-]+)/g)) {
          const [, target, skill] = match;
          if (!skillSets.has(target) || !skillSets.get(target).has(skill)) {
            throw new Error(`${relative(dir, child)} has unresolved handoff ${match[0]}`);
          }
        }
      }
    }
  };
  walk(dir);
}

function validateBundledReferences(dir, skills) {
  const files = [];
  const walk = (path) => {
    for (const entry of readdirSync(path, { withFileTypes: true })) {
      const child = join(path, entry.name);
      if (entry.isDirectory()) walk(child);
      else files.push(child);
    }
  };
  for (const skill of skills) walk(join(dir, "skills", skill));

  for (const file of files) {
    let text;
    try { text = readFileSync(file, "utf8"); } catch { continue; }
    for (const match of text.matchAll(/(?:^|[^A-Za-z0-9_.-])((?:tools|agents)\/[A-Za-z0-9_.\/-]+)/g)) {
      let candidate = match[1].replace(/[).,;:'"`]+$/, "");
      while (candidate && !existsSync(join(root, candidate))) candidate = candidate.replace(/\/[^/]+$/, "");
      if (candidate && !existsSync(join(dir, candidate))) {
        throw new Error(`${relative(dir, file)} references unbundled resource ${candidate}`);
      }
    }
    for (const agent of readdirSync(join(root, "agents"))) {
      if (
        agent.endsWith(".md") &&
        text.includes(agent.slice(0, -3)) &&
        !existsSync(join(dir, "agents", agent))
      ) {
        throw new Error(`${relative(dir, file)} references unbundled agent ${agent}`);
      }
    }
  }
}

validateMap();
rmSync(output, { recursive: true, force: true });
mkdirSync(output, { recursive: true });

const inventories = [];
for (const [name, pkg] of Object.entries(map.packages)) {
  const skills = packageSkills(name);
  const resources = packageResources(name);
  for (const resource of resources) validateResource(resource, name);
  for (const harness of ["claude", "codex"]) {
    const destination = join(output, harness, `tron-${name}`);
    mkdirSync(destination, { recursive: true });
    for (const skill of skills) copyPath(join(root, "skills", skill), join(destination, "skills", skill));
    for (const resource of resources) copyPath(join(root, resource), join(destination, resource));
    copyPath(join(root, "hooks"), join(destination, "hooks"));
    copyPath(join(root, "WORKER_CONTRACT.md"), join(destination, "WORKER_CONTRACT.md"));
    const manifestDir = harness === "claude" ? ".claude-plugin" : ".codex-plugin";
    mkdirSync(join(destination, manifestDir), { recursive: true });
    writeFileSync(
      join(destination, manifestDir, "plugin.json"),
      `${JSON.stringify(manifest(harness === "claude" ? claudeBase : codexBase, name, pkg.description), null, 2)}\n`,
    );
    if (harness === "claude") {
      writeFileSync(
        join(destination, ".claude-plugin", "marketplace.json"),
        `${JSON.stringify(claudeMarketplace(name, pkg.description), null, 2)}\n`,
      );
    } else {
      mkdirSync(join(destination, ".agents", "plugins"), { recursive: true });
      writeFileSync(
        join(destination, ".agents", "plugins", "marketplace.json"),
        `${JSON.stringify(codexMarketplace(name), null, 2)}\n`,
      );
    }
    rewriteNamespace(destination, name);
    rewritePackageIdentity(destination, name);
    validateHandoffs(destination);
    validateBundledReferences(destination, skills);
    inventories.push({ harness, package: `tron-${name}`, skills, resources });
  }
}

writeFileSync(
  join(output, "inventory.json"),
  `${JSON.stringify({
    schemaVersion: 1,
    version: claudeBase.version,
    migration: {
      monolith: "tron",
      rolePackages: Object.keys(map.packages).map((name) => `tron-${name}`),
      mutuallyExclusive: true,
      rollbackNamespace: "tron",
    },
    packages: inventories,
  }, null, 2)}\n`,
);
console.log(JSON.stringify({ ok: true, output, packages: inventories.length }, null, 2));
