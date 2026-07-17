#!/usr/bin/env bash
# test-generate-card.sh — hermetic unit tests for generate-card.sh's sequence
# numbering (--prefix) and exact-name (--name) paths. No network: `node` is
# stubbed to serve canned ImageKit `list` JSON, gen-image.sh / to-webp.sh are
# stubbed, and uploads are skipped via --no-upload.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
GENCARD="$HERE/generate-card.sh"

PASSES=0
FAILURES=0
pass() { printf "  \033[32m✓\033[0m %s\n" "$1"; PASSES=$(( PASSES + 1 )); }
fail() { printf "  \033[31m✗\033[0m %s\n" "$1"; FAILURES=$(( FAILURES + 1 )); }
has() { grep -qF "$2" <<<"$1"; }

# ---- build a fake plugin root + stub bin --------------------------------
FAKE="$(mktemp -d "${TMPDIR:-/tmp}/gencard-test.XXXXXX")"
trap 'rm -rf "$FAKE"' EXIT

mkdir -p "$FAKE/tools/content" "$FAKE/tools/image" "$FAKE/tools/imagekit" \
          "$FAKE/skills/gen-image/scripts" "$FAKE/bin" "$FAKE/home"

# Real unit under test for numbering: the shared content-lib primitives.
cp "$REPO_ROOT/tools/content/content-lib.sh" "$FAKE/tools/content/content-lib.sh"

# Stub to-webp.sh: just copy source → dest.
cat > "$FAKE/tools/image/to-webp.sh" <<'SH'
#!/usr/bin/env bash
cp "$1" "$2"
SH

# imagekit.mjs only needs to exist as a path; the `node` stub handles calls.
: > "$FAKE/tools/imagekit/imagekit.mjs"
: > "$FAKE/home/.env"

# Stub gen-image.sh: write a dummy PNG to the output path ($3).
cat > "$FAKE/skills/gen-image/scripts/gen-image.sh" <<'SH'
#!/usr/bin/env bash
printf 'fake-png' > "$3"
SH

# Stub node: `node imagekit.mjs list …` → cat $FAKE_LIST; `upload` → canned ok.
cat > "$FAKE/bin/node" <<'SH'
#!/usr/bin/env bash
for arg in "$@"; do
  case "$arg" in
    list)   cat "${FAKE_LIST:?FAKE_LIST not set}"; exit 0 ;;
    upload) printf '{"url":"https://ik.imagekit.io/stub"}\n'; exit 0 ;;
  esac
done
echo "node stub: unhandled args: $*" >&2
exit 1
SH

# Stub curl: pretend reference downloads succeed.
cat > "$FAKE/bin/curl" <<'SH'
#!/usr/bin/env bash
exit 0
SH

chmod +x "$FAKE/tools/image/to-webp.sh" "$FAKE/skills/gen-image/scripts/gen-image.sh" \
         "$FAKE/bin/node" "$FAKE/bin/curl"

run_gencard() {
  # $1 = phase label, $2 = canned list JSON file; rest = generate-card args.
  # Bound the complete generator invocation so a stubbed subprocess cannot hang CI.
  local phase="$1" list_json="$2" out err pid elapsed rc
  shift 2
  out="$FAKE/${phase}.stdout"
  err="$FAKE/${phase}.stderr"
  PATH="$FAKE/bin:$PATH" HOME="$FAKE/home" CLAUDE_PLUGIN_ROOT="$FAKE" FAKE_LIST="$list_json" \
    perl -MPOSIX=setsid -e 'defined setsid() or die "setsid failed: $!\n"; exec @ARGV' \
    bash "$GENCARD" "$@" --no-upload >"$out" 2>"$err" &
  pid=$!
  elapsed=0
  while kill -0 "$pid" 2>/dev/null && [ "$elapsed" -lt 20 ]; do
    sleep 1
    elapsed=$((elapsed + 1))
  done
  if kill -0 "$pid" 2>/dev/null; then
    # The generator and stubs share this session, so no child can outlive a timeout.
    kill -TERM -- "-$pid" 2>/dev/null || true
    sleep 2
    kill -KILL -- "-$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    printf 'FAIL: %s timed out after 20s\n' "$phase" >&2
    cat "$err" >&2
    return 1
  fi
  if wait "$pid"; then
    cat "$out"
  else
    rc=$?
    printf 'FAIL: %s exited %s\n' "$phase" "$rc" >&2
    cat "$err" >&2
    return 1
  fi
}

# ---- 1. --prefix picks max existing index + 1 ----------------------------
cat > "$FAKE/list-guides.json" <<'JSON'
[
  {"type":"file","name":"guide-04.webp","url":"https://ik.example/guide-04.webp"},
  {"type":"file","name":"guide-05.webp","url":"https://ik.example/guide-05.webp"},
  {"type":"file","name":"hero-banner.webp","url":"https://ik.example/hero-banner.webp"},
  {"type":"folder","name":"guide-99"}
]
JSON
out="$(run_gencard "prefix-existing" "$FAKE/list-guides.json" --folder guides --prefix guide --prompt "test subject")" || true
if has "$out" '"next":"06"' && has "$out" '"name":"guide-06.webp"'; then
  pass "--prefix: guide-04/05 present → next 06, name guide-06.webp"
else
  fail "--prefix numbering: got: $out"
fi

# ---- 2. empty folder starts at 01 ---------------------------------------
echo '[]' > "$FAKE/list-empty.json"
out="$(run_gencard "prefix-empty" "$FAKE/list-empty.json" --folder guides --prefix guide --prompt "test subject")" || true
if has "$out" '"next":"01"' && has "$out" '"name":"guide-01.webp"'; then
  pass "--prefix: empty folder → 01"
else
  fail "--prefix empty folder: got: $out"
fi

# ---- 3. unpadded legacy names still count -------------------------------
cat > "$FAKE/list-legacy.json" <<'JSON'
[
  {"type":"file","name":"guide-4.webp","url":"https://ik.example/guide-4.webp"},
  {"type":"file","name":"guide-02.webp","url":"https://ik.example/guide-02.webp"}
]
JSON
out="$(run_gencard "prefix-legacy" "$FAKE/list-legacy.json" --folder guides --prefix guide --prompt "test subject")" || true
if has "$out" '"next":"05"'; then
  pass "--prefix: unpadded guide-4.webp counts → next 05"
else
  fail "--prefix legacy names: got: $out"
fi

# ---- 4. non-webp and folder entries are ignored --------------------------
cat > "$FAKE/list-noise.json" <<'JSON'
[
  {"type":"file","name":"guide-07.png","url":"https://ik.example/guide-07.png"},
  {"type":"folder","name":"guide-08.webp"},
  {"type":"file","name":"guide-03.webp","url":"https://ik.example/guide-03.webp"}
]
JSON
out="$(run_gencard "prefix-noise" "$FAKE/list-noise.json" --folder guides --prefix guide --prompt "test subject")" || true
if has "$out" '"next":"04"'; then
  pass "--prefix: .png files and folders ignored → next 04"
else
  fail "--prefix noise filtering: got: $out"
fi

# ---- 5. --name path: exact name, no next field ---------------------------
out="$(run_gencard "exact-name" "$FAKE/list-guides.json" --folder toolkit --name my-slug.webp --prompt "test subject")" || true
if has "$out" '"name":"my-slug.webp"' && ! has "$out" '"next"'; then
  pass "--name: exact filename kept, no next field"
else
  fail "--name path: got: $out"
fi

echo ""
if [[ $FAILURES -eq 0 ]]; then
  printf "\033[32mall %d tests passed\033[0m\n" "$PASSES"
else
  printf "\033[31m%d test(s) FAILED\033[0m\n" "$FAILURES"
  exit 1
fi
