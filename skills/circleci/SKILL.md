---
name: circleci
model: sonnet
effort: medium
description: "Interact with CircleCI pipeline internals from the command line — list/watch pipelines and workflows, fetch run logs and artifacts, validate `.circleci/config.yml`, and run jobs locally for testing. Use this skill whenever the user references a CircleCI pipeline, workflow run, or job (e.g., 'why did CircleCI fail', 'watch the CI run on this branch'), wants to validate or lint a CircleCI config, wants to test a job locally, or pastes a circleci.com/pipelines/... URL. Specifically relevant to the Facilitron `marketing-pages`, `marketing-dynamic-landing-pages`, and nuxt-layers-playground repos — they use CircleCI for their dev/staging/production deploys to S3+CloudFront. Also trigger on phrases like 'check the CircleCI build', 'pipeline status', 'config validate', 'run this job locally', 'fetch the artifact', 'CI is red', 'why is the build failing'. For just the staging/preview URL of a deployed branch, or a simple 'has it deployed yet' check, use tron:preview-url."
allowed-tools:
  - Bash
  - Read
  - WebFetch
---

# CircleCI

Use the `circleci` CLI (`/opt/homebrew/bin/circleci`) for config tasks and local job execution. For everything else (listing pipelines, watching runs, fetching logs, finding deploy URLs), hit the **CircleCI v2 API** with `curl` — the CLI exposes a much narrower surface than the API does.

## Fast path (scripted)

Every recipe below is also a subcommand of the bundled wrapper — reach for it
first instead of reassembling `curl … | jq …` by hand:

```bash
# Resolve this skill's bundled dir robustly. $CLAUDE_SKILL_DIR is NOT always exported
# into the agent's Bash (e.g. under the headless worker); never hardcode a version-pinned path.
name=circleci
SKILL_DIR="${CLAUDE_SKILL_DIR:-${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/skills/$name}}"
# fall back to the newest INSTALLED copy that actually contains scripts/circleci.sh
# (skips a stale mirror that lacks it; newest version wins, marketplace breaks ties)
[ -e "$SKILL_DIR/scripts/circleci.sh" ] || SKILL_DIR="$(for d in ~/.claude/plugins/cache/*/*/*/skills/$name ~/.claude/plugins/marketplaces/*/skills/$name; do [ -e "$d/scripts/circleci.sh" ] && echo "$d"; done | sort -V | tail -1)"
[ -e "$SKILL_DIR/scripts/circleci.sh" ] || { echo "tron:$name: can't find scripts/circleci.sh — run /plugin update (or set CLAUDE_PLUGIN_ROOT)" >&2; exit 1; }
bash "$SKILL_DIR/scripts/circleci.sh" <subcommand> [flags]
```

| Want | Command |
|------|---------|
| Auth check | `circleci.sh me` |
| Branch's workflow statuses (the green/red dots) | `circleci.sh status [--slug S] [--branch B]` |
| Latest pipelines / workflows / jobs | `circleci.sh pipelines` · `workflows` · `jobs --workflow ID` |
| Poll a workflow to completion | `circleci.sh watch --workflow ID [--interval 15]` |
| A job's artifacts (deploy URLs often live here) | `circleci.sh artifacts --job N` |
| Raw step logs (`--grep-urls` for deployed URLs) | `circleci.sh logs --job N [--tail 250] [--grep-urls]` |
| Rerun (everything or `--from-failed`) / trigger | `circleci.sh rerun --workflow ID` · `trigger` |
| Derive `gh/Org/repo` from the origin remote | `circleci.sh slug` |
| **marketing-pages** per-branch URL | `circleci.sh deploy-url <dev\|staging\|production>` |
| Config validate / process / local run | `circleci.sh validate` · `process` · `local --job-name NAME` |

It resolves the token from `$CIRCLECI_TOKEN` (else `~/.circleci/cli.yml`), defaults
the slug from `git remote origin` and the branch from `HEAD`, and emits one JSON
line per verdict (`logs`/`process`/`validate`/`local` print raw text). Exit `0`
success / `1` logical failure / `2` usage error. For `watch`, run it with
`run_in_background: true` + `Monitor` to stream the status ticks (it polls every
`--interval` seconds, default 15). Smoke the offline surface (slug derivation, the
deploy-url table, the usage contract) with `bash "$SKILL_DIR/scripts/test-circleci.sh"`.

The prose below is the reference for what each subcommand does under the hood and
the cases worth understanding (the run model, the deploy-URL table, troubleshooting).

## Setup: auth (prerequisite)

The `circleci` CLI and the v2 API both require a personal API token. On this machine, `~/.circleci/cli.yml` exists but contains no token yet — the user must set one up before any read calls work.

```bash
# One-time interactive setup (writes token to ~/.circleci/cli.yml)
circleci setup

# Or, for scripting, export the token directly:
export CIRCLECI_TOKEN="<token-from-app.circleci.com/settings/user/tokens>"
```

The token is minted at `https://app.circleci.com/settings/user/tokens`. Treat it like an SSH key — it has full read+write access to every project the user can see.

For curl calls below, use `Circle-Token: $CIRCLECI_TOKEN`.

```bash
# Verify auth works
curl -s -H "Circle-Token: $CIRCLECI_TOKEN" https://circleci.com/api/v2/me | jq .login
```

Unauthenticated requests return `{"message": "Project not found"}` even for projects you can see in the dashboard — that error usually means missing/wrong token, not missing project.

## Project slugs vs project IDs

CircleCI has two ways to identify a project:

- **Slug** (used by most v2 API endpoints): `gh/<org>/<repo>` — e.g., `gh/Facilitron/marketing-pages`. Case-sensitive on the org name (`Facilitron`, not `facilitron`).
- **UUID** (used by `circleci pipeline list` CLI subcommand and a few v2 endpoints): looks like `12345678-1234-...-123456789012`. Find it in the project's settings URL or via `GET /api/v2/project/<slug>` → `.id`.

Default to slug. Only reach for UUID when a specific command demands it.

```bash
# Discover the UUID for a slug (rarely needed)
curl -s -H "Circle-Token: $CIRCLECI_TOKEN" \
  "https://circleci.com/api/v2/project/gh/Facilitron/marketing-pages" | jq -r .id
```

## The CircleCI run model

A push to a branch creates a **pipeline** → which contains 1+ **workflows** → each of which contains 1+ **jobs**. Each level has its own status. You typically care about:

- Pipeline state: `created`, `errored`, `setup-pending`, `setup`, `pending`
- Workflow status: `success`, `failed`, `running`, `not_run`, `failing`, `on_hold`, `canceled`, `unauthorized`
- Job status: same vocabulary as workflow

For "is the deploy done?", the *workflow* status is usually what you want — that's the green/red check that shows up next to a PR.

## Common harness recipes

### Latest pipeline for the current branch

```bash
SLUG="gh/Facilitron/marketing-pages"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"

curl -s -H "Circle-Token: $CIRCLECI_TOKEN" \
  "https://circleci.com/api/v2/project/$SLUG/pipeline?branch=$BRANCH" \
  | jq -r '.items[0] | {id, number, state, "vcs.revision": .vcs.revision}'
```

### Workflows in that pipeline (the green/red dots)

```bash
PIPELINE_ID="$(curl -s -H "Circle-Token: $CIRCLECI_TOKEN" \
  "https://circleci.com/api/v2/project/$SLUG/pipeline?branch=$BRANCH" \
  | jq -r '.items[0].id')"

curl -s -H "Circle-Token: $CIRCLECI_TOKEN" \
  "https://circleci.com/api/v2/pipeline/$PIPELINE_ID/workflow" \
  | jq '.items[] | {name, status, id, created_at, stopped_at}'
```

### Jobs in a workflow (where the build/deploy happens)

```bash
WORKFLOW_ID="<workflow-id-from-above>"

curl -s -H "Circle-Token: $CIRCLECI_TOKEN" \
  "https://circleci.com/api/v2/workflow/$WORKFLOW_ID/job" \
  | jq '.items[] | {name, status, job_number, started_at, stopped_at}'
```

### Watch a workflow until it finishes

The CLI has no `watch` command — poll the API:

```bash
WORKFLOW_ID="<id>"
while true; do
  STATUS="$(curl -s -H "Circle-Token: $CIRCLECI_TOKEN" \
    "https://circleci.com/api/v2/workflow/$WORKFLOW_ID" | jq -r .status)"
  echo "$(date +%H:%M:%S) $STATUS"
  case "$STATUS" in
    success|failed|canceled|error|unauthorized|not_run) break ;;
  esac
  sleep 15
done
```

Run this via `run_in_background: true` and use `Monitor` to stream the status lines rather than blocking the session. Poll at 15s intervals — faster wastes API budget without changing the UX.

### Fetch the artifacts from a finished job (this is where the deploy URL usually lives)

```bash
JOB_NUMBER="<number-from-above>"

curl -s -H "Circle-Token: $CIRCLECI_TOKEN" \
  "https://circleci.com/api/v2/project/$SLUG/$JOB_NUMBER/artifacts" \
  | jq '.items[] | {path, url}'

# Download a single artifact (e.g., a deploy-url.txt that the deploy step writes)
curl -s -H "Circle-Token: $CIRCLECI_TOKEN" -L "<artifact-url>"
```

If the deploy step doesn't write a `deploy-url.txt` artifact (common case — most configs don't), the URL is wherever the deploy step printed it in the log. See next recipe.

### Read the (last 250 lines of) a job's log

`circleci`'s CLI doesn't expose logs. The v2 API exposes them via `GET /api/v2/project/.../{job-number}` — but it's spread across nested step objects:

```bash
curl -s -H "Circle-Token: $CIRCLECI_TOKEN" \
  "https://circleci.com/api/v2/project/$SLUG/job/$JOB_NUMBER" \
  | jq '.steps[].actions[] | select(.status=="failed" or .status=="success") | {name, output_url}' \
  | tail -20
```

`output_url` is a presigned S3 URL — fetch it directly (no auth header) to get the actual log text:

```bash
curl -s -L "<output_url>" | tail -250
```

For "find the deployed URL in a log," grep for `https?://` after the deploy step has run:

```bash
curl -s -L "<deploy-step-output-url>" | grep -iE 'https?://[a-z0-9.-]+' | tail -5
```

### Rerun a workflow (or just its failed jobs)

```bash
WORKFLOW_ID="<id>"

# Rerun everything
curl -s -X POST -H "Circle-Token: $CIRCLECI_TOKEN" \
  "https://circleci.com/api/v2/workflow/$WORKFLOW_ID/rerun" \
  -H "Content-Type: application/json" -d '{}'

# Rerun only failed jobs (much faster)
curl -s -X POST -H "Circle-Token: $CIRCLECI_TOKEN" \
  "https://circleci.com/api/v2/workflow/$WORKFLOW_ID/rerun" \
  -H "Content-Type: application/json" -d '{"from_failed": true}'
```

### Trigger a fresh pipeline on a branch

```bash
curl -s -X POST -H "Circle-Token: $CIRCLECI_TOKEN" \
  "https://circleci.com/api/v2/project/$SLUG/pipeline" \
  -H "Content-Type: application/json" \
  -d "{\"branch\": \"$BRANCH\"}"
```

Most projects auto-trigger on push, so this is mainly for "no-code-change" rerun scenarios.

## Facilitron-specific: marketing-pages deploy URLs

The `marketing-pages` repo deploys via CircleCI to S3+CloudFront. **The URL is a function of the branch**, not a per-PR preview. These are the canonical public URLs (source of truth: the repo's own `README.md` "Environments" section):

| Branch       | Environment | URL                                      | CircleCI deploy target               |
|--------------|-------------|------------------------------------------|--------------------------------------|
| `dev`        | Development | `https://morning-coast.facilitron.com`   | `facilitron-marketing-pages-dev`     |
| `staging`    | Staging     | `https://staging.facilitron.com`         | `facilitron-marketing-pages-staging` |
| `production` | Production  | `https://www.facilitron.com`             | `facilitron-marketing-pages-prod`    |

Note the `dev` alias is **`morning-coast.facilitron.com`**, not `dev.facilitron.com` — it's a CloudFront alias, and the deployed bundle is served via Heroku behind it (a `server: Heroku` header on dev is expected, sometimes with an A/B variant cookie). `tron:preview-url` routes here for the branch→URL lookup, so keep this table concrete — that's the whole point of it living here rather than the agent re-deriving the domain each time.

The sibling repos (`marketing-dynamic-landing-pages`, nuxt-layers playgrounds) also deploy per-branch via CircleCI but to their **own** domains — check each repo's README rather than assuming these URLs.

If the user asks "where's my PR previewed?" for a `marketing-pages` PR — there isn't one until the branch is merged into `dev`. The harness flow is: merge to `dev` → wait for CircleCI to finish → visit the `dev` URL above. **Don't go hunting for per-PR preview URLs on this repo; they don't exist.**

Cross-check against the repo's README (public domains) and `cf agent-context custom-hostnames` (see `/cloudflare-cli`) if a domain ever looks stale — CloudFront distributions can be renamed without updating the repo.

## CLI side: config validation & local execution

### Validate a config before committing

```bash
# Validates syntax and structure
circleci config validate
circleci config validate -c .circleci/config.yml

# Pretty-print the fully-resolved config (with orb references expanded)
circleci config process .circleci/config.yml | head -100
```

Run `config validate` before any commit that touches `.circleci/config.yml`. CircleCI's web UI also validates on push, but catching it locally saves a round trip.

### Test a job locally in a Docker container

```bash
# Pick a job from your config and run it locally (needs Docker)
circleci local execute --job <job-name>

# With a specific config file
circleci local execute -c .circleci/config.yml --job <job-name>
```

`circleci local execute` runs the job inside the same docker image CircleCI would use, **but** it doesn't have access to project-level env vars, contexts, or workspaces. So it's best for fast lint/build/test jobs, less useful for deploy jobs (which depend on AWS creds, etc.).

### Pack a multi-file config (advanced)

If `.circleci/config.yml` is split across multiple files (rare), pack them:

```bash
circleci config pack .circleci/src > .circleci/config.yml
```

## Output handling

The v2 API returns JSON by default. Common idioms:

```bash
# Just the field you care about
curl -s -H "Circle-Token: $CIRCLECI_TOKEN" "<url>" | jq -r '.items[].status'

# Paginate (default page-size is 25; max is 1000 for most endpoints)
curl -s -H "Circle-Token: $CIRCLECI_TOKEN" "<url>?page-token=$NEXT" | jq .next_page_token
```

For UI tasks, `circleci open` opens the current project in the browser (no token needed for that).

## When something goes wrong

| Symptom                                                  | Cause / fix                                                                    |
|----------------------------------------------------------|--------------------------------------------------------------------------------|
| `{"message": "Project not found"}` on a project you can see in the dashboard | Missing or wrong `Circle-Token`. Re-mint at `app.circleci.com/settings/user/tokens`. |
| `Project not found` even with auth                       | Slug case mismatch. Try `gh/Facilitron/...` (capital F) not `facilitron`.       |
| `circleci pipeline list` rejects the slug                 | The `pipeline list` CLI command takes a UUID, not a slug. Look up the UUID first (recipe above). |
| Workflow stuck in `running` for >1h                      | A job is hung or waiting on a `hold` approval. `curl .../workflow/<id>/job` to find the offending job. |
| `circleci local execute` fails with auth/env errors      | Local execution has no project env vars. For deploy jobs that need AWS creds, you can pass `-e KEY=VAL` per env var or accept that the job won't run locally. |
| `config validate` says "ok" but cloud fails              | The cloud has version constraints local doesn't enforce (e.g., experimental features). Push to a throwaway branch to surface them. |
