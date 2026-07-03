#!/usr/bin/env bash
# Offline smoke test for gen-image.sh. No real API spend, no image generation:
#   - PATH A (CLI): with a (dummy) OPENAI_API_KEY set, verify the assembled image_gen.py
#     command (edit + one --image per ref + --out + subject/medium prompt). Also run the
#     real CLI in --dry-run (no key needed by the CLI for dry-run; works if image_gen.py
#     is installed) to confirm the request shape.
#   - PATH B (exec fallback): with NO key and a FAKE codex on PATH, verify auth-fail bails
#     fast, arg validation, and that a fresh fake image is copied out.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/gen-image.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

fail=0
expect_exit() { if [ "$2" = "$3" ]; then echo "ok  : $1 (exit $3)"; else echo "FAIL: $1 (want $2, got $3)"; fail=1; fi; }
contains() { if printf '%s' "$3" | grep -qF -- "$2"; then echo "ok  : $1"; else echo "FAIL: $1 — missing '$2'"; fail=1; fi; }

refdir="$TMP/refs"; mkdir -p "$refdir"
printf 'x' > "$refdir/a.jpg"; printf 'x' > "$refdir/b.png"
logo="$HERE/../../md-to-pdf/facilitron-logo.png"
[ -f "$logo" ] || logo="$(ls ~/.claude/plugins/marketplaces/*/skills/md-to-pdf/facilitron-logo.png 2>/dev/null | head -1 || true)"
[ -f "$logo" ] || { echo "SKIP: no sample PNG"; exit 0; }

# ========================================================================================
# PATH A — CLI command assembly (preferred path). Set OPENAI_API_KEY explicitly (it takes
# precedence over the ~/.env source) and point CODEX_HOME at the real install so the CLI is
# found. GENIMG_PRINT_CMD prints the assembled argv and exits.
# ========================================================================================
REAL_CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
cmd="$(OPENAI_API_KEY=sk-test CODEX_HOME="$REAL_CODEX_HOME" GENIMG_PRINT_CMD=1 \
       bash "$SCRIPT" "$refdir" "an empty wooden park bench" "$TMP/out.png" 2>/dev/null || true)"
if [ -n "$cmd" ]; then
  contains "CLI: uses image_gen.py"            "image_gen.py" "$cmd"
  contains "CLI: uses the edit subcommand"     "image_gen.py edit" "$cmd"
  contains "CLI: passes ref a.jpg as --image"  "--image $refdir/a.jpg" "$cmd"
  contains "CLI: passes ref b.png as --image"  "--image $refdir/b.png" "$cmd"
  contains "CLI: --out is the target"          "--out $TMP/out.png" "$cmd"
  contains "CLI: subject in prompt"            "an empty wooden park bench" "$cmd"
  contains "CLI: medium pinned (style only)"   "STYLE/MOOD references ONLY" "$cmd"
  contains "CLI: forbids copying subjects"     "Do NOT copy their specific subjects" "$cmd"
else
  echo "note: CLI path not selected (image_gen.py or python missing) — skipping CLI assertions"
fi

# Real dry-run through the CLI (validates the request shape end-to-end without a live call).
IMAGE_GEN="${CODEX_HOME:-$HOME/.codex}/skills/.system/imagegen/scripts/image_gen.py"
if [ -f "$IMAGE_GEN" ] && command -v python3 >/dev/null 2>&1; then
  dry="$(OPENAI_API_KEY=sk-test CODEX_HOME="$REAL_CODEX_HOME" GENIMG_DRY_RUN=1 \
         bash "$SCRIPT" "$refdir" "an empty wooden park bench" "$TMP/out.png" 2>&1 || true)"
  contains "CLI dry-run: hits /v1/images/edits" "images/edits" "$dry"
  contains "CLI dry-run: model gpt-image-2"      "gpt-image-2" "$dry"
fi

# ========================================================================================
# PATH B — exec fallback (no key). Fake codex on PATH; fake ~/.env-free HOME.
# ========================================================================================
mkfake() {
  local mode="$1"; mkdir -p "$TMP/bin"
  cat > "$TMP/bin/codex" <<EOF
#!/usr/bin/env bash
cat > "$TMP/last-prompt.txt" 2>/dev/null || true
case "$mode" in
  fail) exit 1 ;;
  ok)
    gendir="\$HOME/.codex/generated_images/sess-test"; mkdir -p "\$gendir"
    cp "$logo" "\$gendir/ig_test.png"
    exit 0 ;;
esac
EOF
  chmod +x "$TMP/bin/codex"
}

# auth failure → exit 3, no output
mkfake fail
set +e
out="$(PATH="$TMP/bin:$PATH" HOME="$TMP/exec-home" bash "$SCRIPT" "$refdir" "a gym" "$TMP/o1.png" 2>&1)"; code=$?
set -e
expect_exit "exec: auth-fail bails fast"     3 "$code"
contains    "exec: shows re-auth ask"        "BLOCKED on codex auth" "$out"

# missing source → exit 2
mkfake ok
set +e
out="$(PATH="$TMP/bin:$PATH" HOME="$TMP/exec-home" bash "$SCRIPT" "$TMP/nope" "x" "$TMP/o2.png" 2>&1)"; code=$?
set -e
expect_exit "exec: missing source exits 2"   2 "$code"

# happy path → fresh fake image copied out, exit 0
mkfake ok
set +e
out="$(PATH="$TMP/bin:$PATH" HOME="$TMP/exec-home" bash "$SCRIPT" "$refdir" "a school gymnasium" "$TMP/o3.png" 2>&1)"; code=$?
set -e
expect_exit "exec: happy path exits 0"       0 "$code"
[ -s "$TMP/o3.png" ] && echo "ok  : exec: fresh image copied to target" || { echo "FAIL: exec no output"; fail=1; }
prompt="$(cat "$TMP/last-prompt.txt" 2>/dev/null || true)"
contains    "exec: subject mandatory in prompt" "school gymnasium" "$prompt"

echo
[ "$fail" -eq 0 ] && echo "ALL PASS" || { echo "FAILURES above"; exit 1; }
