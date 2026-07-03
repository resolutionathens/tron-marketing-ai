#!/usr/bin/env bash
# WCAG 2.x contrast ratio between two hex colors (full sRGB relative-luminance
# formula — no eyeballed shortcuts).
#
# Usage: contrast.sh <fg-hex> <bg-hex>     hex as #RGB or #RRGGBB, '#' optional
#
# Prints the ratio and PASS/FAIL at AA thresholds:
#   4.5:1 — normal body text
#   3:1   — large text (≥24px, or ≥19px bold) and UI components / graphics
#
# Exit codes: 0 = computed (regardless of pass/fail), 2 = bad arguments.
set -euo pipefail

usage() { echo "usage: contrast.sh <fg-hex> <bg-hex>   e.g. contrast.sh '#1F2933' '#FFFFFF'" >&2; exit 2; }
[ $# -eq 2 ] || usage

norm() { # normalize to RRGGBB (lowercase, no '#'); exit 2 on anything else
  local h="${1#\#}"
  h="$(printf '%s' "$h" | tr 'A-F' 'a-f')"
  case "$h" in
    [0-9a-f][0-9a-f][0-9a-f]) h="${h:0:1}${h:0:1}${h:1:1}${h:1:1}${h:2:1}${h:2:1}" ;;
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
    *) echo "contrast.sh: bad hex color '$1' (want #RGB or #RRGGBB)" >&2; exit 2 ;;
  esac
  printf '%s' "$h"
}

fg="$(norm "$1")"; bg="$(norm "$2")"

lum() { # relative luminance of RRGGBB per WCAG: linearize each sRGB channel, weight
  awk -v r="$((16#${1:0:2}))" -v g="$((16#${1:2:2}))" -v b="$((16#${1:4:2}))" 'BEGIN {
    c[1]=r; c[2]=g; c[3]=b
    for (i = 1; i <= 3; i++) {
      v = c[i] / 255
      c[i] = (v <= 0.03928) ? v / 12.92 : ((v + 0.055) / 1.055) ^ 2.4
    }
    printf "%.10f", 0.2126*c[1] + 0.7152*c[2] + 0.0722*c[3]
  }'
}

Lfg="$(lum "$fg")"; Lbg="$(lum "$bg")"

awk -v a="$Lfg" -v b="$Lbg" -v fg="#$fg" -v bg="#$bg" 'BEGIN {
  hi = (a > b) ? a : b; lo = (a > b) ? b : a
  r = (hi + 0.05) / (lo + 0.05)
  printf "%s on %s — contrast ratio %.2f:1\n", fg, bg, r
  printf "AA normal text (4.5:1): %s\n", (r >= 4.5) ? "PASS" : "FAIL"
  printf "AA large text / UI (3:1): %s\n", (r >= 3.0) ? "PASS" : "FAIL"
}'
