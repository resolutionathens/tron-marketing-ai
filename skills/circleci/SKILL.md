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

Use the `circleci` CLI for config tasks and local execution. For everything else, hit the v2 API through the org-secret broker with `curl` (see `reference/commands.md`).

## Fast path (scripted)

```bash
name=circleci
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${CLAUDE_SKILL_DIR:+$CLAUDE_SKILL_DIR/../..}}"
RESOLVER="${PLUGIN_ROOT:+$PLUGIN_ROOT/tools/skill/resolve-skill-dir.sh}"
[ -f "${RESOLVER:-}" ] || RESOLVER="$(find ~/.claude/plugins/cache ~/.claude/plugins/marketplaces ~/.codex/plugins/cache ~/.codex/plugins/marketplaces "$HOME/Library/Application Support/tron-os/tron-releases/versions" -maxdepth 7 -type f -path "*/tools/skill/resolve-skill-dir.sh" 2>/dev/null | sort -V | tail -1 || true)"
[ -f "${RESOLVER:-}" ] || { echo "tron:$name: resolver not found; searched Claude/Codex cache and marketplace roots plus the tron release store" >&2; exit 1; }
SKILL_DIR="$(bash "$RESOLVER" "$name" scripts/circleci.sh)"
bash "$SKILL_DIR/scripts/circleci.sh" <subcommand> [flags]
```

For the full subcommand table and raw v2 API curl recipes, see `reference/commands.md`. The script routes network calls through the org-secret broker (`secrets.facilitron.work/circleci/*`), authenticating via a `cloudflared`-minted Access token. If the broker is unreachable or `cloudflared` unavailable, it falls back to the direct CircleCI v2 API using `CIRCLECI_TOKEN` (from the environment or `~/.env`). It defaults the slug from `git remote origin` and the branch from `HEAD`.

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

Network subcommands primarily route through the org-secret broker at `secrets.facilitron.work/circleci/*` — auth is your Facilitron Google identity via Cloudflare Access:

```bash
cloudflared access login https://secrets.facilitron.work   # one-time SSO, cached + auto-refreshed
circleci.sh me                                              # verify auth → {"ok":true,"login":…}
```

If the broker is unreachable (network issues, TLS handshake flake in dispatched workers), the script falls back to the direct CircleCI v2 API, authenticated with `CIRCLECI_TOKEN`. Set it in your environment or in `~/.env`:

```bash
export CIRCLECI_TOKEN=<your-circleci-token>
# or add to ~/.env:
echo 'CIRCLECI_TOKEN=<your-circleci-token>' >> ~/.env
```

Get a token from https://app.circleci.com/settings/user/tokens.

`circleci config validate`/`process`/`local` still use the local `circleci` CLI (no token involved). Unauthenticated broker requests or missing fallback token return `{"ok":false,"error":"..."}`.

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

**`circleci local execute` is broken on Docker 29 / Apple Silicon (arm64)** — it panics because
the CLI's legacy `picard` local-execution agent doesn't support Docker 29 on arm64 (MD-1666).
Don't spend time debugging it on affected machines; fall back to running the job's commands
directly in the CI image via `docker run`:

```bash
docker run --rm -v "$PWD:/work" -w /work <ci-image> bash -lc 'npm ci && npm run generate'
```

Swap `<ci-image>` and the command for whatever the target job actually runs (see
`.circleci/config.yml`).

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `{"ok":false,"error":"CIRCLECI_TOKEN not set…"}` | Set `CIRCLECI_TOKEN` in your environment or `~/.env` for fallback auth (broker is unreachable). Get one at https://app.circleci.com/settings/user/tokens. |
| `{"ok":false,"error":"no Cloudflare Access token…"}` | Run `cloudflared access login https://secrets.facilitron.work` for broker auth. If broker is down, CIRCLECI_TOKEN fallback activates automatically. |
| `{"message": "Project not found"}` | Slug case mismatch — use `gh/Facilitron/...` (capital F). |
| Workflow stuck in `running` >1h | A job is hung or on hold. `curl .../workflow/<id>/job` to find it. |
| `config validate` ok but cloud fails | Cloud has version constraints local doesn't enforce. Push to throwaway branch. |
| `circleci local execute` panics (Docker 29 / arm64) | Known-broken (MD-1666, legacy `picard` agent). Use the `docker run` fallback above instead of debugging it. |
