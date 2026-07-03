#!/usr/bin/env bash
# Deterministic fetch + meta-extraction for /seo-audit.
#
# Usage:
#   seo-audit.sh <url>                          # curl the live page
#   seo-audit.sh --html-file <page.html> [url]  # parse a local file (no network)
#
# stdout: ONE JSON line —
#   {url, final_url, status, redirects, robots_meta, canonical, title,
#    title_length, meta_description, meta_description_length, h1s, h1_count,
#    img_total, img_with_alt, img_alt_coverage}
# stderr: narration.
# Exit: 0 = fetched+parsed, 1 = fetch/read failure, 2 = usage / missing dep.
set -euo pipefail

usage() { echo "usage: seo-audit.sh <url> | seo-audit.sh --html-file <page.html> [<url>]" >&2; exit 2; }

url="" html_file=""
while [ $# -gt 0 ]; do
  case "$1" in
    --html-file) [ $# -ge 2 ] || usage; html_file="$2"; shift 2 ;;
    -h|--help) usage ;;
    -*) usage ;;
    *) [ -z "$url" ] || usage; url="$1"; shift ;;
  esac
done
[ -n "$url" ] || [ -n "$html_file" ] || usage
command -v python3 >/dev/null 2>&1 || { echo "seo-audit.sh: python3 is required" >&2; exit 2; }

status="" redirects=0 final_url="$url"
if [ -n "$html_file" ]; then
  [ -r "$html_file" ] || { echo "seo-audit.sh: cannot read $html_file" >&2; exit 1; }
  echo "→ parsing local file $html_file (no fetch)" >&2
  page="$html_file"
else
  page="$(mktemp)"; trap 'rm -f "$page"' EXIT
  echo "→ fetching $url" >&2
  # --compressed: marketing pages are CloudFront gzip. -L follows the redirect
  # chain; -w reports final status / hop count / landing URL.
  if ! meta="$(curl -sSL --compressed -A "Mozilla/5.0" -o "$page" \
                 -w '%{http_code}\t%{num_redirects}\t%{url_effective}' "$url")"; then
    echo "seo-audit.sh: fetch failed for $url" >&2; exit 1
  fi
  status="${meta%%$'\t'*}"; rest="${meta#*$'\t'}"
  redirects="${rest%%$'\t'*}"; final_url="${rest#*$'\t'}"
  echo "→ HTTP $status after $redirects redirect(s) → $final_url" >&2
fi

STATUS="$status" REDIRECTS="$redirects" URL="$url" FINAL_URL="$final_url" \
python3 - "$page" <<'PY'
import json, os, sys
from html.parser import HTMLParser

class Extract(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.title = None; self.meta_description = None
        self.robots_meta = None; self.canonical = None
        self.h1s = []; self.img_total = 0; self.img_with_alt = 0
        self._in_title = False; self._in_h1 = False; self._buf = []
    def handle_starttag(self, tag, attrs):
        a = {k.lower(): (v or "") for k, v in attrs}
        if tag == "title" and self.title is None:
            self._in_title = True; self._buf = []
        elif tag == "h1":
            self._in_h1 = True; self._buf = []
        elif tag == "meta":
            name = a.get("name", "").lower()
            if name == "description" and self.meta_description is None:
                self.meta_description = a.get("content", "").strip()
            elif name == "robots" and self.robots_meta is None:
                self.robots_meta = a.get("content", "").strip()
        elif tag == "link":
            rels = a.get("rel", "").lower().split()
            if "canonical" in rels and self.canonical is None:
                self.canonical = a.get("href", "").strip()
        elif tag == "img":
            self.img_total += 1
            if a.get("alt", "").strip():
                self.img_with_alt += 1
    def handle_endtag(self, tag):
        if tag == "title" and self._in_title:
            self._in_title = False
            self.title = " ".join("".join(self._buf).split())
        elif tag == "h1" and self._in_h1:
            self._in_h1 = False
            self.h1s.append(" ".join("".join(self._buf).split()))
    def handle_data(self, data):
        if self._in_title or self._in_h1:
            self._buf.append(data)

with open(sys.argv[1], "r", encoding="utf-8", errors="replace") as f:
    p = Extract(); p.feed(f.read())

status = os.environ.get("STATUS", "")
out = {
    "url": os.environ.get("URL", ""),
    "final_url": os.environ.get("FINAL_URL", ""),
    "status": int(status) if status.isdigit() else None,
    "redirects": int(os.environ.get("REDIRECTS") or 0),
    "robots_meta": p.robots_meta,
    "canonical": p.canonical,
    "title": p.title,
    "title_length": len(p.title) if p.title else 0,
    "meta_description": p.meta_description,
    "meta_description_length": len(p.meta_description) if p.meta_description else 0,
    "h1s": p.h1s,
    "h1_count": len(p.h1s),
    "img_total": p.img_total,
    "img_with_alt": p.img_with_alt,
    "img_alt_coverage": round(p.img_with_alt / p.img_total, 2) if p.img_total else None,
}
print(json.dumps(out, separators=(",", ":"), ensure_ascii=False))
PY
