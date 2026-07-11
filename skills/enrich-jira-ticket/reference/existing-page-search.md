# Existing-page search — marketing-pages content/landing-page tickets

Before drafting a landing page or content ticket as net-new, check whether a page matching the
subject already exists and is live. A ticket that reads "build the Attendee Management page"
can just as easily mean "redesign/migrate the Attendee Management page that already ships at
`pages/facility-owners/attendee-management.vue`." Scoping the wrong one costs the developer a
throwaway build.

Run this whenever the work type (step 3) lands on a marketing-pages landing page, product page,
or content item with a route in `pages/**`. Skip it for pure webdev/navigation tickets, toolkit
items, and news/blog posts — those don't carry this net-new/redesign ambiguity.

## 1. Pull search terms from the ticket

Take the ticket subject and any page name mentioned in its description or linked issues, and
derive 2-4 keyword variants: the slugified form, the plain words, and any synonym the ticket
itself uses (e.g. "Attendee Management" -> `attendee-management`, `attendee management`,
`attendee`).

## 2. Search the local checkout if one exists

`marketing-pages` is frequently checked out as a sibling worktree. Check for it before falling
back to a remote search:

```bash
MP_REPO=$(for d in ~/Documents/GitHub/marketing-pages ~/Documents/GitHub/marketing-pages.*; do
  [ -d "$d/pages" ] && echo "$d" && break
done)
```

If found, search both filenames and rendered titles/H1s, since the route slug and the page's
displayed title often diverge:

```bash
find "$MP_REPO/pages" -iname "*<keyword>*"
find "$MP_REPO/pages" -name "*.vue" -exec grep -liE "<keyword one>|<keyword two>" {} +
find "$MP_REPO/content" -name "*.md" -exec grep -liE "<keyword one>|<keyword two>" {} + 2>/dev/null
```

## 3. Fall back to a remote search when no local checkout exists

```bash
gh search code "<keyword>" --repo Facilitron/marketing-pages
```

## 4. Confirm a candidate against the live site

A filename or content match is a candidate, not confirmation. Check the page actually resolves
before citing it:

```bash
curl -s -o /dev/null -w '%{http_code}' "https://facilitron.com/<candidate-route>"
```

A `200` confirms a live page at that route. Note the live URL alongside the repo path.

## 5. Record the result in the enriched description

**Match found** — add it to `## Sources` and steer the implementation notes toward
redesign/migration instead of net-new:

```markdown
- Existing page found: `pages/facility-owners/attendee-management.vue` (live at
  https://facilitron.com/facility-owners/attendee-management) — likely the page this ticket
  redesigns or migrates, not a net-new build. Confirm scope with the reporter before starting.
```

**No match found** — say so explicitly rather than leaving the search invisible, so the next
reader knows it was checked and not skipped:

```markdown
- Existing page search: no matching page found in `marketing-pages` or on the live site — scoped as net-new.
```

Either way, this is a candidate signal, not a verdict. If a match is found, flag it for the
implementer to confirm rather than unilaterally rewriting the ticket's scope.
