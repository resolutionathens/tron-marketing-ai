#!/usr/bin/env bash
# site-audit: the DETERMINISTIC core of tron:site-audit. The runner
# subagent (haiku) invokes THIS script with a target instead of assembling the npx
# command itself — which is how it previously ran the wrong binary (bare `unlighthouse`,
# which opens an interactive UI and ignores --build-static/--reporter) with a flag that
# does not exist (`--urls-pattern`), so nothing scoped the crawl and it hammered the
# whole site for 9+ minutes. Encoding the one correct invocation here removes the model
# from command assembly entirely, so model strength stops mattering.
#
# Only real unlighthouse-ci flags are used (verified against `unlighthouse-ci --help`):
#   --site, --urls, --include-urls (regex/string, NOT glob), --exclude-urls,
#   --build-static, --reporter csvExpanded, --output-path, --no-cache, --samples
#
# Usage:
#   site-audit.sh <target-url> [--page | --full] [--samples N] [--desktop] [--throttle]
#     default            : SECTION scope — crawl the origin, keep only paths under the
#                          target's path (regex-anchored via --include-urls). A bare
#                          origin with no path naturally means the whole site.
#     --page             : SINGLE PAGE — scan exactly the target path, crawler disabled
#                          (--urls). Fully bounded; fastest.
#     --full             : force a full-origin crawl even when the target has a path
#                          (explicit opt-in — this is the only unbounded mode).
#     --samples N        : run N samples per page for score stability (pass-through).
#     --desktop          : audit the desktop profile instead of mobile (pass-through).
#     --throttle         : enable network/CPU throttling for realistic mobile CWV (pass-through).
#
# Prints the absolute path to the parsed CSV (ci-result.csv) on stdout; narration on
# stderr. The caller reads the CSV and summarizes — this script only runs the audit.
set -euo pipefail

log() { echo "site-audit: $*" >&2; }

TARGET="${1:?usage: site-audit.sh <target-url> [--page|--full] [--samples N] [--desktop]}"
shift || true

MODE="section"          # section | page | full
SAMPLES=""
DESKTOP=""
THROTTLE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --page)     MODE="page" ;;
    --full)     MODE="full" ;;
    --samples)  SAMPLES="${2:?--samples needs a number}"; shift ;;
    --desktop)  DESKTOP="1" ;;
    --throttle) THROTTLE="1" ;;
    *) log "ignoring unknown arg: $1" ;;
  esac
  shift
done

# origin = scheme://host (strip any path/query/fragment)
ORIGIN="$(printf '%s' "$TARGET" | sed -E 's#^(https?://[^/]+).*#\1#')"
# path = everything after the host, trailing slash trimmed
PATH_ONLY="$(printf '%s' "$TARGET" | sed -E 's#^https?://[^/]+##; s#[?#].*$##; s#/$##')"

[ -n "$ORIGIN" ] || { log "could not parse an origin from '$TARGET'"; exit 2; }

OUT="$(mktemp -d "${TMPDIR:-/tmp}/unlighthouse.XXXXXX")"
cleanup_failed_audit() {
  local rc=$?
  if [ "$rc" -ne 0 ]; then rm -rf "$OUT"; fi
  return "$rc"
}
trap cleanup_failed_audit EXIT

args=(--site "$ORIGIN" --build-static --reporter csvExpanded --output-path "$OUT" --no-cache)
[ -n "$SAMPLES" ]  && args+=(--samples "$SAMPLES")
[ -n "$DESKTOP" ]  && args+=(--desktop)
[ -n "$THROTTLE" ] && args+=(--throttle)

# A target with no path can only be a full-site crawl.
if [ -z "$PATH_ONLY" ] && [ "$MODE" != "page" ]; then
  MODE="full"
fi

case "$MODE" in
  page)
    # --urls disables the link crawler and scans only this relative path. Fully bounded.
    # A bare origin (no path) has no single page to scope to — default to the site root
    # so we never emit `--urls ""`, which unlighthouse rejects.
    [ -n "$PATH_ONLY" ] || PATH_ONLY="/"
    args+=(--urls "$PATH_ONLY")
    log "single-page scope: $PATH_ONLY"
    ;;
  section)
    # --include-urls is a REGEX/string filter (not a glob). Anchor on the target path so
    # only that section is kept. (NEVER --urls-pattern — that flag does not exist.)
    # Escape regex metacharacters in the path so e.g. `/pricing.html` can't match
    # `/pricingXhtml`, and `/c++` or paths with ()[] don't form an invalid/over-broad regex.
    # Negated-safe-set (alnum + / - _) is portable across BSD/GNU sed and over-escapes only
    # harmless chars (e.g. ~ -> \~, an identity escape).
    PATH_RE="$(printf '%s' "$PATH_ONLY" | sed 's#[^[:alnum:]/_-]#\\&#g')"
    args+=(--include-urls "^${PATH_RE}")
    log "section scope: ^${PATH_RE}"
    ;;
  full)
    log "FULL-SITE crawl of $ORIGIN (unbounded — explicit/implicit opt-in)"
    ;;
esac

log "running: npx -y unlighthouse-ci ${args[*]}"
# Dry-run hook for the offline smoke test: print the assembled argv and stop before
# actually downloading Chromium / hitting the network.
if [ -n "${UNLH_DRY_RUN:-}" ]; then
  printf 'npx -y unlighthouse-ci %s\n' "${args[*]}"
  rm -rf "$OUT"
  trap - EXIT
  exit 0
fi
# unlighthouse-ci is the HEADLESS binary. NEVER the bare `unlighthouse` binary, which
# opens the interactive UI at :5678 and ignores these flags.
npx -y unlighthouse-ci "${args[@]}" >&2

csv="$OUT/ci-result.csv"
if [ ! -f "$csv" ]; then
  log "error: no ci-result.csv produced under $OUT"
  exit 1
fi
echo "$csv"
