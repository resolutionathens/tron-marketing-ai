---
name: md-to-pdf
model: sonnet
effort: medium
description: Convert a Facilitron Nuxt-Content markdown file into a branded PDF (a branded document), authored from the Facilitron-branded LaTeX template (brand fonts, logo, eyebrow kicker, stat cards, dashboard tables, fillable checkboxes). Use when the user wants to convert markdown to PDF or generate a PDF from a markdown SOP, checklist, template, or news post — phrases like "make a PDF of this", "build a PDF", "convert markdown to PDF", "generate a PDF", "generate a PDF download for the toolkit", or "turn this markdown into a downloadable branded document" trigger it. A pandoc-from-markdown fallback exists for quick prose-only output. Output goes to /tmp/facilitron-md-to-pdf by default.
allowed-tools:
  - Bash
  - Read
  - Write
scout:
  surface: true
  title: "Make a branded PDF"
  blurb: "Turns a markdown document into a Facilitron-branded, print-ready PDF."
  when: "A checklist, SOP, or onesheet needs to become a polished document."
  category: media
  effects: [local]
  inputs:
    - key: source
      label: "Markdown file"
      type: path
      required: true
      placeholder: "Pick the markdown to render to PDF"
      accept: ".md,.markdown"
---

# Facilitron Markdown → PDF

Convert Facilitron Nuxt-Content markdown into branded PDFs.

This skill ships its LaTeX template, brand fonts, logo, and a pandoc build script inside the `tron` plugin:

```
$SKILL_DIR/   # template.tex, fonts/, facilitron-logo.png, build.ts
```

**Resolve `$SKILL_DIR` robustly first.** `$CLAUDE_SKILL_DIR` is _not_ always exported into the agent's Bash environment (e.g. under the headless worker), and the plugin's cache path is version-pinned — so never hardcode a path like `…/cache/tron/tron/0.8.0/skills/md-to-pdf`. Compute it once and reuse it in every command below:

```bash
name=md-to-pdf
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${CLAUDE_SKILL_DIR:+$CLAUDE_SKILL_DIR/../..}}"
RESOLVER="${PLUGIN_ROOT:+$PLUGIN_ROOT/tools/skill/resolve-skill-dir.sh}"
[ -f "${RESOLVER:-}" ] || RESOLVER="$(find ~/.claude/plugins/cache ~/.claude/plugins/marketplaces ~/.codex/plugins/cache ~/.codex/plugins/marketplaces "$HOME/Library/Application Support/tron-os/tron-releases/versions" -maxdepth 7 -type f -path "*/tools/skill/resolve-skill-dir.sh" 2>/dev/null | sort -V | tail -1 || true)"
[ -f "${RESOLVER:-}" ] || { echo "tron:$name: resolver not found; searched Claude/Codex cache and marketplace roots plus the tron release store" >&2; exit 1; }
SKILL_DIR="$(bash "$RESOLVER" "$name" template.tex)"
```

This prefers the env hint, then the newest _installed copy that actually contains the asset_ (so a stale mirror missing it is skipped, and same-version ties go to the marketplace copy) — and survives a plugin version bump. `build.ts` additionally resolves its own assets relative to itself (`import.meta.url`), so once you invoke it through `$SKILL_DIR` it needs no env var at all.

## Two paths — default to LaTeX

**The preferred, default path is authoring the PDF in LaTeX from `template.tex`.** Its output is consistently cleaner — brand fonts and color, controlled spacing, proper tables, fillable form fields, reliable page breaks — and it mirrors the marketing-pages site styling. Use it for anything with tables, fillable fields, stat callouts, or multi-section structure (i.e. almost everything).

The **pandoc-from-markdown** path (`build.ts`) is a **fallback** — reach for it only when the content is genuinely prose-only (a short SOP with no tables or forms) and you want a quick render. It outputs in Helvetica, not the brand fonts, and degrades on tables.

---

## Default path — author in LaTeX from the template

The skill ships a Facilitron-branded starter at `$SKILL_DIR/template.tex`, styled to mirror the marketing-pages site (`assets/css/tailwind.css`). It pre-wires: the logo; the brand fonts (Inter body / Archivo display / IBM Plex Mono figures); `tron-asphalt-900` ink for text and headings (not pure black) with `tron-primary-600` links; an `\eyebrow{...}` kicker and an Archivo-ExtraLight hero title matching the site's weight-200 `frame-h1`; rounded `tron-primary-50` stat cards with a `primary-500` accent bar (`\stat{number}{label}` inside a `tcbraster`, the site's "callout" pattern); dashboard-style tables (gray-200 header via `\thd{}` + white/`gray-100` zebra + thin asphalt rules); the `\num{...}` mono-figure macro; and `\fchk` (outline checkbox).

```bash
mkdir -p /tmp/facilitron-md-to-pdf
# Substitute @@SKILLDIR@@ with this skill's bundled dir so the font + logo paths resolve
sed "s|@@SKILLDIR@@|$SKILL_DIR|g" "$SKILL_DIR/template.tex" > /tmp/facilitron-md-to-pdf/<slug>.tex
# Edit <slug>.tex — replace the title and example sections (the EDIT: markers) with real content
xelatex -interaction=nonstopmode -output-directory=/tmp/facilitron-md-to-pdf /tmp/facilitron-md-to-pdf/<slug>.tex
```

Edit the `EDIT:` markers for your content. The template uses `\graphicspath` to keep `\includegraphics{facilitron-logo.png}` resolving even when copied to `/tmp`, and references the vendored brand fonts in `fonts/` via the `@@SKILLDIR@@` token (substituted with `$SKILL_DIR` by the `sed` above), so it works with no further setup or system font install. **Run `xelatex` twice** if hyperref complains about needing a rerun for outlines.

> **Quotes:** the template wires up `csquotes` with `\MakeOuterQuote{"}`, so author body text with either real Unicode curly quotes (`“ ”`) or plain straight quotes (`"..."`) — both render as proper curly quotes in Archivo. **Never** use TeX-style ` ``...'' ` — the backtick opening-quote ligature doesn't map in the brand font and prints a literal `` ` `` glyph.

**Requirements:** `xelatex` (BasicTeX or MacTeX). The brand fonts are bundled — no system font install needed. See the plugin README's Dependencies section.

**Fonts.** The brand fonts are vendored in `fonts/` next to the template (Archivo + IBM Plex Mono as static weights; Inter as its upstream variable font, which is why bold is synthesized via `AutoFakeBold`). If the brand fonts change, drop the new files in `fonts/` and keep the filenames the template references.

For a small number of tables in an otherwise prose document, see [pandoc exceptions](reference/pandoc-exceptions.md).

---

## Fallback path — pandoc from markdown (prose-only)

A quick path for plain prose with no tables or forms. It renders in Helvetica (not the brand fonts) and is "dumb on purpose" — it pipes the markdown through pandoc with the logo and title bolted on top.

```bash
bun "$SKILL_DIR/build.ts" <file.md> [file.md ...] [--out <dir>]
```

- One or more markdown file paths (positional)
- `--out <dir>` — optional output directory (default: `/tmp/facilitron-md-to-pdf`)

It writes both the cleaned intermediate `<slug>.md` and the final `<slug>.pdf` into the output directory.

**What it does:**

- Strips YAML front matter (uses `title` for the PDF heading)
- Expands `::faq` MDC blocks back into `## FAQs` + `### Question` + answer paragraphs
- Strips `::checklist-group` / closing `::` wrappers (converts the bullet items to `- [ ]` checkboxes)
- Prepends the Facilitron logo (PNG, 160px wide) and an H1 title
- Runs `pandoc --pdf-engine=xelatex -V mainfont="Helvetica"` with hyperlink colors

**Requirements:** `bun` (runs the script), `pandoc` (`brew install pandoc`), `xelatex`, and the `yaml` npm package (installed inside the skill via `bun install`).

**What it can't handle:**

- Tables with custom unicode glyphs (e.g., `☐`) — Helvetica lacks them. Use `[ ]` instead.
- Embedded images other than the logo — not auto-resolved. Inline images need local file paths or absolute URLs pandoc can fetch.
- MDC components other than `::faq` and `::checklist-group`. Add handlers to `build.ts` for `::wistiaVideo`, `::quote`, etc.
- **Complex multi-column tables** — pandoc's pipe-table rendering through xelatex squishes wide columns and breaks across pages without repeating headers. This is the signal to switch to the LaTeX path above.

### Auto-warning

`build.ts` scans the input for table density and prints a warning to stderr before invoking pandoc when it sees **3 or more pipe tables** OR **any table with more than 4 columns**. It points at `template.tex` and the LaTeX path. It's a nudge, not a blocker — the script still produces the PDF. If the result is fine, ignore it; if it's ugly, switch to LaTeX.

---

## Shared finish — review then upload

Whichever path you used, the PDF lands wherever you wrote it (default `/tmp/facilitron-md-to-pdf`). Then:

1. Open the resulting PDF(s) so the user can review (`open <pdf-path>`).
2. After approval, upload to ImageKit using the imagekit CLI:
   ```bash
   node "${CLAUDE_PLUGIN_ROOT:-$SKILL_DIR/../..}/tools/imagekit/imagekit.mjs" upload <path-to-pdf> --name <filename>.pdf --folder <imagekit-folder>
   ```
   Always pass `--name` so ImageKit doesn't append a random suffix to the filename.
3. Reference the uploaded PDF from the markdown via the appropriate front-matter field (e.g., `download: <filename>.pdf` for toolkit items).

## What goes into the PDF

It's the caller's job to decide what the PDF should _contain_. For toolkit items in particular, the PDF is the printable take-away (the procedure or checklist body), not a clone of the SEO-rich web page. Strip the lead-in copy, "What is …?" framing, Compliance/Version-Control sections, and `::faq` blocks before building. The `tron:toolkit-item` skill walks through this in detail.

For logo regeneration details, see [pandoc exceptions](reference/pandoc-exceptions.md).
