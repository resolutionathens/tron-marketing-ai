#!/usr/bin/env bash
# a11y-scan: the DETERMINISTIC core of tron:a11y-scan. The runner subagent (haiku)
# invokes THIS script with a target instead of hand-assembling axe / pa11y-ci command
# lines and a .pa11yci.json from prose — the same class of command assembly that once
# made site-audit run the wrong binary with a flag that does not exist. Encoding the
# one correct invocation per mode here removes the model from command assembly.
#
# Only real flags are used:
#   @axe-core/cli : --tags, --save, --dir            (verified against `axe --help`)
#   pa11y-ci      : --config, --json, --sitemap, --sitemap-find, --sitemap-replace
#
# Usage:
#   a11y-scan.sh <url> [<url>…] [--sitemap] [--pa11y] [--standard WCAG2AA]
#                [--sitemap-find STR] [--sitemap-replace STR]
#     one URL (default)  : axe single-page deep audit (most accurate engine),
#                          tags wcag2a,wcag2aa,wcag21a,wcag21aa (WCAG 2.1 AA).
#     one URL + --pa11y  : pa11y-ci spot check on that one URL (generated config).
#     many URLs          : pa11y-ci with a generated pa11yci.json listing them
#                          (defaults: standard WCAG2AA, timeout 30000, wait 1500,
#                          chromeLaunchConfig args ["--no-sandbox"]).
#     --sitemap          : treat the URL as a sitemap and run pa11y-ci --sitemap.
#                          (A target ending in sitemap*.xml selects this automatically.)
#     --standard         : pa11y standard (default WCAG2AA). The axe path ignores it —
#                          its WCAG 2.1 AA tag set is fixed.
#     --sitemap-find / --sitemap-replace : rewrite sitemap URLs (e.g. prod → localhost).
#
# Prints the absolute path to the JSON results file on stdout; narration on stderr.
# Exit: 0 = scan ran and results were written (violations found is still success —
#       findings ARE the product); 1 = scanner produced no results; 2 = bad arguments.
set -euo pipefail

log() { echo "a11y-scan: $*" >&2; }
usage() {
  log "usage: a11y-scan.sh <url> [<url>…] [--sitemap] [--pa11y] [--standard WCAG2AA] [--sitemap-find STR] [--sitemap-replace STR]"
  exit 2
}

urls=()
MODE=""            # axe | urls | sitemap (resolved below)
FORCE_PA11Y=""
STANDARD="WCAG2AA"
SM_FIND=""
SM_REPLACE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --sitemap)         MODE="sitemap" ;;
    --pa11y)           FORCE_PA11Y=1 ;;
    --standard)        [ $# -ge 2 ] || { log "--standard needs a value"; usage; }
                       STANDARD="$2"; shift ;;
    --sitemap-find)    [ $# -ge 2 ] || { log "--sitemap-find needs a value"; usage; }
                       SM_FIND="$2"; shift ;;
    --sitemap-replace) [ $# -ge 2 ] || { log "--sitemap-replace needs a value"; usage; }
                       SM_REPLACE="$2"; shift ;;
    --*)               log "unknown flag: $1"; usage ;;
    http://*|https://*) urls+=("$1") ;;
    *)                 log "not a URL (must start with http:// or https://): $1"; usage ;;
  esac
  shift
done

[ "${#urls[@]}" -ge 1 ] || usage
TARGET="${urls[0]}"

# Auto-detect a sitemap target; otherwise: many URLs (or --pa11y) → pa11y-ci, one URL → axe.
if [ -z "$MODE" ]; then
  case "$TARGET" in *sitemap*.xml) MODE="sitemap" ;; esac
fi
if [ -z "$MODE" ]; then
  if [ "${#urls[@]}" -gt 1 ] || [ -n "$FORCE_PA11Y" ]; then MODE="urls"; else MODE="axe"; fi
fi
if [ "$MODE" = "sitemap" ] && [ "${#urls[@]}" -gt 1 ]; then
  log "sitemap mode takes exactly one sitemap URL (got ${#urls[@]})"; exit 2
fi

OUT="$(mktemp -d "${TMPDIR:-/tmp}/a11y-scan.XXXXXX")"
RESULTS="$OUT/a11y-results.json"
CONFIG="$OUT/pa11yci.json"

write_config() { # <with-urls|defaults-only> — the pa11y-ci config the runner used to hand-write
  {
    echo '{'
    echo '  "defaults": {'
    echo "    \"standard\": \"$STANDARD\","
    echo '    "timeout": 30000,'
    echo '    "wait": 1500,'
    echo '    "chromeLaunchConfig": { "args": ["--no-sandbox"] }'
    if [ "$1" = "with-urls" ]; then
      echo '  },'
      echo '  "urls": ['
      local i last=$(( ${#urls[@]} - 1 ))
      for i in "${!urls[@]}"; do
        if [ "$i" -lt "$last" ]; then echo "    \"${urls[$i]}\","; else echo "    \"${urls[$i]}\""; fi
      done
      echo '  ]'
    else
      echo '  }'
    fi
    echo '}'
  } > "$CONFIG"
}

case "$MODE" in
  axe)
    # Single page, deepest engine. Tag set = WCAG 2.1 AA (Facilitron requirement).
    cmd=(npx -y @axe-core/cli "$TARGET" --tags wcag2a,wcag2aa,wcag21a,wcag21aa
         --dir "$OUT" --save "$(basename "$RESULTS")")
    log "single-URL axe scan: $TARGET"
    ;;
  urls)
    write_config with-urls
    cmd=(npx -y pa11y-ci --config "$CONFIG" --json)
    log "pa11y-ci scan of ${#urls[@]} URL(s), standard $STANDARD (config: $CONFIG)"
    ;;
  sitemap)
    write_config defaults-only
    cmd=(npx -y pa11y-ci --config "$CONFIG" --json --sitemap "$TARGET")
    [ -n "$SM_FIND" ]    && cmd+=(--sitemap-find "$SM_FIND")
    [ -n "$SM_REPLACE" ] && cmd+=(--sitemap-replace "$SM_REPLACE")
    log "pa11y-ci sitemap scan: $TARGET, standard $STANDARD (config: $CONFIG)"
    ;;
esac

log "running: ${cmd[*]}"
# Dry-run hook for the offline smoke test: print the assembled argv (and any generated
# config) and stop before actually downloading scanners / hitting the network.
if [ -n "${A11Y_DRY_RUN:-}" ]; then
  printf '%s\n' "${cmd[*]}"
  [ -f "$CONFIG" ] && cat "$CONFIG"
  exit 0
fi

rc=0
if [ "$MODE" = "axe" ]; then
  "${cmd[@]}" >&2 || rc=$?            # axe writes $RESULTS itself via --dir/--save
else
  "${cmd[@]}" > "$RESULTS" || rc=$?   # pa11y-ci --json prints results on stdout
fi

# The scanners exit non-zero when violations are found — that is a SUCCESSFUL scan
# (findings are the product). Only a missing/empty results file is a failure.
if [ ! -s "$RESULTS" ]; then
  log "error: scanner produced no results under $OUT (scanner rc=$rc)"
  exit 1
fi
log "scan complete (scanner rc=$rc; non-zero usually just means violations were found)"
echo "$RESULTS"
