# Pandoc Exceptions

## One or two tables in prose content

For otherwise prose or checklist content with one or two tables, the pandoc fallback can include raw LaTeX. Pandoc's `raw_tex` extension passes it through unchanged:

```markdown
## Maintenance schedule

\begin{tabular}{|p{3cm}|p{4cm}|p{6cm}|}
\hline
\textbf{Frequency} & \textbf{System} & \textbf{Task} \\
\hline
Monthly & HVAC & Replace filters; inspect drains \\
\hline
\end{tabular}
```

Use `longtable` instead of `tabular` when a table spans pages so headers repeat.

## Updating the logo

`facilitron-logo.png` is rasterized from the brand SVG shipped by the site repo. When the brand
logo changes, resolve that repo's root from its content profile rather than typing a checkout path
— the SVG lives under the repo's `public/` (a framework convention), but which checkout is the
site repo is a fact only the repo declares:

```bash
C="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/content/content.sh"
ROOT="$(bash "$C" paths --repo <site-checkout> | jq -r .root)" || exit 1
SVG="$ROOT/public/img/logos/facilitron-logo.svg"
[ -f "$SVG" ] || { echo "md-to-pdf: no brand SVG at $SVG — locate it in $ROOT before regenerating" >&2; exit 1; }
rsvg-convert -w 600 "$SVG" -o "$SKILL_DIR/facilitron-logo.png"
```

The `public/` location is a framework convention, not something the profile declares, so it is
checked rather than assumed. Rasterizing from a path that does not exist would leave the bundled
PNG silently stale, which is exactly the failure this step exists to prevent.
