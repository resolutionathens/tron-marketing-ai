#!/bin/bash
# Select and run the verification gates supported by the current repository.
#
# Usage:
#   select-verification-gates.sh [--repo-dir <path>] [--dry-run]
#
# Layer 1 is authoritative when present. Otherwise, package scripts named
# test, typecheck, and smoke are selected in that order.

set -euo pipefail

REPO_DIR="."
DRY_RUN=false

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo-dir)
      [ "$#" -ge 2 ] || { echo "select-verification-gates: --repo-dir requires a path" >&2; exit 2; }
      REPO_DIR="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    *)
      echo "select-verification-gates: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

[ -d "$REPO_DIR" ] || { echo "select-verification-gates: repository not found: $REPO_DIR" >&2; exit 2; }
REPO_DIR="$(cd "$REPO_DIR" && pwd)"

run_gate() {
  label="$1"
  command_text="$2"
  echo "git-pr verification: selected $label gate: $command_text"
  if [ "$DRY_RUN" = false ]; then
    (cd "$REPO_DIR" && /bin/bash -c "$command_text")
  fi
}

LAYER1="tools/lint/run-layer1-tests.sh"
if [ -f "$REPO_DIR/$LAYER1" ]; then
  echo "git-pr verification: source=plugin-layer1"
  run_gate "Layer-1" "bash $LAYER1"
  exit 0
fi

PACKAGE_JSON="$REPO_DIR/package.json"
if [ ! -f "$PACKAGE_JSON" ]; then
  echo "git-pr verification: no automatic gates found; inspect CLAUDE.md, README, package scripts, and contribution docs" >&2
  exit 3
fi

if [ -f "$REPO_DIR/bun.lock" ] || [ -f "$REPO_DIR/bun.lockb" ]; then
  RUNNER="bun run"
elif [ -f "$REPO_DIR/pnpm-lock.yaml" ]; then
  RUNNER="pnpm run"
elif [ -f "$REPO_DIR/yarn.lock" ]; then
  RUNNER="yarn"
else
  RUNNER="npm run"
fi

GATES="$(node - "$PACKAGE_JSON" <<'NODE'
const fs = require("fs");
const packageJson = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const scripts = packageJson.scripts || {};
for (const gate of ["test", "typecheck", "smoke"]) {
  if (typeof scripts[gate] === "string" && scripts[gate].trim()) {
    process.stdout.write(`${gate}\n`);
  }
}
NODE
)"

if [ -z "$GATES" ]; then
  echo "git-pr verification: no automatic gates found; inspect CLAUDE.md, README, package scripts, and contribution docs" >&2
  exit 3
fi

echo "git-pr verification: source=repository-package-scripts"
while IFS= read -r gate; do
  [ -n "$gate" ] || continue
  run_gate "$gate" "$RUNNER $gate"
done <<EOF
$GATES
EOF
