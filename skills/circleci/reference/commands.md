# CircleCI command reference

Reference for `tron:circleci` — the scripted subcommand table, the raw v2 API curl
recipes each subcommand wraps, and the CLI-side config/local-run commands. The main
SKILL.md keeps the run model, the deploy-URL table, and troubleshooting; this file is
the command catalog.

## Contents

- Scripted subcommands (`scripts/circleci.sh`)
- Common harness recipes (raw v2 API)
- CLI side: config validation & local execution
- Output handling

## Scripted subcommands (`scripts/circleci.sh`)

Every recipe below is also a subcommand of the bundled wrapper — reach for it first
instead of reassembling `curl … | jq …` by hand.

| Want                                            | Command                                                      |
| ----------------------------------------------- | ------------------------------------------------------------ |
| Auth check                                      | `circleci.sh me`                                             |
| Branch's workflow statuses (the green/red dots) | `circleci.sh status [--slug S] [--branch B]`                 |
| Latest pipelines / workflows / jobs             | `circleci.sh pipelines` · `workflows` · `jobs --workflow ID` |
| Poll a workflow to completion                   | `circleci.sh watch --workflow ID [--interval 15]`            |
| A job's artifacts (deploy URLs often live here) | `circleci.sh artifacts --job N`                              |
| Raw step logs (`--grep-urls` for deployed URLs) | `circleci.sh logs --job N [--tail 250] [--grep-urls]`        |
| Rerun (everything or `--from-failed`) / trigger | `circleci.sh rerun --workflow ID` · `trigger`                |
| Derive `gh/Org/repo` from the origin remote     | `circleci.sh slug`                                           |
| Per-branch deploy URL (repo-declared)           | `circleci.sh deploy-url <branch>` — see `source` in output   |
| Config validate / process / local run           | `circleci.sh validate` · `process` · `local --job-name NAME` |

It authenticates through the org-secret broker (`secrets.facilitron.work/circleci/*`)
via a `cloudflared`-minted Access token — no local `$CIRCLECI_TOKEN` needed — defaults
the slug from `git remote origin` and the branch from `HEAD`, and emits one JSON
line per verdict (`logs`/`process`/`validate`/`local` print raw text). Exit `0`
success / `1` logical failure / `2` usage error. For `watch`, run it with
`run_in_background: true` + `Monitor` to stream the status ticks (it polls every
`--interval` seconds, default 15). Smoke the offline surface (slug derivation, the
deploy-url table, the usage contract) with `bash "$SKILL_DIR/scripts/test-circleci.sh"`.

The recipes below are the reference for what each subcommand does under the hood.

## Common harness recipes (raw v2 API via the broker)

Every recipe below routes through the org-secret broker, not `circleci.com` directly.
Mint the Access token once per session and reuse it:

```bash
TOKEN="$(cloudflared access token --app=https://secrets.facilitron.work)"
```

For curl calls, use `CF-Access-Token: $TOKEN`.

### Latest pipeline for the current branch

```bash
SLUG="gh/Facilitron/marketing-pages"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"

curl -s -H "CF-Access-Token: $TOKEN" \
  "https://secrets.facilitron.work/circleci/v2/project/$SLUG/pipeline?branch=$BRANCH" \
  | jq -r '.items[0] | {id, number, state, "vcs.revision": .vcs.revision}'
```

### Workflows in that pipeline (the green/red dots)

```bash
PIPELINE_ID="$(curl -s -H "CF-Access-Token: $TOKEN" \
  "https://secrets.facilitron.work/circleci/v2/project/$SLUG/pipeline?branch=$BRANCH" \
  | jq -r '.items[0].id')"

curl -s -H "CF-Access-Token: $TOKEN" \
  "https://secrets.facilitron.work/circleci/v2/pipeline/$PIPELINE_ID/workflow" \
  | jq '.items[] | {name, status, id, created_at, stopped_at}'
```

### Jobs in a workflow (where the build/deploy happens)

```bash
WORKFLOW_ID="<workflow-id-from-above>"

curl -s -H "CF-Access-Token: $TOKEN" \
  "https://secrets.facilitron.work/circleci/v2/workflow/$WORKFLOW_ID/job" \
  | jq '.items[] | {name, status, job_number, started_at, stopped_at}'
```

### Watch a workflow until it finishes

The CLI has no `watch` command — poll the API:

```bash
WORKFLOW_ID="<id>"
while true; do
  STATUS="$(curl -s -H "CF-Access-Token: $TOKEN" \
    "https://secrets.facilitron.work/circleci/v2/workflow/$WORKFLOW_ID" | jq -r .status)"
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

curl -s -H "CF-Access-Token: $TOKEN" \
  "https://secrets.facilitron.work/circleci/v2/project/$SLUG/$JOB_NUMBER/artifacts" \
  | jq '.items[] | {path, url}'

# Download a single artifact (e.g., a deploy-url.txt that the deploy step writes)
curl -s -H "CF-Access-Token: $TOKEN" -L "<artifact-url>"
```

If the deploy step doesn't write a `deploy-url.txt` artifact (common case — most configs don't), the URL is wherever the deploy step printed it in the log. See next recipe.

### Read the (last 250 lines of) a job's log

`circleci`'s CLI doesn't expose logs. The v2 API exposes them via `GET /api/v2/project/.../{job-number}` — but it's spread across nested step objects:

```bash
curl -s -H "CF-Access-Token: $TOKEN" \
  "https://secrets.facilitron.work/circleci/v2/project/$SLUG/job/$JOB_NUMBER" \
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
curl -s -X POST -H "CF-Access-Token: $TOKEN" \
  "https://secrets.facilitron.work/circleci/v2/workflow/$WORKFLOW_ID/rerun" \
  -H "Content-Type: application/json" -d '{}'

# Rerun only failed jobs (much faster)
curl -s -X POST -H "CF-Access-Token: $TOKEN" \
  "https://secrets.facilitron.work/circleci/v2/workflow/$WORKFLOW_ID/rerun" \
  -H "Content-Type: application/json" -d '{"from_failed": true}'
```

### Trigger a fresh pipeline on a branch

```bash
curl -s -X POST -H "CF-Access-Token: $TOKEN" \
  "https://secrets.facilitron.work/circleci/v2/project/$SLUG/pipeline" \
  -H "Content-Type: application/json" \
  -d "{\"branch\": \"$BRANCH\"}"
```

Most projects auto-trigger on push, so this is mainly for "no-code-change" rerun scenarios.

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

**Known broken: Docker 29 / arm64 (Apple Silicon).** `circleci local execute` panics on
Docker 29 under arm64 — the CLI's legacy `picard` local-execution agent isn't compatible
(MD-1666). Skip straight to the `docker run` fallback below rather than troubleshooting it.

### Fallback when `circleci local execute` is broken (Docker 29/arm64)

Run the job's commands directly in the same image CircleCI uses, mounting the repo in:

```bash
docker run --rm -v "$PWD:/work" -w /work <ci-image> bash -lc 'npm ci && npm run generate'
```

Replace `<ci-image>` with the `image:` from the job's `docker:` executor in
`.circleci/config.yml`, and the command with whatever the job actually runs (build, test,
lint, etc.). This loses CircleCI-specific conveniences (caching, orbs, contexts) but runs the
same install/build steps and is reliable on affected hosts.

### Pack a multi-file config (advanced)

If `.circleci/config.yml` is split across multiple files (rare), pack them:

```bash
circleci config pack .circleci/src > .circleci/config.yml
```

## Output handling

The v2 API returns JSON by default. Common idioms:

```bash
# Just the field you care about
curl -s -H "CF-Access-Token: $TOKEN" "<url>" | jq -r '.items[].status'

# Paginate (default page-size is 25; max is 1000 for most endpoints)
curl -s -H "CF-Access-Token: $TOKEN" "<url>?page-token=$NEXT" | jq .next_page_token
```

For UI tasks, `circleci open` opens the current project in the browser (no token needed for that).
