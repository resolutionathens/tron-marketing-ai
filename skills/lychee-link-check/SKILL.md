---
name: lychee-link-check
description: "Check for broken or dead links in markdown content, HTML pages, sitemaps, or any URL using lychee. Use this skill when the user wants to validate links, find broken/dead URLs, audit a site for 404s, verify internal/external links, or says things like 'check for broken links', 'find dead links', 'lychee', 'link check', 'verify these links work', 'audit the links on the site', 'are any links broken in this content', or 'lint the URLs'. Especially relevant before publishing toolkit items, blog posts, redirects changes, or any content/*.md update where links could rot."
allowed-tools:
  - Task
  - Bash
---

# /lychee-link-check — Broken-link check

This skill delegates the actual link-check to the **`lychee-link-runner`** subagent, which runs on **Haiku** to keep cost low. Your job (the main agent) is only to resolve the target and hand off — **do not run lychee yourself.**

## What to do

1. **Resolve the target** from the user's request:
   - A specific markdown file, or a directory glob (prefer scanning source over crawling the live site — faster, catches broken internal links before they ship).
   - A live URL or sitemap.
   - "Changed markdown in the branch" → resolve with `git diff --name-only <base>...HEAD -- '*.md'` and pass the resulting file list.
   - Convert any file targets to **absolute paths** (the subagent has its own working directory).

2. **Delegate to the `lychee-link-runner` subagent** (via the Task tool) with a prompt like:
   > "Run a lychee link check on `<absolute target>`. `<any extra options the user asked for>`. Return the triaged summary."

3. **Relay the subagent's report** to the user (tidy formatting only if needed). If it reports lychee isn't installed, tell the user to `brew install lychee`.

## Notes

- The runner already applies sensible defaults (`--cache`, `--accept 200,206,429`, `--exclude-mail`). Only pass extra flags (`--include-fragments`, `--require-https`, `--exclude '<regex>'`, `--format json`) through the prompt if the user asks.
- For projects that run lychee regularly, suggest a `lychee.toml` at the repo root with standard exclusions/accept-codes so future runs need no flags.
- **Cost:** the heavy run-and-parse happens on Haiku in an isolated context; the main session only sees the final report.
- Good pre-publish step alongside **`tron:news-item`** / **`tron:guide-item`** / **`tron:toolkit-item`** (run it before opening the PR).
