---
name: brainstorm
model: opus
effort: high
description: "Collaborative one-question-at-a-time ideation for a marketing idea before you commit to producing it — a content topic, a campaign, positioning, a name, a new landing page. Use for '/brainstorm', 'I have an idea', 'help me think through', 'workshop this idea', or a vague hypothesis with no plan yet. Asks one question at a time to surface assumptions, then writes a structured Ideation Note. Does NOT produce the content — it produces the thinking."
allowed-tools:
  - Bash
  - AskUserQuestion
  - Read
  - Write
  - Skill
scout:
  surface: true
  title: "Brainstorm an idea"
  blurb: "A guided back-and-forth that pressure-tests a fuzzy idea one question at a time, then writes it up as a structured ideation note."
  when: "You have a topic, campaign, or name in your head but no plan yet."
  category: drafting
  effects: [draft]
  inputs:
    - key: topic
      label: "Topic"
      type: textarea
      required: true
      help: "The subject to brainstorm angles / ideas for."
---

# /brainstorm — Ideation Workshop

## Durable delivery gate

Resolve the durable destination before drafting the Ideation Note. Follow
[the durable deliverable contract](../../tools/content/durable-deliverables.md): select Drive or Confluence, capture review/owner/handoff metadata, work in a uniquely created scratch directory, publish through the matching publisher skill, return the complete success block, and clean scratch on success and failure. This skill never writes repository content or performs Git operations.

For the fuzzy front end — when you have a hunch but haven't pinned down audience, angle, or viability. Output is an Ideation Note a content skill (`tron:news-item`, `tron:guide-item`, `tron:toolkit-item`) turns into a real page.

**When NOT to use:** already-scoped idea → go straight to the content skill. Have a draft to stress-test → use `/grill`. Want search data → `/tron-report`.

## Methodology — One Question at a Time

Never dump a list of questions. Ask one, integrate, then ask the next.

```
- [ ] Stage 1 — Frame the problem (not the solution)
- [ ] Stage 2 — Identify a specific audience
- [ ] Stage 3 — Pressure-test the interest (real vs. imagined demand)
- [ ] Stage 4 — Imagine the outcome (do-nothing vs. lands-perfectly delta)
- [ ] Stage 5 — Risk & constraint check
- [ ] Stage 6 — Inputs & adjacency (discovery work, new page vs. update)
- [ ] Save the Ideation Note
```

| Stage | Question to ask |
|-------|----------------|
| **1 — Frame** | "What's the problem or pattern you're noticing? What made you bring this up?" |
| **2 — Audience** | "Who is this for? Be specific — not 'customers' but 'a K-12 facilities director at a 20-school district.'" |
| **3 — Interest** | "What does this audience do today instead? Are they actively searching, asking us, or is this something we think they should care about?" |
| **4 — Outcome** | "If we do nothing, what happens? If this lands perfectly, what changes — for the reader and for us?" |
| **5 — Risk** | "What could make this a bad idea or a weak piece? Thin angle, wrong funnel stage, claims we can't back, something a competitor already owns?" |
| **6 — Inputs** | "What should we look at before producing this? Search Console, GA, competitor content, sales/support questions, an existing page we should update instead of creating a new one?" |

## Anti-patterns

- ❌ Dump all 6 questions in one message
- ❌ Jump to an outline before Stage 4
- ❌ Suggest angles not grounded in the Stage 2 audience
- ❌ Skip Stage 5 on an exciting idea — that's where ideas break
- ❌ Produce the content here — that's the content skill's job

## Output: Ideation Note

Save via the fast path script (handles slug, date, front matter):

```bash
name=brainstorm
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${CLAUDE_SKILL_DIR:+$CLAUDE_SKILL_DIR/../..}}"
RESOLVER="${PLUGIN_ROOT:+$PLUGIN_ROOT/tools/skill/resolve-skill-dir.sh}"
[ -f "${RESOLVER:-}" ] || RESOLVER="$(find ~/.claude/plugins/cache ~/.claude/plugins/marketplaces ~/.codex/plugins/cache ~/.codex/plugins/marketplaces "$HOME/Library/Application Support/tron-os/tron-releases/versions" -maxdepth 7 -type f -path "*/tools/skill/resolve-skill-dir.sh" 2>/dev/null | sort -V | tail -1 || true)"
[ -f "${RESOLVER:-}" ] || { echo "tron:$name: resolver not found; searched Claude/Codex cache and marketplace roots plus the tron release store" >&2; exit 1; }
SKILL_DIR="$(bash "$RESOLVER" "$name" scripts/brainstorm.sh)"
bash "$SKILL_DIR/scripts/brainstorm.sh" save "<idea name>" [--audience S] [--format F] --out "$WORK/ideation-<slug>.md"
```

Then edit the file to fill in all 6 stage answers. Use the template in `reference/ideation-note-template.md`. Facilitron voice in the note's copy: see [tools/voice/facilitron-voice.md](../../tools/voice/facilitron-voice.md).

The note ends with a next-step routing — route per the template's Next Step list.
