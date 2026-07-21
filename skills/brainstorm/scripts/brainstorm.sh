#!/usr/bin/env bash
# brainstorm: the deterministic tail of tron:brainstorm — after the 6-stage
# conversation, stamp out an Ideation Note skeleton on disk so the agent fills
# the body instead of re-deriving the path, slug, date, and front-matter by hand.
# The THINKING (the 6 stages, the answers) stays a judgment step in the skill;
# this script only does the mechanical save.
#
# Usage:
#   brainstorm.sh save <idea-name> [--audience S] [--format F] [--out PATH]
#       slugifies <idea-name>, seeds the bundled template's front-matter
#       (created=today, audience, format), writes it, and prints the path.
#       Default out: /tmp/ideation-<slug>.md  (won't clobber — errors if exists
#       unless --force).
#   brainstorm.sh slug <text>     → print the slug only (pure, offline)
#
# Output: `save` prints the written path on stdout, narration on stderr.
# Exit 0 success / 1 logical failure / 2 usage error.
set -euo pipefail

log() { echo "brainstorm: $*" >&2; }
usage_err() { echo "brainstorm.sh: $*" >&2; exit 2; }

# Resolve this skill's bundled dir robustly. $CLAUDE_SKILL_DIR is NOT always exported
# into the agent's Bash (e.g. under the headless worker); never hardcode a version-pinned path.
name=brainstorm
SKILL_DIR="${CLAUDE_SKILL_DIR:-${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/skills/$name}}"
# fall back to the newest INSTALLED copy that actually contains scripts/brainstorm.sh
# (skips a stale mirror that lacks it; newest version wins, marketplace breaks ties)
[ -e "$SKILL_DIR/scripts/brainstorm.sh" ] || SKILL_DIR="$(find ~/.claude/plugins/cache ~/.claude/plugins/marketplaces "$HOME/Library/Application Support/tron-os/tron-releases/versions" -maxdepth 5 -type d -path "*/skills/$name" 2>/dev/null | while read -r d; do [ -e "$d/scripts/brainstorm.sh" ] && echo "$d"; done | sort -V | tail -1 || true)"
# last resort: this script's own dir (running straight from the checkout)
[ -e "$SKILL_DIR/scripts/brainstorm.sh" ] || SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
[ -e "$SKILL_DIR/reference/ideation-note-template.md" ] || { echo "tron:$name: can't find reference/ideation-note-template.md — run /plugin update (or set CLAUDE_PLUGIN_ROOT)" >&2; exit 1; }

# Lowercase, strip non-alphanumerics to hyphens, collapse/trim hyphens.
slugify() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g'
}

CMD="${1:-}"; [[ $# -gt 0 ]] && shift
AUDIENCE=""; FORMAT=""; OUT=""; FORCE=0; ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --audience) AUDIENCE="${2:-}"; shift ;;
    --format)   FORMAT="${2:-}"; shift ;;
    --out)      OUT="${2:-}"; shift ;;
    --force)    FORCE=1 ;;
    -h|--help)  sed -n '2,21p' "$0"; exit 0 ;;
    -*) usage_err "unknown flag '$1'" ;;
    *) ARGS+=("$1") ;;
  esac
  shift
done

cmd_slug() {
  local in="${ARGS[0]:-}"; [[ -z "$in" ]] && usage_err "slug requires <text>"
  slugify "$in"
}

cmd_save() {
  local idea="${ARGS[0]:-}"; [[ -z "$idea" ]] && usage_err "save requires <idea-name>"
  local slug; slug="$(slugify "$idea")"
  [[ -z "$slug" ]] && usage_err "<idea-name> slugified to empty"
  local out="${OUT:-/tmp/ideation-$slug.md}"
  [[ -e "$out" && "$FORCE" -ne 1 ]] && { log "refusing to clobber existing $out (pass --force)"; exit 1; }

  local today; today="$(date +%F)"
  local aud="${AUDIENCE:-{ specific persona/segment \}}"
  local fmt="${FORMAT:-{ article | guide | toolkit item | landing page | campaign | other \}}"

  # Strip the template's ```markdown fences, then seed the front-matter, leaving the
  # body for the agent to fill. awk (not sed) does the substitution so the values'
  # `|` and `/` characters can't collide with a sed delimiter.
  awk '/^```markdown$/{f=1;next} /^```$/{if(f){f=0;next}} f' \
    "$SKILL_DIR/reference/ideation-note-template.md" \
    | awk -v today="$today" -v aud="$aud" -v fmt="$fmt" -v idea="$idea" '
        /^created: YYYY-MM-DD$/ { print "created: " today; next }
        /^audience: / { print "audience: " aud; next }
        /^format: / { print "format: " fmt; next }
        /^# Ideation Note — \{Short name of the idea\}$/ { print "# Ideation Note — " idea; next }
        { print }
      ' \
    > "$out"

  log "wrote Ideation Note skeleton → $out"
  printf '%s\n' "$out"
}

case "$CMD" in
  save) cmd_save ;;
  slug) cmd_slug ;;
  ""|help|-h|--help) sed -n '2,21p' "$0" ;;
  *) usage_err "unknown subcommand '$CMD' (try: save, slug)" ;;
esac
