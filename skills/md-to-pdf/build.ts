#!/usr/bin/env bun
// Build branded PDFs from Facilitron Nuxt-Content markdown files.
//
// - Strips front matter (title is read from it)
// - Expands ::faq MDC blocks into "## FAQs" + "### Question" + answer paragraphs
// - Strips ::checklist-group wrappers (leaves bullet items as-is)
// - Prepends the Facilitron logo and an H1 title
// - Runs pandoc with xelatex to produce a PDF
//
// Usage:
//   bun "$CLAUDE_SKILL_DIR/build.ts" <file.md> [file.md ...] [--out <dir>] [--emit-md]
//
// --emit-md stops after the parse/clean stage: it writes the intermediate
// markdown (front matter stripped, ::faq expanded, checklists converted, logo +
// title prepended) to <out>/<slug>.md and skips the pandoc/xelatex render.
// Used by test-build.sh to test the parsing without a TeX toolchain.

import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { join, basename, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";
import { parse as parseYaml } from "yaml";

const SKILL_DIR = dirname(fileURLToPath(import.meta.url));
const LOGO_PATH = join(SKILL_DIR, "facilitron-logo.png");

const args = process.argv.slice(2);
let outDir = "/tmp/facilitron-md-to-pdf";
let emitMdOnly = false;
const files: string[] = [];
for (let i = 0; i < args.length; i++) {
  if (args[i] === "--out") {
    outDir = resolve(args[++i]);
  } else if (args[i] === "--emit-md") {
    emitMdOnly = true;
  } else {
    files.push(resolve(args[i]));
  }
}

if (files.length === 0) {
  console.error("Usage: build.ts <file.md> [file.md ...] [--out <dir>]");
  process.exit(1);
}

mkdirSync(outDir, { recursive: true });

function splitFrontMatter(raw: string): { front: Record<string, unknown>; body: string } {
  if (!raw.startsWith("---\n")) return { front: {}, body: raw };
  const end = raw.indexOf("\n---\n", 4);
  if (end === -1) return { front: {}, body: raw };
  const yaml = raw.slice(4, end);
  const body = raw.slice(end + 5);
  return { front: parseYaml(yaml) as Record<string, unknown>, body };
}

function expandFaqBlocks(md: string): string {
  const re = /::faq\s*\n---\n([\s\S]*?)\n---\n::/g;
  return md.replace(re, (_, yaml) => {
    const data = parseYaml(yaml) as { title?: string; faqItems: { question: string; answer: string }[] };
    const lines: string[] = [];
    lines.push(`## ${data.title ?? "FAQs"}\n`);
    for (const item of data.faqItems) {
      lines.push(`### ${item.question}\n`);
      lines.push(`${item.answer}\n`);
    }
    return lines.join("\n");
  });
}

// Detect table-heavy markdown so we can suggest the LaTeX template before
// pandoc produces a possibly-ugly PDF. A "table" here is a pipe-table whose
// header row is followed by a separator row (|---|---|...).
function analyzeTables(md: string): { count: number; maxCols: number } {
  const lines = md.split("\n");
  let count = 0;
  let maxCols = 0;
  for (let i = 0; i < lines.length - 1; i++) {
    const line = lines[i].trim();
    const next = lines[i + 1].trim();
    const isHeader = line.startsWith("|") && line.lastIndexOf("|") > 0;
    const isSeparator = /^\|[\s\-:|]+\|$/.test(next);
    if (isHeader && isSeparator) {
      const cols = line.split("|").filter((s) => s.trim().length > 0).length;
      count++;
      if (cols > maxCols) maxCols = cols;
      // Skip past this table so we don't double-count rows
      i++;
      while (i + 1 < lines.length && lines[i + 1].trim().startsWith("|")) i++;
    }
  }
  return { count, maxCols };
}

function maybeWarnTableHeavy(md: string, slug: string): void {
  const { count, maxCols } = analyzeTables(md);
  const heavy = count >= 3 || maxCols > 4;
  if (!heavy) return;
  const reason =
    count >= 3 && maxCols > 4
      ? `${count} tables (max ${maxCols} cols)`
      : count >= 3
        ? `${count} tables`
        : `a ${maxCols}-column table`;
  console.warn(
    [
      `⚠️  Heads up: this markdown has ${reason}.`,
      `   Pandoc/xelatex tables can break across pages awkwardly and squish wide columns.`,
      `   For better tabular layout, escalate to raw LaTeX:`,
      `     sed "s|@@SKILLDIR@@|${SKILL_DIR}|g" ${SKILL_DIR}/template.tex > /tmp/facilitron-md-to-pdf/${slug}.tex`,
      `   See SKILL.md → "Two paths — default to LaTeX".`,
      ``,
    ].join("\n"),
  );
}

function stripChecklistGroups(md: string): string {
  const lines = md.split("\n");
  const out: string[] = [];
  let inGroup = false;
  for (const line of lines) {
    const trimmed = line.trim();
    if (trimmed === "::checklist-group") {
      inGroup = true;
      continue;
    }
    if (inGroup && trimmed === "::") {
      inGroup = false;
      continue;
    }
    if (inGroup) {
      // ChecklistGroup always renders checkboxes — convert "- item" to "- [ ] item"
      // so pandoc's task_lists extension renders a checkbox in the PDF.
      const m = line.match(/^(\s*)-\s+(?!\[[ xX]\])(.*)$/);
      if (m) {
        out.push(`${m[1]}- [ ] ${m[2]}`);
        continue;
      }
    }
    out.push(line);
  }
  return out.join("\n");
}

for (const file of files) {
  // Normalize CRLF → LF so the front-matter split and the ::faq/::checklist
  // parsers (which all key off "\n---\n" and trimmed lines) work on pasted
  // content with Windows line endings, not just LF repo files.
  const raw = readFileSync(file, "utf8").replace(/\r\n/g, "\n");
  const { front, body } = splitFrontMatter(raw);
  const title = (front.title as string) ?? basename(file, ".md");

  let processed = body;
  processed = expandFaqBlocks(processed);
  processed = stripChecklistGroups(processed);

  const slug = basename(file, ".md");
  maybeWarnTableHeavy(processed, slug);

  const fullMd = `![](${LOGO_PATH}){ width=160px }\n\n\\vspace{0.5em}\n\n# ${title}\n\n${processed.trim()}\n`;
  const mdPath = join(outDir, `${slug}.md`);
  const pdfPath = join(outDir, `${slug}.pdf`);
  writeFileSync(mdPath, fullMd);

  if (emitMdOnly) {
    console.log(`→ ${mdPath} (parse stage only, --emit-md)`);
    continue;
  }

  console.log(`→ ${pdfPath}`);
  // execFileSync (no shell) so a filename with shell metacharacters can't be
  // interpreted — args go straight to pandoc as an argv array.
  execFileSync(
    "pandoc",
    [
      mdPath,
      "-o", pdfPath,
      "--pdf-engine=xelatex",
      "-V", "geometry:margin=1in",
      "-V", "mainfont=Helvetica",
      "-V", "colorlinks=true",
      "-V", "linkcolor=NavyBlue",
      "-V", "urlcolor=NavyBlue",
    ],
    { stdio: "inherit" },
  );
}

console.log(`\nDone. Output: ${outDir}`);
