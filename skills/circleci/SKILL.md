---
name: circleci
model: sonnet
effort: medium
description: "Interact with CircleCI pipeline internals from the command line — list/watch pipelines and workflows, fetch run logs and artifacts, validate `.circleci/config.yml`, and run jobs locally for testing. Use this skill whenever the user references a CircleCI pipeline, workflow run, or job (e.g., 'why did CircleCI fail', 'watch the CI run on this branch'), wants to validate or lint a CircleCI config, wants to test a job locally, or pastes a circleci.com/pipelines/... URL. Also trigger on phrases like 'check the CircleCI build', 'pipeline status', 'config validate', 'run this job locally'."
allowed-tools:
  - Bash
  - Read
  - WebFetch
scout:
  surface: developer
---

# CircleCI

Use the `circleci` CLI for config tasks and local execution. For everything else, hit the v2 API with `curl`.

## Fast path (scripted)

```bash
name=circleci
SKILL_DIR="${CLAUDE_SKILL_DIR:-${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/skills/$name}}"
[ -e "$SKILL_DIR/scripts/circleci.sh" ] || SKILL_DIR="$(for d in ~/.claude/plugins/cache/*/*/*/skills/$name ~/.claude/plugins/marketplaces/*/skills/$name; do [ -e "$d/scripts/circleci.sh" ] && echo "$d"; done | sort -V | tail -1)"
[ -e "$SKILL_DIR/scripts/circleci.sh" ] || { echo "tron:$name: scripts/circleci.sh not found — run /plugin update (or set CLAUDE_PLUGIN_ROOT)" >&2; exit 1; }
bash "$SKILL_DIR/scripts/circleci.sh" <subcommand> [flags]
```

For the full subcommand table and raw v2 API curl recipes, see `reference/commands.md`. The script resolves the token from `$CIRCLECI_TOKEN` (else `~/.circleci/cli.yml`), defaults the slug from `git remote origin` and the branch from `HEAD`.

### Common subcommands

| Want | Command |
|------|---------|
| Branch's workflow statuses | `circleci.sh status [--slug S] [--branch B]` |
| Watch workflow to completion | `circleci.sh watch --workflow <id>` (run_in_background: true) |
| Read job log | `circleci.sh logs --job <number> [--grep-urls]` |
| Rerun workflow | `circleci.sh rerun --workflow <id> [--from-failed]` |
| Deploy URL lookup | `circleci.sh deploy-url <branch>` |

Full subcommand table (pipelines, workflows, jobs, artifacts, trigger, slug,
validate/process/local) lives in `reference/commands.md`.

## Setup — auth

The token lives at `app.circleci.com/settings/user/tokens`. Export as `$CIRCLECI_TOKEN` or configure via `circleci setup`.

```bash
# Verify auth
curl -s -H "Circle-Token: $CIRCLECI_TOKEN" https://circleci.com/api/v2/me | jq .login
```

Unauthenticated requests return `{"message": "Project not found"}`.

## Facilitron deploy URLs (marketing-pages)

`circleci.sh deploy-url <branch>` is the canonical lookup — don't reconstruct the
URLs from memory. One gotcha worth knowing: the `dev` alias is **morning-coast**
(`morning-coast.facilitron.com`), not `dev.facilitron.com`. Only
`dev`/`staging`/`production` deploy — feature branches do not get preview URLs.
Check each repo's README for sibling repos.

## Config validation & local execution

```bash
circleci config validate                  # validate config.yml before committing
circleci config process .circleci/config.yml | less   # view expanded config
circleci local execute --job <job-name>   # run job locally (no project env vars/contexts)
```

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `{"message": "Project not found"}` | Missing/wrong `Circle-Token`. Re-mint the token. |
| Same, with valid token | Slug case mismatch — use `gh/Facilitron/...` (capital F). |
| Workflow stuck in `running` >1h | A job is hung or on hold. `curl .../workflow/<id>/job` to find it. |
| `config validate` ok but cloud fails | Cloud has version constraints local doesn't enforce. Push to throwaway branch. |