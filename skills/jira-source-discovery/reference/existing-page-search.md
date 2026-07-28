# Existing-page search — page and content tickets

Before drafting a landing page or content ticket as net-new, check whether a page matching the
subject already exists and is live. A ticket that reads "build the Attendee Management page"
can just as easily mean "redesign/migrate the Attendee Management page that already ships at
`app/pages/facility-owners/attendee-management.vue`." Scoping the wrong one costs the developer
a throwaway build.

Run this whenever the work type (step 3) lands on a landing page, product page, or content item
served from the target repo's pages tree. Skip it for pure webdev/navigation tickets, toolkit
items, and news/blog posts — those don't carry this net-new/redesign ambiguity.

The target repo comes from the ticket's `Repo:` field or its summary PREFIX
([tools/jira/conventions.md](../../../tools/jira/conventions.md) is canonical). Everything below
is written against that repo, resolved from what it declares — never a path assumed for one repo.

## 1. Pull search terms from the ticket

Take the ticket subject and any page name mentioned in its description or linked issues, and
derive 2-4 keyword variants: the slugified form, the plain words, and any synonym the ticket
itself uses (e.g. "Attendee Management" -> `attendee-management`, `attendee management`,
`attendee`).

## 2. Resolve the local checkout and its source roots

The target repo is frequently checked out as a sibling worktree. Find one, then ask **it** where
its pages and content live — do not probe for a conventional directory:

```bash
C="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/content/content.sh"
REPO_NAME=<repo-from-the-ticket>          # e.g. marketing-pages
ROOTS=""
for d in ~/Documents/GitHub/"$REPO_NAME" ~/Documents/GitHub/"$REPO_NAME".*; do
  [ -d "$d/.git" ] || continue
  ROOTS="$(bash "$C" paths --repo "$d" 2>/dev/null)" && break
  ROOTS=""
done
[ -n "$ROOTS" ] && echo "$ROOTS" | jq -r '.root, .pagesRootAbs, .contentRootAbs'
```

`content.sh paths` reads the repo's own `.tron/content-profile.json`. Two outcomes, both useful:

- **It answers** — use `pagesRootAbs` / `contentRootAbs` for step 3.
- **It fails** — that checkout declares no profile (or no `framework` block), so its layout is
  unknown. Skip to the remote search in step 4 and say so in the write-up. Do **not** fall back to
  `$d/pages`: marketing-pages moved to a Nuxt 4 `app/` srcDir and left an empty root `pages/`
  behind, so a directory probe still succeeds, the search finds nothing, and the ticket gets
  scoped as net-new on the strength of a search that never looked anywhere real.

## 3. Search the resolved roots

Search both filenames and rendered titles/H1s, since the route slug and the page's displayed
title often diverge:

```bash
PAGES="$(jq -r '.pagesRootAbs // empty' <<<"$ROOTS")"
CONTENT="$(jq -r '.contentRootAbs // empty' <<<"$ROOTS")"
[ -n "$PAGES" ] && find "$PAGES" -iname "*<keyword>*"
[ -n "$PAGES" ] && rg -li "<keyword one>|<keyword two>" "$PAGES" --glob '*.vue'
[ -n "$CONTENT" ] && rg -li "<keyword one>|<keyword two>" "$CONTENT" --glob '*.md'
```

Report matches as repo-relative paths (strip `.root`) so they stay meaningful to a reader who has
the repo checked out somewhere else.

## 4. Fall back to a remote search when no local checkout resolves

```bash
gh search code "<keyword>" --repo Facilitron/"$REPO_NAME"
```

## 5. Confirm a candidate against the live site

A filename or content match is a candidate, not confirmation. Check the page actually resolves
before citing it:

```bash
curl -s -o /dev/null -w '%{http_code}' "https://facilitron.com/<candidate-route>"
```

A `200` confirms a live page at that route. Note the live URL alongside the repo path.

## 6. Record the result in the enriched description

**Match found** — add it to `## Sources` and steer the implementation notes toward
redesign/migration instead of net-new:

```markdown
- Existing page found: `app/pages/facility-owners/attendee-management.vue` (live at
  https://facilitron.com/facility-owners/attendee-management) — likely the page this ticket
  redesigns or migrates, not a net-new build. Confirm scope with the reporter before starting.
```

**No match found** — say so explicitly rather than leaving the search invisible, so the next
reader knows it was checked and not skipped. Name where you actually looked, so a reader can tell
a real miss from a search that had nowhere to run:

```markdown
- Existing page search: no match in `marketing-pages` (`app/pages`, `content`) or on the live
  site — scoped as net-new.
```

If no local checkout resolved and the remote search was the only pass, say that instead:

```markdown
- Existing page search: no local `marketing-pages` checkout declares a content profile, so this
  was a remote `gh search code` pass only — a local match may exist. Confirm scope with the
  reporter before starting.
```

Either way, this is a candidate signal, not a verdict. If a match is found, flag it for the
implementer to confirm rather than unilaterally rewriting the ticket's scope.
