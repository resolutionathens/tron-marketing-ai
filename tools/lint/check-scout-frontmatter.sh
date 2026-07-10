#!/usr/bin/env bash
# Lints every skills/*/SKILL.md's scout: frontmatter block against the shape
# tron-os/lib/catalog.ts -> parseScoutMeta() expects (see CLAUDE.md -> SKILL.md
# frontmatter -> The scout: block). parseScoutMeta() is deliberately
# tolerant — a malformed block doesn't error there, it silently degrades
# (surface normalizes to "hidden", a bad inputs entry drops from the run
# form, an unknown category falls back to "More tools") — so this lint is
# the only thing that catches the mistake before it ships. MD-2027.
#
#   bash tools/lint/check-scout-frontmatter.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="${1:-$(cd "$HERE/../.." && pwd)}"
cd "$ROOT"

VALID_CATEGORIES="tickets drafting qa seo media"
VALID_EFFECTS="draft report jira publish cdn local"
VALID_TYPES="text textarea path"

fail=0
checked=0

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  s="${s%\"}"; s="${s#\"}"
  s="${s%\'}"; s="${s#\'}"
  printf '%s' "$s"
}

in_list() {
  local needle="$1" hay="$2" w
  for w in $hay; do [ "$w" = "$needle" ] && return 0; done
  return 1
}

flush_item() {
  if [ "$have_item" = 1 ]; then
    input_keys+=("$cur_key")
    input_labels+=("$cur_label")
    input_types+=("$cur_type")
  fi
  cur_key=""; cur_label=""; cur_type=""; have_item=0
}

shopt -s nullglob
for doc in skills/*/SKILL.md; do
  skill="$(basename "$(dirname "$doc")")"
  checked=$((checked + 1))
  errs=()

  frontmatter="$(awk '/^---$/{c++; next} c==1' "$doc")"

  if ! grep -q '^scout:' <<<"$frontmatter"; then
    echo "OK   $skill (no scout: block)"
    continue
  fi

  # The scout: block itself, from "scout:" up to (not including) the next
  # top-level frontmatter key.
  scout="$(awk '/^scout:/{f=1; next} f && /^[A-Za-z_-]+:/{exit} f{print}' <<<"$frontmatter")"

  surface="" title="" blurb="" when="" category="" effects_raw=""
  input_keys=(); input_labels=(); input_types=()
  cur_key=""; cur_label=""; cur_type=""; have_item=0
  in_inputs=0

  while IFS= read -r line; do
    if [[ "$line" =~ ^\ \ ([a-zA-Z_]+):\ ?(.*)$ ]]; then
      flush_item
      in_inputs=0
      key="${BASH_REMATCH[1]}"; val="$(trim "${BASH_REMATCH[2]}")"
      case "$key" in
        surface) surface="$val" ;;
        title) title="$val" ;;
        blurb) blurb="$val" ;;
        when) when="$val" ;;
        category) category="$val" ;;
        effects) effects_raw="$val" ;;
        inputs) in_inputs=1 ;;
      esac
      continue
    fi
    if [ "$in_inputs" = 1 ] && [[ "$line" =~ ^\ \ \ \ -\ (.*)$ ]]; then
      flush_item
      have_item=1
      rest="${BASH_REMATCH[1]}"
      if [[ "$rest" =~ ^([a-zA-Z_]+):\ ?(.*)$ ]]; then
        k="${BASH_REMATCH[1]}"; v="$(trim "${BASH_REMATCH[2]}")"
        case "$k" in
          key) cur_key="$v" ;;
          label) cur_label="$v" ;;
          type) cur_type="$v" ;;
        esac
      fi
      continue
    fi
    if [ "$in_inputs" = 1 ] && [ "$have_item" = 1 ] && [[ "$line" =~ ^\ \ \ \ \ \ ([a-zA-Z_]+):\ ?(.*)$ ]]; then
      k="${BASH_REMATCH[1]}"; v="$(trim "${BASH_REMATCH[2]}")"
      case "$k" in
        key) cur_key="$v" ;;
        label) cur_label="$v" ;;
        type) cur_type="$v" ;;
      esac
      continue
    fi
  done <<<"$scout"
  flush_item

  case "$surface" in
    ""|true|developer|false) ;;
    *) errs+=("surface '$surface' is not one of true | \"true\" | developer | false/absent (silently normalizes to hidden in tron-os)") ;;
  esac

  if [ "$surface" = "true" ]; then
    [ -n "$title" ] || errs+=("surface: true requires a non-empty title")
    [ -n "$blurb" ] || errs+=("surface: true requires a non-empty blurb")
    [ -n "$when" ] || errs+=("surface: true requires a non-empty when")
    [ -n "$category" ] || errs+=("surface: true requires a non-empty category")
    [ -n "$effects_raw" ] || errs+=("surface: true requires a non-empty effects list")
  fi

  if [ -n "$category" ] && ! in_list "$category" "$VALID_CATEGORIES"; then
    errs+=("category '$category' is not one of tickets | drafting | qa | seo | media")
  fi

  if [ -n "$effects_raw" ]; then
    list="${effects_raw#\[}"; list="${list%\]}"
    IFS=',' read -ra effs <<<"$list"
    for e in ${effs[@]+"${effs[@]}"}; do
      e="$(trim "$e")"
      [ -n "$e" ] || continue
      in_list "$e" "$VALID_EFFECTS" || errs+=("effects entry '$e' is not one of draft | report | jira | publish | cdn | local")
    done
  fi

  for i in "${!input_keys[@]}"; do
    k="${input_keys[$i]}"; l="${input_labels[$i]}"; t="${input_types[$i]}"
    [ -n "$k" ] || errs+=("inputs[$i] is missing a non-empty key")
    [ -n "$l" ] || errs+=("inputs[$i] (key '$k') is missing a non-empty label")
    if [ -n "$t" ] && ! in_list "$t" "$VALID_TYPES"; then
      errs+=("inputs[$i] (key '$k') type '$t' is not one of text | textarea | path")
    fi
  done

  if [ "${#errs[@]}" -eq 0 ]; then
    echo "OK   $skill"
  else
    fail=1
    for e in "${errs[@]}"; do
      echo "FAIL $skill — $e"
    done
  fi
done

echo
if [ "$fail" = 1 ]; then
  echo "check-scout-frontmatter: FAILED (checked $checked skills)"
  exit 1
fi
echo "check-scout-frontmatter: OK (checked $checked skills)"
