#!/usr/bin/env bash
# Verifies ticket-authoring and manual-image instructions use owned TMPDIR workspaces.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
need() { rg -q "$2" "$1" || { echo "FAIL: $3" >&2; exit 1; }; echo "ok  : $3"; }
need "$ROOT/skills/create-ticket/SKILL.md" 'mktemp -d.*tron-create-ticket' 'create-ticket uses a unique workspace'
need "$ROOT/skills/create-ticket/SKILL.md" "trap 'rm -rf.*WORK" 'create-ticket owns success and failure cleanup'
need "$ROOT/skills/jira-ticket-enricher/SKILL.md" 'mktemp -d.*tron-enrich-jira-ticket' 'enricher uses a unique workspace'
need "$ROOT/skills/jira-ticket-enricher/SKILL.md" "trap 'rm -rf.*WORK" 'enricher owns success and failure cleanup'
need "$ROOT/skills/gen-image/SKILL.md" 'mktemp -d.*card-refs' 'manual image references use a unique workspace'
need "$ROOT/skills/gen-image/SKILL.md" '<explicit durable output path>' 'manual image output is explicitly durable'
