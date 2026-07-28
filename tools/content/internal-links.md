# Internal links (shared reference)

Shared by `tron:news-item`, `tron:guide-item`, and `tron:toolkit-item`. Bad internal
links are the #1 build-breaking pitfall — a path with no serving `*.vue` page 404s the
prerender. Each skill links this file directly from its SKILL.md; the workflow (when to
run the checks) stays in each skill.

Which paths are right is a fact about the consuming repo, so this file holds the
*flow*, and the repo's own content profile holds the *paths*.

## The deterministic flow

Use the shared helper — don't hand-edit URLs or grep by eye:

```bash
C="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/content/content.sh"
bash "$C" rewrite-links <file>        # absolute marketing URLs → relative, in place
bash "$C" check-link /product/<path>  # once per internal path — resolves against the repo's pages
```

`rewrite-links` converts every absolute marketing-domain URL in the file to a
site-relative path. Then `check-link` each internal path — it resolves the route the
same way Nuxt does (`foo.vue`, `foo/index.vue`, or the nearest `[...slug].vue`
catch-all, under `app/pages/` or `pages/`) and exits nonzero when nothing serves it.

## Known traps — read them from the repo

A route that exists as a *directory* but has no index page is the classic 404. The
consuming repo declares the ones it knows about, with the reason:

```bash
bash "$C" profile | jq -r '.internalLinks.exceptions[]? | "\(.wrong) → \(.right)\n    \(.reason)"'
bash "$C" profile | jq -r '.internalLinks.rewriteAbsolute'
```

Treat that list as advisory, not exhaustive: it records the traps someone has already
been bitten by. `check-link` is still the authority on whether a given path resolves,
so run it on every internal link regardless.

## When a link doesn't resolve

`check-link` failing means no page serves that route. Find the real one by searching
the repo's pages directory, which the profile declares. Read it loudly — if the repo
does not declare one, stop and say so rather than guessing `pages/` or `app/pages/`:

```bash
PAGES="$(bash "$C" profile | jq -er '.framework.pagesRoot')" \
  || { echo "profile declares no framework.pagesRoot — cannot locate this repo's pages" >&2; exit 1; }
find "$PAGES" -type f -name '*.vue' | rg -i <keyword>
```

Content routes for a given pipeline are also discoverable — `content.sh pipeline <name>`
returns the `route` and `indexRoute` that pipeline publishes at.
