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

`facilitron-logo.png` is rasterized from the marketing-pages SVG. When the brand logo changes:

```bash
rsvg-convert -w 600 <marketing-pages>/public/img/logos/facilitron-logo.svg \
  -o "$SKILL_DIR/facilitron-logo.png"
```
