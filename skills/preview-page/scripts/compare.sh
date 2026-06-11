#!/usr/bin/env bash
# compare.sh: refresh the Figma ↔ Dev compare view at Figma-native viewport.
#
# Usage:
#   compare.sh <figma-png> <route> <section-index>
#     - figma-png:      path to the Figma node screenshot
#     - route:          path on the dev server (e.g. /solutions/maintenance-teams)
#     - section-index:  0-based nth-of-type([class*="py-16"]) in the page DOM
#
# Example:
#   compare.sh /tmp/figma-section4.png /solutions/maintenance-teams 4
#
# What it does:
#   1. Spawns a headless Chromium at 1440x2400 (Figma-native width), navigates
#      to the route, locates the target section, and clips a screenshot to its
#      bounding box. This gives a dev render at the same width Figma renders
#      its node at, so element positions overlay cleanly.
#   2. Writes /tmp/cmp-figma.png and /tmp/cmp-dev.png.
#   3. Starts the static server on :4002 if needed.
#   4. (Re)opens the compare page in the cmux browser pane. The compare page
#      has three modes: SIDE (side-by-side), STACK (opacity slider), DIFF
#      (mix-blend-mode: difference).
#
# Why Playwright instead of cmux:
#   cmux uses macOS WKWebView, which does not support setViewportSize. We need
#   1440px to match Figma. Playwright headless Chromium handles this cleanly.

set -euo pipefail

# Subcommand: list — enumerate matched sections on a route, no screenshots.
#   compare.sh --list <route>
if [[ "${1:-}" == "--list" || "${1:-}" == "list" ]]; then
  if [[ $# -lt 2 ]]; then
    echo "usage: compare.sh --list <route>" >&2
    exit 2
  fi
  SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  SKILL_DIR=$(dirname "$SCRIPT_DIR")
  URL="http://localhost:4001${2}"
  (cd "$SKILL_DIR" && bun scripts/section-shot.mjs "$URL" list)
  exit 0
fi

# Subcommand: full — capture a whole-page screenshot at 1440 wide.
#   compare.sh --full <route> <out-path>
if [[ "${1:-}" == "--full" || "${1:-}" == "full" ]]; then
  if [[ $# -lt 3 ]]; then
    echo "usage: compare.sh --full <route> <out-path>" >&2
    exit 2
  fi
  SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  SKILL_DIR=$(dirname "$SCRIPT_DIR")
  URL="http://localhost:4001${2}"
  (cd "$SKILL_DIR" && bun scripts/section-shot.mjs "$URL" full "$3")
  exit 0
fi

if [[ $# -lt 3 ]]; then
  echo "usage: compare.sh <figma-png> <route> <section-index>" >&2
  echo "       compare.sh --list <route>" >&2
  echo "       compare.sh --full <route> <out-path>" >&2
  exit 2
fi

FIGMA_SRC="$1"
ROUTE="$2"
SECTION_IDX="$3"
COMPARE_HTML=/tmp/compare.html
COMPARE_SURFACE_FILE=/tmp/compare-surface
SURFACE_FILE=/tmp/preview-page-surface
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SKILL_DIR=$(dirname "$SCRIPT_DIR")
DEV_PORT=4001

# ---- 1. Capture dev at 1440 via Playwright -----------------------------------
[[ -f "$FIGMA_SRC" ]] || { echo "missing figma png: $FIGMA_SRC" >&2; exit 1; }
cp "$FIGMA_SRC" /tmp/cmp-figma.png

URL="http://localhost:${DEV_PORT}${ROUTE}"
(
  cd "$SKILL_DIR"
  bun scripts/section-shot.mjs "$URL" "$SECTION_IDX" /tmp/cmp-dev.png
) >&2

# ---- 2. Write the HTML (always rewrite — small, evolves over time) -----------
cat > "$COMPARE_HTML" <<'EOF'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Figma vs Dev — compare</title>
<style>
  :root { color-scheme: light dark; }
  * { box-sizing: border-box; }
  body { margin: 0; font: 13px/1.4 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background: #0b0d10; color: #e8e8ea; }
  header { position: sticky; top: 0; z-index: 10; padding: 8px 14px; background: #15181d; border-bottom: 1px solid #23262d; display: flex; align-items: center; gap: 14px; }
  header h1 { margin: 0; font-size: 12px; font-weight: 600; letter-spacing: .12em; text-transform: uppercase; color: #9aa0a6; }
  header .modes { display: flex; gap: 4px; }
  header .modes button { background: #1f2329; color: #cfd2d6; border: 1px solid #2a2e35; padding: 5px 10px; border-radius: 6px; font-size: 12px; cursor: pointer; }
  header .modes button.active { background: #1670e6; color: #fff; border-color: #1670e6; }
  header .opacity-row { display: none; align-items: center; gap: 8px; margin-left: auto; }
  header .opacity-row.show { display: flex; }
  header .opacity-row input { width: 220px; }
  header .opacity-row label { font-size: 12px; color: #9aa0a6; }
  header .dims { margin-left: auto; font-size: 11px; color: #6c727a; }
  main { height: calc(100vh - 41px); overflow: auto; }

  /* SIDE: two-column scroll */
  .side .pane { background: #1a1d22; border-right: 1px solid #23262d; overflow: auto; }
  .side .pane:last-child { border-right: none; }
  .side .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 0; height: 100%; }
  .side .pane h2 { position: sticky; top: 0; margin: 0; padding: 8px 12px; background: rgba(11,13,16,.92); backdrop-filter: blur(8px); font-size: 11px; font-weight: 600; letter-spacing: .12em; text-transform: uppercase; color: #9aa0a6; border-bottom: 1px solid #23262d; }
  .side .pane h2 .badge { float: right; font-weight: 400; color: #6c727a; text-transform: none; letter-spacing: 0; }
  .side .pane img { display: block; width: 100%; height: auto; }

  /* STACK: images overlaid; opacity slider blends top image */
  .stack .wrap { position: relative; width: 100%; max-width: 1440px; margin: 0 auto; background: #1a1d22; }
  .stack .wrap img { display: block; width: 100%; height: auto; }
  .stack .wrap img.top { position: absolute; top: 0; left: 0; opacity: 0.5; }

  /* DIFF: same stack as STACK but with mix-blend-mode: difference */
  .diff .wrap { position: relative; width: 100%; max-width: 1440px; margin: 0 auto; background: #000; }
  .diff .wrap img { display: block; width: 100%; height: auto; }
  .diff .wrap img.top { position: absolute; top: 0; left: 0; mix-blend-mode: difference; }

  /* hide modes not in use */
  main > section { display: none; height: 100%; }
  main > section.active { display: block; }
</style>
</head>
<body>
<header>
  <h1>Figma ↔ Dev</h1>
  <div class="modes">
    <button data-mode="side" class="active">Side</button>
    <button data-mode="stack">Stack</button>
    <button data-mode="diff">Diff</button>
  </div>
  <div class="opacity-row">
    <label>dev opacity</label>
    <input id="opacity" type="range" min="0" max="100" value="50">
    <span id="opacity-val">50%</span>
  </div>
  <div class="dims" id="dims"></div>
</header>
<main>
  <section class="side active">
    <div class="grid">
      <div class="pane">
        <h2>Figma <span class="badge" id="figma-dims-side"></span></h2>
        <img id="figma-side" src="cmp-figma.png" alt="Figma render">
      </div>
      <div class="pane">
        <h2>Dev <span class="badge" id="dev-dims-side"></span></h2>
        <img id="dev-side" src="cmp-dev.png" alt="Dev render">
      </div>
    </div>
  </section>
  <section class="stack">
    <div class="wrap">
      <img class="bottom" src="cmp-figma.png" alt="Figma render">
      <img id="stack-dev" class="top" src="cmp-dev.png" alt="Dev render">
    </div>
  </section>
  <section class="diff">
    <div class="wrap">
      <img class="bottom" src="cmp-figma.png" alt="Figma render">
      <img class="top" src="cmp-dev.png" alt="Dev render">
    </div>
  </section>
</main>
<script>
  // Cache-bust to defeat browser cache when PNGs are re-written.
  const t = Date.now();
  document.querySelectorAll('img').forEach(el => {
    el.src = el.getAttribute('src') + '?t=' + t;
  });

  // Mode switching
  const sections = document.querySelectorAll('main > section');
  const opacityRow = document.querySelector('.opacity-row');
  document.querySelectorAll('.modes button').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.modes button').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      const mode = btn.dataset.mode;
      sections.forEach(s => s.classList.toggle('active', s.classList.contains(mode)));
      opacityRow.classList.toggle('show', mode === 'stack');
    });
  });

  // Opacity slider for STACK mode
  const opacity = document.getElementById('opacity');
  const opacityVal = document.getElementById('opacity-val');
  const stackDev = document.getElementById('stack-dev');
  opacity.addEventListener('input', () => {
    const v = opacity.value;
    stackDev.style.opacity = v / 100;
    opacityVal.textContent = v + '%';
  });

  // Show dimensions
  function updateDims() {
    const f = document.getElementById('figma-side');
    const d = document.getElementById('dev-side');
    if (f.complete && d.complete) {
      const fd = `${f.naturalWidth} × ${f.naturalHeight}`;
      const dd = `${d.naturalWidth} × ${d.naturalHeight}`;
      document.getElementById('figma-dims-side').textContent = fd;
      document.getElementById('dev-dims-side').textContent = dd;
      document.getElementById('dims').textContent = `figma ${fd}  ·  dev ${dd}`;
    }
  }
  document.getElementById('figma-side').addEventListener('load', updateDims);
  document.getElementById('dev-side').addEventListener('load', updateDims);
  updateDims();

  // Keyboard: 1/2/3 to switch modes, ←/→ to nudge opacity in stack mode
  document.addEventListener('keydown', (e) => {
    if (e.key === '1') document.querySelector('[data-mode="side"]').click();
    if (e.key === '2') document.querySelector('[data-mode="stack"]').click();
    if (e.key === '3') document.querySelector('[data-mode="diff"]').click();
    if (e.key === 'ArrowLeft' && opacityRow.classList.contains('show')) {
      opacity.value = Math.max(0, +opacity.value - 5);
      opacity.dispatchEvent(new Event('input'));
    }
    if (e.key === 'ArrowRight' && opacityRow.classList.contains('show')) {
      opacity.value = Math.min(100, +opacity.value + 5);
      opacity.dispatchEvent(new Event('input'));
    }
  });
</script>
</body>
</html>
EOF

# ---- 3. Start static server on :4002 if not already up -----------------------
if ! lsof -ti:4002 >/dev/null 2>&1; then
  (cd /tmp && nohup python3 -m http.server 4002 >/tmp/compare-server.log 2>&1 &)
  for _ in $(seq 1 20); do
    lsof -ti:4002 >/dev/null 2>&1 && break
    sleep 0.1
  done
fi

COMPARE_URL="http://localhost:4002/compare.html"

# ---- 4. Reuse the compare surface if it exists, otherwise open new ----------
if [[ -f "$COMPARE_SURFACE_FILE" ]]; then
  S=$(cat "$COMPARE_SURFACE_FILE" 2>/dev/null || true)
  if [[ -n "${S:-}" ]] && cmux browser --surface "$S" url >/dev/null 2>&1; then
    cmux browser --surface "$S" reload >/dev/null 2>&1 || true
    echo "$S"
    echo "$COMPARE_URL"
    exit 0
  fi
fi

# ---- 5. Find browser pane (prefer the one preview.sh uses) ------------------
BROWSER_PANE=""
if [[ -f "$SURFACE_FILE" ]]; then
  PREV=$(cat "$SURFACE_FILE" 2>/dev/null || true)
  if [[ -n "${PREV:-}" ]]; then
    BROWSER_PANE=$(cmux browser --surface "$PREV" identify 2>/dev/null | grep -oE 'pane:[0-9]+' | head -1 || true)
  fi
fi
if [[ -z "$BROWSER_PANE" ]]; then
  PANES=$(cmux list-panes | awk '{ for (i=1; i<=NF; i++) if ($i ~ /^\*?pane:[0-9]+$/) print $i }' | sed 's/^\*//')
  while IFS= read -r pane; do
    [[ -z "$pane" ]] && continue
    if cmux list-pane-surfaces --pane "$pane" 2>/dev/null \
       | grep -Eq ' - (JIRA|GitHub|Confluence|YouTube|Google|localhost|[A-Za-z0-9-]+\.(com|io|dev|net|org|app))( |$|\[)'; then
      BROWSER_PANE="$pane"
      break
    fi
  done <<< "$PANES"
fi

if [[ -n "$BROWSER_PANE" ]]; then
  OPEN_OUT=$(cmux new-surface --type browser --pane "$BROWSER_PANE" --url "$COMPARE_URL" --focus false)
else
  OPEN_OUT=$(cmux new-pane --type browser --direction right --url "$COMPARE_URL" --focus false)
fi

SURFACE=$(printf '%s\n' "$OPEN_OUT" | grep -oE 'surface:[0-9]+' | head -1)
[[ -n "$SURFACE" ]] && printf '%s\n' "$SURFACE" > "$COMPARE_SURFACE_FILE"
echo "${SURFACE:-?}"
echo "$COMPARE_URL"
