---
name: md-to-pdf
description: Convert a Facilitron Nuxt-Content markdown file into a branded PDF (Facilitron logo at the top, title from front matter, expanded ::faq blocks, stripped ::checklist-group wrappers). Use when the user wants to build a PDF from a markdown SOP, checklist, template, or news post — phrases like "make a PDF of this", "build a PDF", "generate a PDF download for the toolkit", or "turn this markdown into a downloadable PDF" trigger it. Output goes to /tmp/facilitron-md-to-pdf by default.
---

# Facilitron Markdown → PDF

Convert one or more Facilitron Nuxt-Content markdown files into branded PDFs.

This skill ships its build script, LaTeX template, brand fonts, and logo inside the `tron` plugin. Reference them through `$CLAUDE_SKILL_DIR` — the plugin sets it to this skill's bundled directory, so commands work from any worktree or cwd:

```
$CLAUDE_SKILL_DIR/   # build.ts, template.tex, fonts/, facilitron-logo.png
```

## Prefer the LaTeX path

**Default to authoring the PDF in LaTeX from `template.tex` (Option B below), not the pandoc-from-markdown `build.ts` path.** In practice the LaTeX output is consistently cleaner — controlled spacing, proper tables, fillable form fields, reliable page breaks — while the pandoc path degrades on anything beyond plain prose. Reach for `build.ts` only when the content is genuinely prose-only (a short SOP with no tables or forms) and you want the quick path. Anything with tables, fillable fields, or multi-section structure: go straight to LaTeX.

## What it does

- Strips YAML front matter (uses `title` for the PDF heading)
- Expands `::faq` MDC blocks back into `## FAQs` + `### Question` + answer paragraphs
- Strips `::checklist-group` and closing `::` wrapper lines (leaves the bullet items)
- Prepends the Facilitron logo (PNG, 160px wide) and an H1 title
- Runs `pandoc --pdf-engine=xelatex -V mainfont="Helvetica"` with hyperlink colors

## Requirements

The skill assumes these are installed (already true on Ian's machine):

- `bun` — runs the script
- `pandoc` (Homebrew: `brew install pandoc`) — typesetting
- `xelatex` (BasicTeX or MacTeX) — PDF engine
- `yaml` npm package — installed inside the skill via `bun install`

## Usage (pandoc path — prose-only fallback)

```bash
bun "$CLAUDE_SKILL_DIR/build.ts" <file.md> [file.md ...] [--out <dir>]
```

- One or more markdown file paths (positional)
- `--out <dir>` — optional output directory (default: `/tmp/facilitron-md-to-pdf`)

The script writes both the cleaned intermediate `<slug>.md` and the final `<slug>.pdf` into the output directory.

## Workflow

1. Run the script on the markdown file(s).
2. Open the resulting PDF(s) so the user can review (`open <pdf-path>`).
3. After approval, upload to ImageKit using the imagekit CLI:
   ```bash
   node ~/.claude/tools/imagekit/imagekit.mjs upload <path-to-pdf> --name <filename>.pdf --folder <imagekit-folder>
   ```
   Always pass `--name` so ImageKit doesn't append a random suffix to the filename.
4. Reference the uploaded PDF from the markdown via the appropriate front-matter field (e.g., `download: <filename>.pdf` for toolkit items).

## What goes into the markdown you feed the script

The script is dumb on purpose — it pipes whatever you give it through pandoc with the Facilitron logo and title bolted on top. It's the caller's job to decide what the PDF should *contain*. For toolkit items in particular, the PDF is meant to be the printable take-away (the procedure or checklist body), not a clone of the SEO-rich web page. Build a trimmed temp markdown that strips the lead-in copy, "What is …?" framing, Compliance/Version-Control sections, and `::faq` blocks before running the script. The `tron:toolkit-item` skill walks through this in detail.

## What the script can't handle

- Tables with custom unicode glyphs (e.g., `☐`) — Helvetica lacks them. Use `[ ]` instead.
- Embedded images other than the logo — they're not auto-resolved. Inline images in the markdown body would need to be local file paths or absolute URLs that pandoc can fetch.
- MDC components other than `::faq` and `::checklist-group`. Add new handlers to `build.ts` if you need to expand `::wistiaVideo`, `::quote`, etc.
- **Complex multi-column tables.** Pandoc's pipe-table rendering through xelatex is fine for 2–3 narrow columns but degrades quickly: long cells wrap weirdly, columns get squished, and tables break across pages without repeating headers. Below is the escalation path.

### Auto-warning

`build.ts` scans the input for table density and prints a warning to stderr before invoking pandoc when it sees:

- 3 or more pipe tables, OR
- any table with more than 4 columns

The warning points at `template.tex` and the escalation section below. It's a nudge, not a blocker — the script still produces the markdown PDF. If the result is fine, ignore the warning. If it's ugly, switch to LaTeX.

## Escalating to LaTeX for table-heavy PDFs

When the content is mostly structured tabular data (e.g., a maintenance schedule template with frequency × system × task columns, a vendor comparison matrix, a multi-row inventory log), pandoc-from-markdown produces a worse PDF than authoring the table in LaTeX directly. Two ways to escalate:

**Option A — inline raw LaTeX inside the markdown.** Pandoc's `raw_tex` extension is on by default with the markdown reader, so a `\begin{tabular}…\end{tabular}` block in the body passes through untouched. Use this when most of the document is prose/checklists with one or two tables that need precise control:

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

For tables that span pages, swap `tabular` for `longtable` so headers repeat and the table breaks cleanly.

**Option B — start from `template.tex` and run xelatex directly. This is the preferred path (see "Prefer the LaTeX path" above).** The skill ships a Facilitron-branded starter at `$CLAUDE_SKILL_DIR/template.tex`, styled to mirror the marketing-pages site (`assets/css/tailwind.css`). It pre-wires: the logo; the brand fonts (Inter body / Archivo display / IBM Plex Mono figures); `tron-asphalt-900` ink for text and headings (not pure black) with `tron-primary-600` links; an `\eyebrow{...}` kicker and an Archivo-ExtraLight hero title matching the site's weight-200 `frame-h1`; rounded `tron-primary-50` stat cards with a `primary-500` accent bar (`\stat{number}{label}` inside a `tcbraster`, the site's "callout" pattern); dashboard-style tables (gray-200 header via `\thd{}` + white/`gray-100` zebra + thin asphalt rules); the `\num{...}` mono-figure macro; and `\fchk` (outline checkbox). Edit the `EDIT:` markers for your content:

```bash
mkdir -p /tmp/facilitron-md-to-pdf
# Substitute @@SKILLDIR@@ with this skill's bundled dir so the font + logo paths resolve
sed "s|@@SKILLDIR@@|$CLAUDE_SKILL_DIR|g" "$CLAUDE_SKILL_DIR/template.tex" > /tmp/facilitron-md-to-pdf/<slug>.tex
# Edit <slug>.tex — replace the title and example sections with real content
xelatex -interaction=nonstopmode -output-directory=/tmp/facilitron-md-to-pdf /tmp/facilitron-md-to-pdf/<slug>.tex
```

The template uses `\graphicspath` to keep `\includegraphics{facilitron-logo.png}` resolving even when copied to `/tmp`, and references the vendored brand fonts in `fonts/` via the `@@SKILLDIR@@` token (substituted with `$CLAUDE_SKILL_DIR` by the `sed` above), so it works with no further setup or system font install. Run `xelatex` twice if hyperref complains about needing a rerun for outlines.

**Fonts.** The brand fonts are vendored in `fonts/` next to the template (Archivo + IBM Plex Mono as static weights; Inter as its upstream variable font, which is why bold is synthesized via `AutoFakeBold`). If the brand fonts change, drop the new files in `fonts/` and keep the filenames the template references. The pandoc fallback path (`build.ts`) still renders in Helvetica — it's the prose-only quick path; use the LaTeX template when brand fonts matter.

Either way, when you're done the PDF lands wherever you wrote it — open it and let the user confirm before uploading, same as the markdown path.

## When to update the logo

The logo PNG (`facilitron-logo.png`) was rasterized once from `public/img/logos/facilitron-logo.svg` via `rsvg-convert -w 600`. If the brand logo changes, regenerate it:

```bash
rsvg-convert -w 600 /Users/slip/Documents/GitHub/marketing-pages/public/img/logos/facilitron-logo.svg \
  -o "$CLAUDE_SKILL_DIR/facilitron-logo.png"
```
