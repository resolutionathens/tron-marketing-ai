# Internal links on marketing-pages (shared reference)

Shared by `tron:news-item`, `tron:guide-item`, and `tron:toolkit-item`. Bad internal
links are the #1 build-breaking pitfall — a path with no serving `pages/*.vue` 404s the
prerender. Each skill links this file directly from its SKILL.md; the workflow (when to
run the checks) stays in each skill.

## The deterministic flow

Use the shared helper — don't hand-edit URLs or grep by eye:

```bash
C="${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR/../..}/tools/content/content.sh"
bash "$C" rewrite-links <file>        # facilitron.com → relative, in place
bash "$C" check-link /product/<path>  # once per internal path — resolves against pages/
```

`rewrite-links` converts every absolute `https://www.facilitron.com/...` URL in the file
to a site-relative path. Then `check-link` each internal path — it resolves the route the
same way Nuxt does (`foo.vue`, `foo/index.vue`, or the nearest `[...slug].vue` catch-all)
and exits nonzero when nothing serves it.

## Known trap

`/product/scheduling-and-reservations/` has **no index page** — linking there is a 404.
Link to `/product/facilitron-scheduling-and-reservations` instead. Sub-paths like
`/product/scheduling-and-reservations/automated-work-orders` are fine.

## Common landing pages

| Want to link to                   | Correct path                                      | Notes                                                                                                |
| --------------------------------- | ------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| Facilitron Works product          | `/product/works`                                  | has `index.vue`                                                                                      |
| Scheduling & Reservations product | `/product/facilitron-scheduling-and-reservations` | the directory `/product/scheduling-and-reservations/` has **no index page** — linking there is a 404 |
| Building Automation Systems       | `/product/scheduling-and-reservations/bas`        | exists                                                                                               |
| Facilitron FIT                    | `/product/facilitron-fit`                         |                                                                                                      |
| Other toolkit items               | `/resources/toolkit/<slug>`                       |                                                                                                      |
| News articles                     | `/resources/news/<slug>`                          | served by the news catch-all                                                                         |

When a path isn't in the table and `check-link` fails, find the real route with
`find pages -type f -name "*.vue" | grep -i <keyword>` in the marketing-pages repo.
