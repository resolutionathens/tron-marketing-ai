#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'FAIL: %s is required to run package tests.\n' "$1" >&2
    exit 1
  }
}
need_cmd node
need_cmd trash

OUT="$(mktemp -d "${TMPDIR:-/tmp}/tron-packages-test.XXXXXX")"
cleanup() { trash "$OUT"; }
trap cleanup EXIT

node "$ROOT/tools/package/build-packages.mjs" "$OUT" >/dev/null

node - "$ROOT" "$OUT" <<'NODE'
const fs = require("fs");
const path = require("path");
const [root, out] = process.argv.slice(2);
const map = JSON.parse(fs.readFileSync(path.join(root, "packages/package-map.json")));
const inventory = JSON.parse(fs.readFileSync(path.join(out, "inventory.json")));
const repos = map.repos || {};
// Repo bundles build under a `repo-` prefixed key so they share the role
// packages' schema, closure, and namespace passes without colliding with them.
const bundles = {
  ...map.packages,
  ...Object.fromEntries(Object.entries(repos).map(([repo, bundle]) => [`repo-${repo}`, bundle])),
};
const owners = new Map(Object.entries(map.ownership)
  .flatMap(([owner, skills]) => skills.map((skill) => [skill, owner])));
const skillSets = new Map(inventory.packages
  .filter((entry) => entry.harness === "claude")
  .map((entry) => [entry.package.slice(5), new Set(entry.skills)]));
const source = fs.readdirSync(path.join(root, "skills"))
  .filter((name) => fs.existsSync(path.join(root, "skills", name, "SKILL.md"))).sort();
const owned = Object.values(map.ownership).flat().sort();
if (JSON.stringify(source) !== JSON.stringify(owned)) throw new Error("ownership is not exhaustive");
if (inventory.packages.length !== Object.keys(bundles).length * 2) {
  throw new Error("both harnesses must build every package");
}
if (
  inventory.migration.monolith !== "tron" ||
  inventory.migration.mutuallyExclusive !== true ||
  inventory.migration.rolePackages.length !== Object.keys(map.packages).length ||
  inventory.migration.repoBundles.length !== Object.keys(repos).length
) {
  throw new Error("migration metadata is incomplete");
}
// A repo bundle must never be mistaken for a role package by migration tooling.
for (const repo of Object.keys(repos)) {
  if (inventory.migration.rolePackages.includes(`tron-repo-${repo}`)) {
    throw new Error(`repo bundle ${repo} leaked into the role package list`);
  }
  if (!inventory.migration.repoBundles.includes(`tron-repo-${repo}`)) {
    throw new Error(`repo bundle ${repo} is missing from the migration metadata`);
  }
}
for (const entry of inventory.packages) {
  const expectedKind = Object.keys(repos).some((repo) => entry.package === `tron-repo-${repo}`)
    ? "repo"
    : "role";
  if (entry.kind !== expectedKind) {
    throw new Error(`${entry.package} is labelled ${entry.kind}, not ${expectedKind}`);
  }
}
const validSelection = (packages) => {
  const selected = packages.filter((name) =>
    name === inventory.migration.monolith || inventory.migration.rolePackages.includes(name));
  return selected.length === 1;
};
if (
  !validSelection(["tron"]) ||
  !validSelection(["tron-content"]) ||
  validSelection(["tron", "tron-content"]) ||
  validSelection(["tron-content", "tron-seo"])
) {
  throw new Error("monolith XOR role-package migration rule is not enforced by the fixture");
}
for (const name of Object.keys(bundles)) {
  const claude = inventory.packages.find((entry) => entry.harness === "claude" && entry.package === `tron-${name}`);
  const codex = inventory.packages.find((entry) => entry.harness === "codex" && entry.package === `tron-${name}`);
  if (!claude || !codex || JSON.stringify(claude.skills) !== JSON.stringify(codex.skills)) {
    throw new Error(`${name} harness inventories differ`);
  }
  for (const skill of claude.skills) {
    const sourceSkill = fs.readFileSync(path.join(root, "skills", skill, "SKILL.md"), "utf8");
    for (const harness of ["claude", "codex"]) {
      const builtPath = path.join(out, harness, `tron-${name}`, "skills", skill, "SKILL.md");
      if (!fs.existsSync(builtPath)) throw new Error(`${harness}/${name} omitted ${skill}`);
      const built = fs.readFileSync(builtPath, "utf8");
      const expected = sourceSkill.replace(/\btron:([a-z0-9-]+)/g, (reference, targetSkill) => {
        const owner = owners.get(targetSkill);
        if (!owner) throw new Error(`source references unknown skill ${reference}`);
        return `tron-${skillSets.get(name).has(targetSkill) ? name : owner}:${targetSkill}`;
      });
      if (built !== expected) {
        throw new Error(`${harness}/${name}/${skill} is not a deterministic source transform`);
      }
      const rolledBack = built.replace(/\btron-[a-z0-9-]+:([a-z0-9-]+)/g, "tron:$1");
      if (rolledBack !== sourceSkill) {
        throw new Error(`${harness}/${name}/${skill} cannot roll back to monolith namespace`);
      }
      for (const match of built.matchAll(/\btron-([a-z0-9-]+):([a-z0-9-]+)/g)) {
        const [, target, targetSkill] = match;
        if (!skillSets.get(target)?.has(targetSkill)) {
          throw new Error(`${harness}/${name}/${skill} has unresolved handoff ${match[0]}`);
        }
      }
    }
  }
  const expectedResources = new Set(bundles[name].resources);
  for (const parent of bundles[name].extends || []) {
    for (const resource of bundles[parent].resources) expectedResources.add(resource);
  }
  if (JSON.stringify(claude.resources) !== JSON.stringify([...expectedResources].sort())) {
    throw new Error(`${name} resources differ from the declared closure`);
  }
}
const expectedContentSkills = [
  "brainstorm",
  "case-study",
  "confluence",
  "confluence-publish",
  "create-ticket",
  "drive-publish",
  "email-campaign",
  "enrich-jira-ticket",
  "grill",
  "jira",
  "jira-comment",
  "jira-source-discovery",
  "jira-ticket-enricher",
  "link-check",
  "md-to-pdf",
  "okf-query",
  "onesheet",
  "optimize-images",
  "press-release",
  "prose-lint",
  "ticket-lint",
  "weekly-update",
];
const expectedContentResources = [
  "agents/confluence-transformer.md",
  "agents/facilitron-voice-judge.md",
  "agents/lychee-link-runner.md",
  "agents/optimize-images-runner.md",
  "agents/vale-prose-runner.md",
  "tools/broker",
  "tools/confluence",
  "tools/content",
  "tools/google-workspace",
  "tools/image",
  "tools/imagekit",
  "tools/jira",
  "tools/lint/run-layer1-tests.sh",
  "tools/md-to-adf",
  "tools/okf",
  "tools/skill",
  "tools/ticket",
  "tools/voice",
];
const websitePublishingSkills = ["guide-item", "news-item", "toolkit-item"];
for (const harness of ["claude", "codex"]) {
  const content = inventory.packages.find((entry) =>
    entry.harness === harness && entry.package === "tron-content");
  if (JSON.stringify(content.skills) !== JSON.stringify(expectedContentSkills)) {
    throw new Error(`${harness}/content has an unexpected skill inventory: ${content.skills}`);
  }
  if (JSON.stringify(content.resources) !== JSON.stringify(expectedContentResources)) {
    throw new Error(`${harness}/content has an unexpected resource inventory: ${content.resources}`);
  }
  const marketingPages = inventory.packages.find((entry) =>
    entry.harness === harness && entry.package === "tron-repo-marketing-pages");
  const retained = marketingPages.skills.filter((skill) => websitePublishingSkills.includes(skill));
  if (JSON.stringify(retained) !== JSON.stringify(websitePublishingSkills)) {
    throw new Error(`${harness}/marketing-pages lost website-publishing skills: ${retained}`);
  }
}
for (const name of Object.keys(bundles).filter((entry) => entry !== "core")) {
  const skills = inventory.packages.find((entry) => entry.harness === "claude" && entry.package === `tron-${name}`).skills;
  for (const coreSkill of map.packages.core.skills) {
    if (!skills.includes(coreSkill)) throw new Error(`${name} omitted core skill ${coreSkill}`);
  }
}
for (const entry of inventory.packages) {
  const packageRoot = path.join(out, entry.harness, entry.package);
  const role = entry.package.slice(5);
  const manifestDir = entry.harness === "claude" ? ".claude-plugin" : ".codex-plugin";
  const manifest = JSON.parse(fs.readFileSync(path.join(packageRoot, manifestDir, "plugin.json")));
  if (manifest.name !== entry.package || manifest.version !== inventory.version) {
    throw new Error(`${entry.harness}/${role} manifest identity is invalid`);
  }
  const expectedContract = {
    schemaVersion: 1,
    root: ".",
    skills: Object.fromEntries(Object.entries({
      "create-ticket": ["tools/jira", "tools/md-to-adf", "tools/skill", "tools/ticket", "tools/voice"],
      // MD-2749: git-pr Step 1c resolves the bundled local-review client, so every package
      // that ships git-pr must ship tools/review with it.
      "git-pr": ["tools/review", "tools/skill"],
      jira: ["tools/jira", "tools/md-to-adf", "tools/skill", "tools/ticket"],
    }).filter(([skill]) => entry.skills.includes(skill))),
  };
  if (JSON.stringify(manifest.resourceContract) !== JSON.stringify(expectedContract)) {
    throw new Error(`${entry.harness}/${role} resource contract differs from the exact skill closure`);
  }
  for (const resources of Object.values(manifest.resourceContract.skills)) {
    for (const resource of resources) {
      if (!fs.existsSync(path.join(packageRoot, resource))) {
        throw new Error(`${entry.harness}/${role} contract names missing resource ${resource}`);
      }
    }
  }
  if (entry.harness === "codex") {
    const marketplace = JSON.parse(fs.readFileSync(
      path.join(packageRoot, ".agents/plugins/marketplace.json"),
    ));
    const plugin = marketplace.plugins?.find((candidate) => candidate.name === entry.package);
    if (plugin?.source?.source !== "local" || plugin?.source?.path !== ".") {
      throw new Error(`codex/${role} marketplace cannot discover ${entry.package}`);
    }
  } else {
    const marketplace = JSON.parse(fs.readFileSync(
      path.join(packageRoot, ".claude-plugin/marketplace.json"),
    ));
    const plugin = marketplace.plugins?.find((candidate) => candidate.name === entry.package);
    if (plugin?.source !== ".") {
      throw new Error(`claude/${role} marketplace cannot discover ${entry.package}`);
    }
  }
  const hook = fs.readFileSync(path.join(packageRoot, "hooks/check-update.sh"), "utf8");
  if (!hook.includes(`${entry.package}@tron`)) {
    throw new Error(`${entry.harness}/${role} hook does not update its own package`);
  }
  // Hook commands run through `sh -c`, so an unquoted CLAUDE_PLUGIN_ROOT word-splits
  // on install paths containing spaces (the release store lives under Application Support).
  const hookConfig = JSON.parse(fs.readFileSync(path.join(packageRoot, "hooks/hooks.json"), "utf8"));
  const sessionStart = (hookConfig.hooks?.SessionStart ?? []).flatMap((matcher) => matcher.hooks ?? []);
  if (sessionStart.length === 0) {
    throw new Error(`${entry.harness}/${role} ships no SessionStart hook`);
  }
  for (const entryHook of sessionStart) {
    // The interpolated path must be quoted; trailing arguments after it are fine.
    if (!/^"[^"]*\$\{CLAUDE_PLUGIN_ROOT\}[^"]*"($| )/.test(entryHook.command ?? "")) {
      throw new Error(`${entry.harness}/${role} hook command is not quoted: ${entryHook.command}`);
    }
  }
  const walk = (dir) => {
    for (const item of fs.readdirSync(dir, { withFileTypes: true })) {
      if (item.name === "node_modules") throw new Error(`${entry.package} bundled node_modules`);
      const child = path.join(dir, item.name);
      if (item.isSymbolicLink()) throw new Error(`${entry.package} contains a symlink`);
      if (item.isDirectory()) walk(child);
    }
  };
  walk(packageRoot);
}
for (const harness of ["claude", "codex"]) {
  const manifestDir = harness === "claude" ? ".claude-plugin" : ".codex-plugin";
  const monolith = JSON.parse(fs.readFileSync(path.join(root, manifestDir, "plugin.json")));
  if (monolith.name !== "tron" || monolith.version !== inventory.version) {
    throw new Error(`${harness} monolith rollback identity changed`);
  }
}
NODE

test -f "$OUT/claude/tron-engineer/agents/a11y-scan-runner.md"
test -f "$OUT/claude/tron-content/skills/md-to-pdf/template.tex"
test -f "$OUT/codex/tron-designer/tools/imagekit/imagekit.mjs"
node -e "
const fs = require('fs');
const text = fs.readFileSync(process.argv[1], 'utf8');
if (!text.includes('tron-engineer:news-item') || text.includes('tron-content:news-item')) process.exit(1);
" "$OUT/claude/tron-content/skills/link-check/SKILL.md"
node -e "
const fs = require('fs');
const text = fs.readFileSync(process.argv[1], 'utf8');
if (!text.includes('tron-engineer:news-item') || text.includes('tron-content:news-item')) process.exit(1);
" "$OUT/claude/tron-engineer/skills/link-check/SKILL.md"

for HARNESS in claude codex; do
  test -f "$OUT/$HARNESS/tron-engineer/skills/figma-inspect/scripts/figma-inspect.mjs"
  for REPO in marketing-pages marketing-dynamic-landing-pages facilitron-ui; do
    test -f "$OUT/$HARNESS/tron-repo-$REPO/skills/figma-inspect/SKILL.md"
  done
  for SKILL in guide-item news-item toolkit-item; do
    test -f "$OUT/$HARNESS/tron-repo-marketing-pages/skills/$SKILL/SKILL.md"
    test ! -e "$OUT/$HARNESS/tron-content/skills/$SKILL"
  done
  test ! -e "$OUT/$HARNESS/tron-content/tools/git"
  test ! -e "$OUT/$HARNESS/tron-content/tools/worktree"
  # seo-report is an SEO-role responsibility only; content teammates read its
  # findings from SEO teammates, not from a second entry point in their bundle.
  test -f "$OUT/$HARNESS/tron-seo/skills/seo-report/SKILL.md"
  test ! -e "$OUT/$HARNESS/tron-content/skills/seo-report"
done
test -f "$OUT/claude/tron-repo-marketing-pages/tools/content/content.sh"
test -f "$OUT/codex/tron-repo-facilitron-ui/agents/a11y-scan-runner.md"

BAD_MAP="$OUT/unsafe-package-map.json"
node - "$ROOT/packages/package-map.json" "$BAD_MAP" <<'NODE'
const fs = require("fs");
const [source, target] = process.argv.slice(2);
const map = JSON.parse(fs.readFileSync(source, "utf8"));
map.packages.core.resources.push("../README.md");
fs.writeFileSync(target, `${JSON.stringify(map)}\n`);
NODE
if TRON_PACKAGE_MAP="$BAD_MAP" node "$ROOT/tools/package/build-packages.mjs" "$OUT/unsafe" >/dev/null 2>&1; then
  printf 'FAIL: unsafe resource path was accepted.\n' >&2
  exit 1
fi

# Adding repo bundles must leave every role package byte-identical, so a repo
# scoping change can never silently alter what a role worker installs.
NO_REPOS_MAP="$OUT/no-repos-package-map.json"
node - "$ROOT/packages/package-map.json" "$NO_REPOS_MAP" <<'NODE'
const fs = require("fs");
const [source, target] = process.argv.slice(2);
const map = JSON.parse(fs.readFileSync(source, "utf8"));
delete map.repos;
fs.writeFileSync(target, `${JSON.stringify(map)}\n`);
NODE
TRON_PACKAGE_MAP="$NO_REPOS_MAP" node "$ROOT/tools/package/build-packages.mjs" "$OUT/no-repos" >/dev/null
for PACKAGE in core engineer designer content seo manager social video; do
  for HARNESS in claude codex; do
    diff -r "$OUT/no-repos/$HARNESS/tron-$PACKAGE" "$OUT/$HARNESS/tron-$PACKAGE" >/dev/null || {
      printf 'FAIL: repo bundles changed the generated %s/%s tree.\n' "$HARNESS" "$PACKAGE" >&2
      exit 1
    }
  done
done

# A repo bundle is only useful if a bad declaration fails the build instead of
# shipping a bundle that is missing, duplicated, or circular.
reject_map() {
  local label="$1"
  local mutation="$2"
  local bad="$OUT/reject-$label.json"
  node - "$ROOT/packages/package-map.json" "$bad" "$mutation" <<'NODE'
const fs = require("fs");
const [source, target, mutation] = process.argv.slice(2);
const map = JSON.parse(fs.readFileSync(source, "utf8"));
new Function("map", mutation)(map);
fs.writeFileSync(target, `${JSON.stringify(map)}\n`);
NODE
  if TRON_PACKAGE_MAP="$bad" node "$ROOT/tools/package/build-packages.mjs" "$OUT/reject-$label" >/dev/null 2>&1; then
    printf 'FAIL: build accepted %s.\n' "$label" >&2
    exit 1
  fi
}
reject_map unknown-skill 'map.repos["marketing-pages"].skills.push("not-a-real-skill")'
reject_map unknown-parent 'map.repos["tron-os"].extends = ["not-a-real-package"]'
reject_map repo-parent 'map.repos["tron-os"].extends = ["repo-mabe-nuxt"]'
reject_map name-collision 'map.packages["repo-tron-os"] = { description: "x", resources: [], skills: [] }'
reject_map bad-repo-key 'map.repos["Marketing Pages"] = { description: "x", resources: [], skills: [] }'
reject_map unsafe-repo-resource 'map.repos["tron-os"].resources.push("../README.md")'

# The manifest's per-skill resourceContract is installer input, not descriptive
# metadata. Even if an aggregate package declaration omits those paths, the
# builder must materialize the exact closure for every included contracted skill.
CONTRACT_MAP="$OUT/contract-only-resources.json"
node - "$ROOT/packages/package-map.json" "$CONTRACT_MAP" <<'NODE'
const fs = require("fs");
const [source, target] = process.argv.slice(2);
const map = JSON.parse(fs.readFileSync(source, "utf8"));
const contracted = new Set(["tools/jira", "tools/md-to-adf", "tools/skill", "tools/ticket", "tools/voice"]);
map.packages.core.resources = map.packages.core.resources.filter((resource) => !contracted.has(resource));
fs.writeFileSync(target, `${JSON.stringify(map)}\n`);
NODE
TRON_PACKAGE_MAP="$CONTRACT_MAP" node "$ROOT/tools/package/build-packages.mjs" "$OUT/contract-only" >/dev/null
for HARNESS in claude codex; do
  for RESOURCE in tools/jira tools/md-to-adf tools/skill tools/ticket tools/voice; do
    test -e "$OUT/contract-only/$HARNESS/tron-core/$RESOURCE" || {
      printf 'FAIL: resourceContract did not materialize %s for %s/tron-core.\n' "$RESOURCE" "$HARNESS" >&2
      exit 1
    }
  done
done

printf 'PASS: all role packages and repo bundles have deterministic Claude/Codex inventories and local dependency closures.\n'
