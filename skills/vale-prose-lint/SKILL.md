---
name: vale-prose-lint
description: "Lint prose, marketing copy, blog posts, SOPs, and other markdown content with Vale to enforce style, terminology, and readability rules. Use this skill when the user wants to check writing quality, lint copy, run prose checks, enforce a style guide, find spelling/grammar/terminology issues, or says things like 'run vale', 'lint this content', 'check the prose', 'proofread this', 'check the writing', 'review the copy', 'check our terminology', or 'enforce the style guide'. Also trigger when the user is finalizing marketing copy, blog/cluster articles, toolkit items (SOPs, checklists, templates), or other content/*.md files and wants a quality pass before publish."
---

# Vale Prose Lint

This skill delegates the lint to the **`vale-prose-runner`** subagent (runs on Sonnet — the findings need light prose judgment). Your job is to resolve the target, tell the runner where the Facilitron style pack lives, and hand off — **don't run vale yourself.**

## What to do

1. **Resolve the target:** a file/dir the user named → else `content/` if it exists → else project root.
2. **Resolve the style-pack path.** It ships with this plugin at `$CLAUDE_SKILL_DIR/styles` (rules under `styles/Facilitron/`, vocab under `styles/config/vocabularies/Facilitron/accept.txt`). Expand `$CLAUDE_SKILL_DIR` to an absolute path so the subagent can find it.
3. **Delegate to `vale-prose-runner`** (Task tool): "Lint `<target>` with Vale using the Facilitron style pack at `<absolute styles path>` (scaffold `.vale.ini` + symlinks if missing). Return findings grouped by file with severity counts and the top offenders." If the user wants an errors-only gate (pre-commit/PR), say so in the prompt.
4. **Relay the runner's grouped findings.** If it reports vale isn't installed, surface `brew install vale`.

## Notes
- The Facilitron style pack is bundled with the plugin (`styles/Facilitron/` rules + `styles/config/vocabularies/Facilitron/accept.txt` vocab) — shared across repos. To accept a false-positive term, append it to `accept.txt` and the change ships with the next plugin release.
- The runner handles project scaffolding (symlinks, `.vale.ini`, `vale sync`) — `.vale.ini` is committed; `.vale/styles/` is gitignored.
- Good final pass before `tron:news-item` / `tron:guide-item` / `tron:case-study` / `tron:press-release` open their PR.
