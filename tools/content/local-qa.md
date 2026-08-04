# Content worktree bootstrap and local QA

Use this reference before running local content checks in a fresh
`marketing-pages` worktree. It is shared by `tron:news-item`,
`tron:guide-item`, and `tron:toolkit-item`.

## Bootstrap the worktree

From the `marketing-pages` worktree root, install its declared dependencies before
starting Nuxt or running local checks:

```bash
npm install
```

Run it once for each new worktree, or again after its dependency manifest changes.
Do not borrow a dev server from another worktree: it can serve stale content and
make a change look verified when it is not.

## Interpret local checks correctly

### Vale styles missing

`tron:prose-lint` can be unavailable locally when the worktree does not contain
the Vale styles it expects. Treat a missing-style error as an environment
limitation, not proof that the content passed or failed prose review. Report the
limitation, complete the checks that can run, and run prose lint in an environment
with the repository's Vale styles before relying on its result.

### Root-relative links reported by Lychee

Lychee can report a root-relative internal link such as `/resources/guides` as a
missing local file. That is an expected false positive when Lychee has no site base
URL. It is **not** a broken-link finding by itself.

Verify every internal route with the content helper, which resolves pages the way
Nuxt does:

```bash
C="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/content/content.sh"
bash "$C" check-link /resources/guides
```

If `check-link` exits nonzero, the route is a real broken link that must be fixed.
For a Lychee run against a running local server, pass its base URL, for example
`--base-url http://localhost:<port>`.

### Newly registered index cards

Nuxt can retain its route or content index when it was already running before a
new guide or other indexed card was added. If the new card does not appear after
you save its registration entry, restart the Nuxt server, then reload the index
route. Only treat the card as missing after that restart.
