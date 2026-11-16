---
name: create-ticket
model: sonnet
effort: medium
fallback:
  cost: low
  skip_when: "Use tron:create-ticket only for new tickets. Use tron:jira-source-discovery + tron:jira-ticket-enricher for existing tickets."
  stage_skips:
    - stage: "Step 4 — Self-check against the rubric"
      skip_when: "User confirms the draft is complete and accurate"
description: "Create a new, high-confidence Jira ticket: product, engineering, bug, data and spike tickets in the Ticketing pilot template (metadata header with Stakeholder, Engineer, Intent and Done, then numbered sections; an engineering ticket gets a people description plus a <KEY>-engineering.md brief attachment), and design, content, campaign-asset or hosted-CMS tickets with the shared rubric's markers. Asks for the Stakeholder and never fills it in, stamps the summary PREFIX for engineering routing, lints the draft for its stage and creates it via acli. Use for 'create a ticket', 'file a Jira ticket for X', 'open a task', 'write a product ticket', 'log this as a ticket', or when the user describes work that should become one. Enforces the template so the ticket is actionable by construction, not thin/title-only. For fixing an EXISTING thin ticket use tron:jira-source-discovery + tron:jira-ticket-enricher; to check tickets against the rubric use tron:ticket-lint."
allowed-tools:
  - Bash
  - Read
scout:
  surface: true
  title: "Create an actionable ticket"
  blurb: "Turns a work request into a complete Jira ticket with clear ownership and acceptance criteria."
  when: "New work needs a Jira ticket that someone can start without filling in the gaps."
  category: tickets
  effects: [jira]
  inputs:
    - key: request
      label: "Work request"
      type: textarea
      required: true
      placeholder: "Describe the work and include any brief or source links"
---

# Create Ticket

File a new Jira ticket that is **actionable by construction**. The plugin's problem was thin,
title-only tickets: triage can tell they are blocked but not what the work is. This skill fixes that
upstream by enforcing the shared [ticket rubric](../../tools/ticket/ticket-rubric.md) at creation, so
the ticket carries exactly the signals triage keys on (deliverable, work type, context link,
decision/owner) and scores **high** the moment it exists.

Read the rubric first: [tools/ticket/ticket-rubric.md](../../tools/ticket/ticket-rubric.md). It is the
single source of truth for the spine, the per-work-type sections, the machine-readable markers, and the
verdict ladder. This skill is the authoring front end; `tron:ticket-lint` is the checker; Scout triage
is the third consumer. All three read that one file.

**Product, engineering, bug, data and spike tickets use the pilot template**
([tools/ticket/pilot-template.md](../../tools/ticket/pilot-template.md), rubric-version 5, Ian's decision of
Nov 16 2026). Read it before drafting one: it holds the header fields and the stage each is required from,
the seven sections, which sections each type needs, and the rules. Design, content, campaign-asset and cms
tickets keep the rubric's marker shape.

The skill's complete shared-resource closure is declared in the plugin manifest's versioned
[`resourceContract`](../../tools/skill/plugin-resources.md). Installers must preserve that tree or set
`TRON_PLUGIN_ROOT`; the workflow must stop if it cannot resolve the converter or rubric tooling.

This is a **Jira-write** skill. It creates a ticket only after you have gathered the required fields and
(by default) shown the user the assembled ticket. It does not branch, commit, transition, or implement —
use `tron:start-ticket` to begin the work once the ticket exists.

## The one rule: no thin tickets

Never invent field values to get to a green verdict. The rubric's whole point is that the required fields
are real: a `Context:` link that resolves, a `Done:` line naming a concrete deliverable, acceptance
criteria that are checkable. If the user cannot supply a required field, ask for it. Per the house rule,
**fetch the source the user names** (a Figma frame, a Google Doc, a Confluence page) before drafting so the
context line is real, not a guess. A ticket that lints `medium` because a genuine detail is still unknown
is fine and honest; a ticket padded with `<placeholder>` values is not.

## Workflow

### 1. Pick the work type and target

Determine the canonical `Type` from the shared rubric. Do not keep a separate type list here. Then:

- **product / engineering / bug / data / spike** — the pilot template. `product` is written by product
  and says what and why, never how. The others are engineering's. For engineering work, which repo does it
  land in? Map it to a summary `PREFIX:` from [tools/jira/conventions.md](../../tools/jira/conventions.md)
  (`TRON-PLUGIN`, `SCOUT`, `PAGES`, `LLLP`, `MABE`, `SUPPORT`, `UI`). If the repo is not clear, ask; do not
  guess a prefix.
- **design / content / campaign-asset / cms** — no summary prefix; the `Deliverable type:` marker
  carries the routing.

Also settle the `Deliverable type:` (the fine-grained class): from the rubric's allowed values for a
marker type, or the pilot template's (`pr`, `research`, `report`…) for a pilot type.

### 2. Gather the fields

Walk the fields for the chosen `Type`, one at a time, in plain conversation.

**Stakeholder: always ask, never fill it in yourself.** For every pilot ticket, ask the user who decides
and signs off (one or more people, comma-separated) and write exactly what they answer. Do not take it from
the source, the reporter, the assignee, the epic or yourself, even when one of them looks obvious; if a
source names someone, offer that name in the question and still wait for the answer. If the user doesn't
know, the ticket has no Stakeholder yet and lints `low`; say so rather than filling the line. When
dispatched (no `AskUserQuestion`), ask in one plain message and stop until it is answered.

For a **pilot type**, collect ([pilot-template.md](../../tools/ticket/pilot-template.md) has each field's
meaning and the stage it is required from):

- **Header:** `Done`, `Intent` (the reason, not the same as Done; never invented), `Type`,
  `Deliverable type`, `Stakeholder` (asked, as above), `Engineer` (asked; "not yet assigned" is fine until
  Ready to Develop), `Context` (the source link), `Decision` (who decided what and when, who signs off).
- **Acceptance criteria:** two or more, numbered `- AC1 …`, `- AC2 …` in the header and repeated as
  `**AC1** …` in section 5 with the same numbers. Each names one thing a person or a browser test can check
  pass or fail; a question or "it works" holds the ticket at `medium` (SR-6176). A spike has a deliverable
  instead.
- **Repo and Affected paths:** only on engineering's tickets, and only once the engineer knows them. Never
  on a product ticket before kickoff (the lint reports it as a problem).
- **Sections:** `## 1. Problem` always; then the sections the type needs (product and engineering 1 to 6,
  bug 1, 3, 4, 5, data 1, 2, 5, spike 1, 2, 6). An unknown becomes a section 6 row with an owner, `Open`
  until decided.

For a **marker type**, collect:

- **Spine (all types):** `Done`, `Type`, `Deliverable type`, `Context`, `Decision` (due date, sign-off
  owner, constraints), plus optional `Intent` (one sentence describing the desired user or system outcome,
  not the selected implementation). Add `Intent` only when the source evidence establishes it; never invent
  one to complete a ticket.
- **The type's section markers:**
  - design: `Figma`, `Format`, `Brand refs`, `Lands`.
  - content: `Destination`, `Format`, `SEO target`, `Draft`.
  - campaign-asset: `Campaign`, `Asset`, `Format`, `Lands`.
  - cms: `CMS`, `Edit URL`, `Verify URL`.

Reject placeholders. If the user gives a source link, fetch it (Figma/Doc/Confluence) and use its real
detail to fill `Context` and the section markers.

### 3. Assemble the ticket

**Summary:** `PREFIX: short imperative description` for engineering's pilot tickets; a plain imperative
summary for product tickets and the marker types.

**A pilot ticket** ([pilot-template.md](../../tools/ticket/pilot-template.md), "Where it lives"):

- `Type: engineering` is written as **two parts**. The brief, `<slug>-brief.md`, is the whole template:
  the fenced metadata header, the PR panel line and sections 1 to 7. The description, `<slug>.md`, is for
  people: `**Done:**`, `**Intent:**`, `**Stakeholder:**`, then `### Problem`, `### Scope` and
  `### Acceptance criteria` (the same AC numbers in plain language), ending with the line "The
  engineering brief (affected paths, decisions, test data, change log) is the attached engineering file."
  Nothing about how goes in the description. The brief is attached as `<KEY>-engineering.md` once the
  ticket exists.
- `product`, `bug`, `data` and `spike` are written as **one part**: the whole template is the description,
  with no attachment until kickoff.

**A marker ticket — description:** the machine header (a fenced code block holding every marker) first, then the human prose.
The fenced block is required, not cosmetic: `acli` stores descriptions as ADF and md-to-adf collapses
ordinary consecutive lines into one paragraph and splits bare URLs off their `Key:`. A code block keeps
one marker per line with literal URLs, so triage parses exactly what you wrote. See the worked example in
the [rubric template](../../tools/ticket/ticket-rubric.md#the-template-body). Repeat any link you want
clickable as a normal link in the prose below the block.

Use one private workspace under `TMPDIR` and own it with an exit trap. The Markdown and ADF are
scratch files: remove them after Jira consumes the ADF, including when linting or the Jira write fails.

### 4. Self-check against the rubric, then create

Lint the assembled description (for an engineering pilot ticket, the brief) **before** creating, and show
the user the verdict. A new ticket starts in Backlog, so a pilot ticket is graded at `--stage created`.
Iterate until it is `high` (or the user accepts a `medium` with a genuinely unknown detail; a ticket without
a Stakeholder stays `low` until the user names one). Report missing pilot fields by the names the lint
gives (`Stakeholder`, `Engineer`, `section 3. Pages & Roles`). Then convert and create.

## Fast path (scripted)

Resolve the shared tools once, then lint and create:

```bash
name=create-ticket
PLUGIN_ROOT="${TRON_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CLAUDE_SKILL_DIR:+$CLAUDE_SKILL_DIR/../..}}}"
if [ -z "$PLUGIN_ROOT" ] && [ -f "$HOME/.config/opencode/skills/$name/SKILL.md" ]; then
  PLUGIN_ROOT="$HOME/.config/opencode"
fi
if [ -z "$PLUGIN_ROOT" ] && [ -f "$HOME/.pi/agent/skills/$name/SKILL.md" ]; then
  PLUGIN_ROOT="$HOME/.pi/agent"
fi
if [ -z "$PLUGIN_ROOT" ]; then
  ROOTS="$(find "$HOME/.claude/plugins/cache" "$HOME/.claude/plugins/marketplaces" "${CODEX_HOME:-$HOME/.codex}/plugins/cache" "${CODEX_HOME:-$HOME/.codex}/plugins/marketplaces" "$HOME/Library/Application Support/tron-os/tron-releases/versions" -type f -path "*/skills/$name/SKILL.md" 2>/dev/null | while IFS= read -r skill_doc; do printf '%s\n' "${skill_doc%/skills/$name/SKILL.md}"; done | LC_ALL=C sort -u)"
  ROOT_COUNT="$(printf '%s\n' "$ROOTS" | sed '/^$/d' | wc -l | tr -d ' ')"
  [ "$ROOT_COUNT" = 1 ] || { echo "tron:$name: found ${ROOT_COUNT:-0} installed package roots; install one complete Tron package or set TRON_PLUGIN_ROOT (multiple installed Tron packages are ambiguous)" >&2; exit 1; }
  PLUGIN_ROOT="$ROOTS"
fi
RESOLVER="${PLUGIN_ROOT:+$PLUGIN_ROOT/tools/skill/resolve-plugin-root.sh}"
[ -f "${RESOLVER:-}" ] || { echo "tron:$name: its package root is unavailable or incomplete; install/update that complete Tron package or set TRON_PLUGIN_ROOT to it" >&2; exit 1; }
PLUGIN_ROOT="$(bash "$RESOLVER" "$name" tools/md-to-adf/md-to-adf.mjs tools/ticket/rubric-lint.sh tools/ticket/ticket-rubric.md)"
TICKET_DIR="$PLUGIN_ROOT/tools/ticket"
ADF="$PLUGIN_ROOT/tools/md-to-adf/md-to-adf.mjs"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/tron-create-ticket.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
MD="$WORK/<slug>.md"
ADF_FILE="$WORK/<slug>.adf.json"

BRIEF="$WORK/<slug>-brief.md"   # engineering pilot tickets only

# 1. Self-check the draft (offline). Lint the brief for an engineering pilot ticket,
#    the description otherwise. Pass --summary so a valid PREFIX satisfies Repo.
bash "$TICKET_DIR/rubric-lint.sh" --file "$BRIEF" --stage created \
  --summary "TRON-PLUGIN: <summary>" | jq '{verdict, missing, issues}'
# → iterate until .verdict == "high: actionable"

# 2. Convert to ADF and create the ticket.
node "$ADF" < "$MD" > "$ADF_FILE"
acli jira workitem create \
  --project MD --type Task \
  --summary "TRON-PLUGIN: <summary>" \
  --description-file "$ADF_FILE" \
  --assignee "@me"

# 3. Engineering pilot ticket: attach the brief as <NEW-KEY>-engineering.md
#    (needs ATLASSIAN_EMAIL and JIRA_API_TOKEN; acli can't upload attachments).
bash "$TICKET_DIR/brief-attachment.sh" upload <NEW-KEY> "$BRIEF"

# 4. Verify the LIVE ticket lints high: --key reads the brief attachment when there
#    is one, else the description (round-tripped through Jira's stored ADF), at the
#    stage its Jira status maps to.
bash "$TICKET_DIR/rubric-lint.sh" --key <NEW-KEY> | jq '{verdict, stage, source, missing}'
```

The `--project` and `--type` follow the target board (default `MD`, `Task`). The `--assignee` flag
defaults to `"@me"` (current user); pass `"user@example.com"` or another value to assign to someone
else. Report the new key and its verdict to the user.

### Verifying the fix

To verify a ticket was created with an assignee, run:

```bash
acli jira workitem view <NEW-KEY> --fields assignee
```

The output should include a non-empty `Assignee:` line. If no assignee appears, the acli invocation
was missing the `--assignee` flag.

### Linking the new ticket

To link the new ticket to another (it blocks, is blocked by, or relates to one), use the shared
helper with the `PLUGIN_ROOT` resolved above, never raw `acli jira workitem link create`: acli's
success message prints the reverse of the direction it stores.

```bash
L="$PLUGIN_ROOT/tools/jira/jira-link.sh"
[ -f "$L" ] || { echo "tron:create-ticket: tools/jira/jira-link.sh missing; update the Tron package" >&2; exit 1; }
bash "$L" create "<NEW-KEY> is blocked by MD-1234"   # exits 3 if Jira stored the reverse
```

Usage, `show`, and delete/replace by link id: [tools/jira/conventions.md](../../tools/jira/conventions.md#dependency-links-blocks-relates).

## Quality rules

- Markers in a fenced code block; prose (with clickable links) below. Always.
- Stakeholder is the user's answer, word for word, or nothing. Never inferred.
- An engineering pilot ticket is never left without its brief: if the upload fails, retry it, and if it
  still fails, say so and keep the brief file (copy it out of `$WORK` before the trap removes it) so it can
  be attached by hand.
- Facilitron voice in the prose you draft: see [tools/voice/facilitron-voice.md](../../tools/voice/facilitron-voice.md).
- Never pass raw markdown to `acli --description`; always use md-to-adf + `--description-file`
  ([tools/md-to-adf/usage.md](../../tools/md-to-adf/usage.md)).
- Engineering tickets carry the summary `PREFIX:`, and the `Repo:` marker once the repo is known (a pilot
  ticket requires it from kickoff).
- Do not include section markers for a `Type` other than the ticket's.
- Verify the live ticket lints `high` after creating; if Jira's stored ADF changed anything, fix it with
  `acli jira workitem edit --key <KEY> --description-file … --yes`.

## Related skills

See [rubric consumer roles](reference/consumer-roles.md) when deciding whether to create, lint, or enrich a ticket.
