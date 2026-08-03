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
description: "Create a new, high-confidence Jira ticket by walking the shared ticket rubric for engineering, design, content, campaign-asset, or hosted-CMS work, stamping the summary PREFIX for engineering routing, and creating it via acli with machine-readable markers triage can parse. Use for 'create a ticket', 'file a Jira ticket for X', 'open a task', 'log this as a ticket', or when the user describes work that should become one. Enforces the rubric so the ticket is actionable by construction, not thin/title-only. For fixing an EXISTING thin ticket use tron:jira-source-discovery + tron:jira-ticket-enricher; to check tickets against the rubric use tron:ticket-lint."
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

- **engineering** — which repo does the work land in? Map it to a summary `PREFIX:` from
  [tools/jira/conventions.md](../../tools/jira/conventions.md) (`TRON-PLUGIN`, `SCOUT`, `PAGES`, `LLLP`,
  `MABE`, `SUPPORT`, `UI`). If the repo is not clear, ask; do not guess a prefix.
- **design / content / campaign-asset / cms** — no summary prefix; the `Deliverable type:` marker
  carries the routing.

Also settle the `Deliverable type:` (the fine-grained class) from the allowed values for that `Type` in
the rubric.

### 2. Gather the rubric fields

Walk the fields for the chosen `Type`, one at a time, in plain conversation. Collect:

- **Spine (all types):** `Done`, `Type`, `Deliverable type`, `Context`, `Decision` (due date, sign-off
  owner, constraints).
- **The type's section markers:**
  - engineering: `Repo`, `Affected paths`, `Acceptance criteria` (2+ checkable bullets).
  - design: `Figma`, `Format`, `Brand refs`, `Lands`.
  - content: `Destination`, `Format`, `SEO target`, `Draft`.
  - campaign-asset: `Campaign`, `Asset`, `Format`, `Lands`.
  - cms: `CMS`, `Edit URL`, `Verify URL`.

Reject placeholders. If the user gives a source link, fetch it (Figma/Doc/Confluence) and use its real
detail to fill `Context` and the section markers.

### 3. Assemble the ticket

**Summary:** `PREFIX: short imperative description` for engineering; a plain imperative summary for
all non-engineering types.

**Description:** the machine header (a fenced code block holding every marker) first, then the human prose.
The fenced block is required, not cosmetic: `acli` stores descriptions as ADF and md-to-adf collapses
ordinary consecutive lines into one paragraph and splits bare URLs off their `Key:`. A code block keeps
one marker per line with literal URLs, so triage parses exactly what you wrote. See the worked example in
the [rubric template](../../tools/ticket/ticket-rubric.md#the-template-body). Repeat any link you want
clickable as a normal link in the prose below the block.

Use one private workspace under `TMPDIR` and own it with an exit trap. The Markdown and ADF are
scratch files: remove them after Jira consumes the ADF, including when linting or the Jira write fails.

### 4. Self-check against the rubric, then create

Lint the assembled description **before** creating, and show the user the verdict. Iterate until it is
`high` (or the user accepts a `medium` with a genuinely unknown detail). Then convert and create.

## Fast path (scripted)

Resolve the shared tools once, then lint and create:

```bash
name=create-ticket
PLUGIN_ROOT="${TRON_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-${CLAUDE_SKILL_DIR:+$CLAUDE_SKILL_DIR/../..}}}"
RESOLVER="${PLUGIN_ROOT:+$PLUGIN_ROOT/tools/skill/resolve-plugin-root.sh}"
[ -f "${RESOLVER:-}" ] || RESOLVER="$(find ~/.claude/plugins/cache ~/.claude/plugins/marketplaces ~/.codex/plugins/cache ~/.codex/plugins/marketplaces ~/.config/opencode "$HOME/Library/Application Support/tron-os/tron-releases/versions" -maxdepth 8 -type f -path "*/tools/skill/resolve-plugin-root.sh" 2>/dev/null | LC_ALL=C sort | tail -1 || true)"
[ -f "${RESOLVER:-}" ] || { echo "tron:$name: shared resource resolver not found; install or update the complete Tron package" >&2; exit 1; }
PLUGIN_ROOT="$(bash "$RESOLVER" "$name" tools/md-to-adf/md-to-adf.mjs tools/ticket/rubric-lint.sh tools/ticket/ticket-rubric.md)"
TICKET_DIR="$PLUGIN_ROOT/tools/ticket"
ADF="$PLUGIN_ROOT/tools/md-to-adf/md-to-adf.mjs"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/tron-create-ticket.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
MD="$WORK/<slug>.md"
ADF_FILE="$WORK/<slug>.adf.json"

# 1. Self-check the drafted description (offline) against the rubric.
#    Pass --summary so a valid PREFIX satisfies engineering's Repo requirement.
bash "$TICKET_DIR/rubric-lint.sh" --file "$MD" \
  --summary "TRON-PLUGIN: <summary>" | jq '{verdict, missing}'
# → iterate on the markdown until .verdict == "high: actionable"

# 2. Convert to ADF and create the ticket.
node "$ADF" < "$MD" > "$ADF_FILE"
acli jira workitem create \
  --project MD --type Task \
  --summary "TRON-PLUGIN: <summary>" \
  --description-file "$ADF_FILE" \
  --assignee "@me"

# 3. Verify the LIVE ticket lints high (round-trips through Jira's stored ADF).
bash "$TICKET_DIR/rubric-lint.sh" --key <NEW-KEY> | jq '{verdict, missing}'
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

## Quality rules

- Markers in a fenced code block; prose (with clickable links) below. Always.
- Facilitron voice in the prose you draft: see [tools/voice/facilitron-voice.md](../../tools/voice/facilitron-voice.md).
- Never pass raw markdown to `acli --description`; always use md-to-adf + `--description-file`
  ([tools/md-to-adf/usage.md](../../tools/md-to-adf/usage.md)).
- Engineering tickets carry both the summary `PREFIX:` and the `Repo:` marker.
- Do not include section markers for a `Type` other than the ticket's.
- Verify the live ticket lints `high` after creating; if Jira's stored ADF changed anything, fix it with
  `acli jira workitem edit --key <KEY> --description-file … --yes`.

## Related skills

See [rubric consumer roles](reference/consumer-roles.md) when deciding whether to create, lint, or enrich a ticket.
