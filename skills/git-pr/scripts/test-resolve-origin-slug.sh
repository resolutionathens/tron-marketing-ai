#!/bin/bash
# Hermetic coverage for resolve-origin-slug.sh, run under both bash and zsh —
# the whole point of MD-2661 is that this extraction must behave identically
# under both, since zsh is this environment's default shell.
#
# Run:
#   bash skills/git-pr/scripts/test-resolve-origin-slug.sh

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/resolve-origin-slug.sh"

PASS=0

assert_slug() {
  shell="$1"
  url="$2"
  expected="$3"
  actual="$("$shell" "$SCRIPT" "$url")"
  if [ "$actual" != "$expected" ]; then
    echo "FAIL ($shell): $url -> expected '$expected', got '$actual'" >&2
    exit 1
  fi
  PASS=$((PASS + 1))
}

assert_error() {
  shell="$1"
  url="$2"
  if "$shell" "$SCRIPT" "$url" >/tmp/resolve-origin-slug-out.$$ 2>&1; then
    echo "FAIL ($shell): $url -> expected failure, got success" >&2
    cat /tmp/resolve-origin-slug-out.$$ >&2
    rm -f /tmp/resolve-origin-slug-out.$$
    exit 1
  fi
  rm -f /tmp/resolve-origin-slug-out.$$
  PASS=$((PASS + 1))
}

for SHELL_BIN in bash zsh; do
  command -v "$SHELL_BIN" >/dev/null 2>&1 || { echo "skip: $SHELL_BIN not installed" >&2; continue; }

  assert_slug "$SHELL_BIN" "git@github.com:Facilitron/marketing-pages.git" "Facilitron/marketing-pages"
  assert_slug "$SHELL_BIN" "git@github.com:Facilitron/marketing-pages" "Facilitron/marketing-pages"
  assert_slug "$SHELL_BIN" "https://github.com/Facilitron/marketing-pages.git" "Facilitron/marketing-pages"
  assert_slug "$SHELL_BIN" "https://github.com/Facilitron/marketing-pages" "Facilitron/marketing-pages"
  assert_slug "$SHELL_BIN" "ssh://git@github.com/Facilitron/marketing-pages.git" "Facilitron/marketing-pages"

  assert_error "$SHELL_BIN" "git@github.com:Facilitron"
  assert_error "$SHELL_BIN" "https://gitlab.com/Facilitron/marketing-pages.git"
  assert_error "$SHELL_BIN" "https://github.com/Facilitron/nested/marketing-pages.git"
  assert_error "$SHELL_BIN" "not-a-url"
done

echo "test-resolve-origin-slug: $PASS assertions passed"
