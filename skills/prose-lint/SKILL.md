---
name: prose-lint
model: haiku
effort: low
description: "Lint prose, marketing copy, blog posts, SOPs, and other markdown content with Vale to enforce style, terminology, and readability rules, then judge published copy against the Facilitron brand voice. Use for 'run vale', 'lint this content', 'check the prose', 'proofread this', 'does this sound like us', or 'enforce the style guide'. Also trigger when the user is finalizing marketing copy, blog/cluster articles, toolkit items, or other content/*.md files and wants a quality pass before publish."
allowed-tools:
  - Task
  - Bash
scout:
  surface: true
  title: "Check writing style"
  blurb: "Runs copy against the Facilitron style guide — terminology, readability, consistency — then checks whether it sounds like Facilitron, and lists what to fix."
  when: "Copy is nearly final and needs a style and voice pass."
  category: qa
  effects: [report]
  inputs:
    - key: target
      label: "Draft path"
      type: path
      required: true
      placeholder: "Pick the markdown / draft to lint"
      accept: ".md,.markdown,.txt"
---

# /prose-lint — Prose / style + voice lint

Two passes over the same draft, both delegated. The **mechanical pass** goes to the **`vale-prose-runner`** subagent (Sonnet — the findings need light prose judgment). The **voice pass** goes to the **`facilitron-voice-judge`** subagent (Opus — this is the judgment quality dominates cost), because Vale can tell you the mechanics are clean but not that the copy sounds like Facilitron. You stay a thin orchestrator on Haiku: resolve the target and the two paths, hand off, relay. **Don't run vale and don't judge the voice yourself.**

The two layers are deliberately split. Every regex-catchable rule lives in the Vale pack and nowhere else; the judgment lives in [tools/voice/facilitron-voice.md](../../tools/voice/facilitron-voice.md) and [tools/voice/marketing-copy.md](../../tools/voice/marketing-copy.md). When the two disagreed, only the prose half knew (MD-2574) — so never restate a banned word in prose guidance, and never encode judgment as a Vale token.

## What to do

1. **Resolve the target:** a file/dir the user named → else `content/` if it exists → else project root.
2. **Resolve the style-pack path.** It ships with this plugin under the skill's `styles/` dir (rules under `styles/Facilitron/`, vocab under `styles/config/vocabularies/Facilitron/accept.txt`). Resolve the skill dir robustly — `$CLAUDE_SKILL_DIR` is not always exported into Bash — and pass the **absolute** `styles/` path to the runner:
   ```bash
   name=prose-lint
   PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${CLAUDE_SKILL_DIR:+$CLAUDE_SKILL_DIR/../..}}"
   RESOLVER="${PLUGIN_ROOT:+$PLUGIN_ROOT/tools/skill/resolve-skill-dir.sh}"
   [ -f "${RESOLVER:-}" ] || RESOLVER="$(find ~/.claude/plugins/cache ~/.claude/plugins/marketplaces ~/.codex/plugins/cache ~/.codex/plugins/marketplaces "$HOME/Library/Application Support/tron-os/tron-releases/versions" -maxdepth 7 -type f -path "*/tools/skill/resolve-skill-dir.sh" 2>/dev/null | sort -V | tail -1 || true)"
   [ -f "${RESOLVER:-}" ] || { echo "tron:$name: resolver not found; searched Claude/Codex cache and marketplace roots plus the tron release store" >&2; exit 1; }
   SKILL_DIR="$(bash "$RESOLVER" "$name" vale-ini.template styles)"
   echo "$SKILL_DIR/styles"   # → the absolute style-pack path to hand the runner
   ```
3. **Delegate to `vale-prose-runner`** (Task tool): "Lint `<target>` with Vale using the Facilitron style pack at `<absolute styles path>` (scaffold `.vale.ini` + symlinks if missing). Return findings grouped by file with severity counts and the top offenders." If the user wants an errors-only gate (pre-commit/PR), say so in the prompt.
4. **Relay the runner's grouped findings.** If it reports vale isn't installed, surface `brew install vale`.

5. **Delegate the voice pass to `facilitron-voice-judge`** (Task tool) for published marketing copy:
   anything under `content/`, or a draft the user describes as an article, toolkit item, guide, case
   study, press release, email, social post, onesheet, or video script. Skip it for internal prose
   (tickets, comments, reports) — those follow `facilitron-voice.md` only, and a Jira comment should
   not sound like a press release.

   The voice guidance sits next to the style pack, so the same resolver gives you its path:
   `"$SKILL_DIR/../../tools/voice"`. Prompt: "Judge `<target>` against the Facilitron brand voice
   using the guidance at `<absolute tools/voice path>`. The mechanical Vale pass already ran, so skip
   banned words, dashes, and terminology. Return findings grouped by stance, register, claims, and
   red flags, most severe first, each with the quoted line and the fix."

6. **Report both passes together**, mechanical findings first (they are objective), then voice
   findings with a one-line reason each and the fix. Say plainly when the voice pass found nothing;
   a clean Vale run plus silence reads as "not checked."

## Notes

- The Facilitron style pack is bundled with the plugin (`styles/Facilitron/` rules + `styles/config/vocabularies/Facilitron/accept.txt` vocab) — shared across repos. To accept a false-positive term, append it to `accept.txt` and the change ships with the next plugin release.
- The runner handles project scaffolding (symlinks, `.vale.ini`, `vale sync`) — `.vale.ini` is copied verbatim from the bundled `vale-ini.template` (next to `styles/`) and committed; `.vale/styles/` is gitignored.
- Good final pass before `tron:news-item` / `tron:guide-item` / `tron:case-study` / `tron:press-release` open their PR.
