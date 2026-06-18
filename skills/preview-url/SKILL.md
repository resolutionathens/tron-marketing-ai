---
name: preview-url
description: "Given a branch (default: current) and a repo (default: cwd), find the staging/preview URL where the latest commit is deployed. Detects the deploy target from repo signals (`.circleci/config.yml`, `wrangler.{toml,jsonc}`, `vercel.json`, `netlify.toml`, `fly.toml`, GH Actions workflows) and routes to the right lookup recipe. Use this skill whenever the user asks 'where's my staging link', 'what's the preview URL for this PR', 'where did this deploy', 'has staging updated yet', 'can you grab the deploy URL', or anything that implies 'I want to look at the deployed version of this branch in a browser'. Use as the FINAL step in the canonical task lifecycle right before /agent-browser to walk the deployed feature."
allowed-tools:
  - Bash
  - Read
---

# Preview URL Finder

Find the staging/preview URL for a deployed branch. This skill is **routing logic**, not novel API integration — it detects the deploy target and delegates to the appropriate underlying skill (`/gh`, `/circleci`, `/cloudflare-cli`).

## Fast path (deterministic)

The detection + the registered-deployment lookup are mechanical — run the bundled
script first:

```bash
bash $CLAUDE_SKILL_DIR/scripts/preview-url.sh [--repo <path>] [--branch <branch>]
```

It detects the deploy target from filesystem signals (same precedence as the table
below), and for targets that register GitHub deployments (Vercel / Netlify / CF Pages /
GitHub Pages) resolves the branch's preview URL via `gh`. One JSON line on stdout:

```json
{"ok":true,"target":"cf-pages","branch":"x","url":"https://…pages.dev","confidence":"high","reason":"…"}
{"ok":true,"target":"cf-workers","branch":"x","url":null,"confidence":"n/a","reason":"workers has no per-PR preview URL …"}
{"ok":false,"target":"unknown","branch":"x","url":null,"confidence":"none","reason":"no deploy signal — ask the user"}
```

Read the result, then act:
- **`url` present** → hand it to the user (lead with the URL); offer `/agent-browser`.
- **`target":"cf-workers"`** → there is no per-PR preview; say so up front (dev server or merge-to-prod).
- **`target":"circleci"`** → look the branch up in the **marketing-pages branch→URL table** under "Recipes by target › CircleCI" below. That table is the first-class answer — consult it **before** hitting the CircleCI API or grepping a job log. (The script intentionally doesn't hardcode Facilitron bucket URLs, but the skill prose does; `/circleci` carries the same table plus deploy-target/bucket detail.)
- **`url":null` on a gh-deployment target** → CI is likely mid-build, or `gh` wasn't authed/in the right checkout; fall back to the recipes below.
- **`target":"unknown"`** → ask the user where it deploys.

Smoke the detection with `bash $CLAUDE_SKILL_DIR/scripts/test-preview-url.sh`. Everything
below is the reference for the URL recipes and the cases the script routes onward.

## The detection flow

Walk this top-down. First match wins. The signals are usually unambiguous; if more than one matches, prefer the higher in the list (most projects only have one real deploy target).

```bash
# Get the repo path (default to cwd if not specified)
REPO="${REPO:-$(pwd)}"
BRANCH="${BRANCH:-$(git -C "$REPO" rev-parse --abbrev-ref HEAD)}"
```

| Signal in `$REPO`                                                                                          | Deploy target              | URL source of truth                                                          |
|-----------------------------------------------------------------------------------------------------------|----------------------------|------------------------------------------------------------------------------|
| `vercel.json` OR Vercel GH App configured                                                                  | **Vercel**                 | `gh api repos/:owner/:repo/deployments?ref=$BRANCH&environment=Preview`       |
| `netlify.toml`                                                                                             | **Netlify**                | Same `gh api` deployments query                                              |
| `fly.toml`                                                                                                 | **Fly.io**                 | `flyctl status -a <app-name>` or `https://<app-name>.fly.dev`                |
| `wrangler.{toml,jsonc}` AND the file contains `pages_build_output_dir` OR `[env.preview]` AND `pages_…`     | **Cloudflare Pages**       | `gh api .../deployments?environment=Preview` OR `wrangler pages deployment list --project-name=<name>` |
| `wrangler.{toml,jsonc}` AND no Pages markers (the common Workers case)                                     | **Cloudflare Workers**     | **No per-branch preview URL exists.** Workers deploys overwrite production. See "Workers gotcha" below. |
| `.circleci/config.yml`                                                                                     | **CircleCI** (deploy-anywhere) | Branch → fixed URL mapping for known repos; otherwise CircleCI job log grep |
| `.github/workflows/*.yml` containing `pages-build-deployment`, `actions/deploy-pages`, or similar          | **GitHub Pages**           | `gh api .../deployments?environment=github-pages`                            |
| Any `.github/workflows/*.yml` with `cloudflare/wrangler-action` deploying on PR (not just push to master)  | Cloudflare Workers w/ PR-aware deploy | Read the workflow log for the printed URL — see "Workflow log grep" below   |
| **None of the above**                                                                                      | Unknown                    | Ask the user. Don't guess.                                                  |

### Quick auto-detect script

```bash
detect_deploy_target() {
  local repo="${1:-$(pwd)}"
  if [ -f "$repo/vercel.json" ]; then echo "vercel"; return; fi
  if [ -f "$repo/netlify.toml" ]; then echo "netlify"; return; fi
  if [ -f "$repo/fly.toml" ]; then echo "fly"; return; fi
  if ls "$repo"/wrangler.* 2>/dev/null | grep -q .; then
    if grep -q -E 'pages_build_output_dir|\[env\.preview\]' "$repo"/wrangler.* 2>/dev/null; then
      echo "cf-pages"
    else
      echo "cf-workers"
    fi
    return
  fi
  if [ -f "$repo/.circleci/config.yml" ]; then echo "circleci"; return; fi
  if ls "$repo/.github/workflows"/*.yml 2>/dev/null | xargs grep -l "actions/deploy-pages\|pages-build-deployment" 2>/dev/null | grep -q .; then
    echo "github-pages"
    return
  fi
  echo "unknown"
}
```

## Workers gotcha

**Cloudflare Workers (deployed via `wrangler deploy` or `cloudflare/wrangler-action`) does not create per-PR preview URLs by default.** Each deploy overwrites the production Worker. So for any repo deployed this way there is no preview URL for a PR branch.

The realistic answer in these cases is one of:
1. **"Merge to main and check production"** — for low-stakes changes.
2. **"Run the dev server locally"** — `npm run dev` and use `/agent-browser` on `http://localhost:3000`.
3. **"Spin up a per-branch Worker with a custom route"** — requires a `wrangler-action` workflow that deploys to `<branch>-<service>.<account>.workers.dev`. If the user wants this set up, route to `/cloudflare-cli` and offer to add a workflow.

When asked "where's the preview" for a Workers project, **say "Workers doesn't do per-PR previews" up front** rather than spending tokens hunting for a URL that doesn't exist.

## Recipes by target

### Vercel / Netlify / Cloudflare Pages

All three register GitHub deployments. Single recipe works:

```bash
# Find the most recent deployment for the branch
DEPLOY_ID="$(gh api "repos/:owner/:repo/deployments?ref=$BRANCH" --jq '.[0].id')"
gh api "repos/:owner/:repo/deployments/$DEPLOY_ID/statuses" --jq '.[0].environment_url'
```

If multiple environments exist on the same branch (e.g., `Preview` and `Production`), filter:

```bash
gh api "repos/:owner/:repo/deployments?ref=$BRANCH&environment=Preview" --jq '.[0].id'
```

`environment` is **case-sensitive**. Vercel uses `Preview`, Cloudflare Pages uses `Preview`, GitHub Pages uses `github-pages`. Run `gh api .../deployments --jq '[.[] | .environment] | unique'` first if unsure.

For Cloudflare Pages, cross-check against `wrangler pages deployment list --project-name=<name>` (see `/cloudflare-cli`) — the GitHub deployment occasionally lags behind the actual Pages state.

### Fly.io

```bash
APP="$(awk -F'"' '/^app =/ {print $2}' "$REPO/fly.toml")"
flyctl status -a "$APP" --json | jq -r .Hostname
# Result is usually <app>.fly.dev
```

For per-PR Fly previews (using the `fly-pr-review-apps` GH Action or similar), the URL is in the workflow comment on the PR:

```bash
gh pr view --json comments --jq '.comments[] | select(.author.login | test("fly|bot")) | .body' \
  | grep -oE 'https://[a-z0-9.-]+\.fly\.dev' | head -1
```

### CircleCI

For Facilitron repos with fixed branch→bucket mappings (`marketing-pages`, `marketing-dynamic-landing-pages`, nuxt-layers playgrounds), the URL is a **function of the branch**, not a per-PR preview. **Look the branch up in the table below before hitting the CircleCI API or grepping a job log** — it's the authoritative answer and saves the round trip. (Source of truth: each repo's own `README.md` "Production Environments" section; this table mirrors it.)

#### marketing-pages (`Facilitron/marketing-pages`)

| Branch       | Environment | URL                                    |
|--------------|-------------|----------------------------------------|
| `dev`        | Development | https://morning-coast.facilitron.com   |
| `staging`    | Staging     | https://staging.facilitron.com         |
| `production` | Production  | https://www.facilitron.com             |

Only `dev`, `staging`, and `production` deploy — the CircleCI `build_and_deploy` workflow filters to exactly those three branches. The `dev` alias is **`morning-coast.facilitron.com`**, not `dev.facilitron.com` — it's a CloudFront alias served via Heroku (a `server: Heroku` header on dev is expected, sometimes with an A/B variant cookie). **`master` and feature/PR branches don't deploy anywhere** — there is no per-PR preview; merge into `dev` and visit the dev URL above once CircleCI finishes.

> When curling any of these CloudFront-served URLs to verify a deploy, always pass `--compressed` — they return gzip by default, which silently breaks `grep`.

The sibling repos (`marketing-dynamic-landing-pages`, nuxt-layers playgrounds) also deploy per-branch via CircleCI but to their **own** domains — check each repo's README rather than assuming these URLs. `/circleci` carries this same table plus the per-branch deploy-target/bucket names.

For arbitrary CircleCI projects:

```bash
# Find latest pipeline → workflow → job for branch (see /circleci for full recipe)
SLUG="gh/<org>/<repo>"
PIPELINE_ID="$(curl -s -H "Circle-Token: $CIRCLECI_TOKEN" \
  "https://circleci.com/api/v2/project/$SLUG/pipeline?branch=$BRANCH" \
  | jq -r '.items[0].id')"

# Then: workflow → job → artifacts. If artifacts contain a deploy-url.txt, that's the answer.
# Otherwise: grep the deploy job's log for https://
```

### Workflow log grep (last resort for ad-hoc setups)

When the deploy target is "some workflow that prints the URL to stdout":

```bash
RUN="$(gh run list --branch "$BRANCH" --limit 1 --json databaseId --jq '.[0].databaseId')"
gh run view "$RUN" --log | grep -oE 'https?://[a-z0-9.-]+(?:/[^[:space:]]*)?' \
  | grep -v 'github\.com\|githubusercontent\.com' \
  | sort -u
```

This is heuristic — review the matches with the user before treating any as "the staging URL."

## The full synthesis flow

When invoked, do this:

1. **Detect** — run the auto-detect script above.
2. **State what you detected** — one line like "This is a Cloudflare Workers project; Workers doesn't do per-PR previews."
3. **Apply the right recipe** — call out which underlying skill you're routing to (`tron:gh`, `/circleci`, `/cloudflare-cli` — the latter two are global/Cloudflare-plugin skills, not bundled here).
4. **Return the URL** with a confidence note — `"high"` if the deployment is registered + recent, `"medium"` if it's from a log-grep, `"low"` if you guessed from a branch pattern.
5. **Suggest the next step** — usually `/agent-browser` to walk it, or `/verify` to test it.

Don't ask the user follow-up questions if the auto-detect is unambiguous. Only ask when:
- Multiple deploy targets are configured (rare)
- The repo is in the "unknown" bucket
- The latest deployment is older than the latest commit on the branch (likely CI failed)

## Example invocations

```
> "where's my staging link for this branch?"
detect_deploy_target → cf-workers
→ "This is a Cloudflare Workers project — there's no per-PR preview URL.
   To verify your changes:
   - run `npm run dev` locally and use /agent-browser, or
   - merge to master and check production after the wrangler-action workflow completes."

> "where did the PR for MD-1743 deploy?"
detect_deploy_target → circleci (marketing-pages)
→ "Marketing-pages doesn't preview per-PR — it deploys per-branch.
   This PR is on `MD-1743-homepage-access-issue-announcement` which won't deploy anywhere until merged into `dev`.
   After merge into dev: https://morning-coast.facilitron.com"

> "preview URL for the <Workers-deployed repo> PR"
detect_deploy_target → cf-workers
→ "Same Workers gotcha — no preview URL. Use the dev server."

> "preview URL for this Pages project"
detect_deploy_target → cf-pages
→ runs the gh deployments recipe, returns the .pages.dev URL.
```

## Output conventions

When returning the URL, lead with the URL itself. One line. Then the confidence + how to verify on the next line.

```
https://staging.example.com  (high confidence — registered as GitHub deployment 2 min ago)
→ /agent-browser to walk it, or /verify to test it.
```

Avoid: long preamble, restating the detection steps, multiple URL candidates without picking one. The user is asking for a link — give them a link.
