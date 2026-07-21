# Source-type catalog — what metadata each source carries

Identify the source type from the links gathered in steps 1–3 and capture whatever the
implementer will need. A ticket often has more than one source (a spec plus a design, say) —
capture each.

## Design and content sources

- **Figma file** — keep the full URL with its `node-id`. Note the frame or page name from any comment. The implementer builds to this; do not try to render it.
- **Existing or HubSpot page being replaced** — keep the URL as the content/layout reference.
- **Asset location** — an ImageKit folder, a download link, or attachments named in the source ticket.
- **Google Doc** — read it through the **authenticated gws Docs API**, not a plain export or
  browser fetch (which fail for any doc that is not world-readable, which is most of them). This
  is the path CCAL-1777 missed:
  ```bash
  # documentId is the long token from the /document/d/<ID>/edit URL
  gws docs documents get --params '{"documentId":"<ID>"}'
  ```
  The response is the Docs **JSON model**, not plain text. Readable text lives under
  `body.content[]` — each structural element is a paragraph whose runs carry the text:
  ```bash
  gws docs documents get --params '{"documentId":"<ID>"}' \
    | jq -r '.body.content[]?.paragraph?.elements[]?.textRun?.content // empty'
  ```
  From the extracted text read fields near the top such as `Meta Title:`, `Meta Description:`,
  `Slug:`, the H1 title, and Purpose / Scope / Procedure / FAQ sections. A Google Doc a ticket
  links as its spec is an authoritative source — it is a hard implementation gate, so it must be
  read, not skipped (see [WORKER_CONTRACT.md](../../../WORKER_CONTRACT.md) → *An authoritative
  source is a hard implementation gate*).

## Spec and code sources

- **Confluence page** — the brief or spec often lives here. Fetch the body with the shared helper so the spec text lands in the description, not just a link:
  ```bash
  "${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/confluence/fetch-confluence.sh" <confluence-url-or-id>
  ```
  Pull the goal, scope, and any acceptance criteria already written there.
- **GitHub PR, issue, or code path** — keep the URL, or a `owner/repo` + file path / symbol reference, so the implementer knows exactly where the change or the prior art lives. A linked PR is often the pattern to copy or the thing to revert.
- **Error or monitoring link** (Sentry, logs, dashboard) — keep the issue URL and capture the error message, affected endpoint, and frequency if shown. This is the repro context for a fix.
- **Chat or recording link** (Slack thread, Loom) — keep the URL as provenance, but note it may not be accessible to the implementer; summarize any decision captured in the ticket text rather than relying on the link.

"Not directly accessible" means **every supported authenticated path for that source type has
been tried** — the gws Docs API for a Google Doc, `fetch-confluence.sh` for Confluence, `acli`
for Jira, the broker for Figma — not that a first plain fetch returned nothing. Only after that
do you record the URL as a reference. When the source is authoritative (the thing the work
implements) and no authenticated path reads it, that is a hard blocker for the implementer, not a
note to work around (see [WORKER_CONTRACT.md](../../../WORKER_CONTRACT.md)).
