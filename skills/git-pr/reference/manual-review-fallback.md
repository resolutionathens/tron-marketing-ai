# Manual Retro Fallback

Use this only when `git-pr-retro.sh` cannot be resolved **and both `TRON_DISPATCH_ID` and
`TRON_API_URL` are unset**. If either variable is set, there is no direct-GitHub fallback: report
the missing helper and stop without claiming Scout recorded durable retrospective state.

There is nothing to fall back to for the code review itself: it runs before the PR (SKILL.md Step
1c) via `bun run review:local`, which does not use this script. If that review could not run, say so
prominently in Step 8 rather than substituting a reviewer here — no automated review arrives after
the PR opens, so there is nothing to request, poll, or wait for.

For an interactive retro, run `tools/git/token-usage.sh`, write the marker, headings, literal model ID, and
token line to a unique temp file, then post it with `gh pr comment "<N>" --body-file "$RETRO_BODY"`.

- Create that file with `RETRO_BODY="$(mktemp "${TMPDIR:-/tmp}/tron-retro-body.XXXXXX")"` and `trap 'rm -f "$RETRO_BODY"' EXIT`.
- The template must end in `X` characters with no suffix after them. BSD `mktemp`, which macOS ships, substitutes only the trailing X run, so a suffixed template returns that literal name and then fails `File exists` on the next run.
- The retro comment needs the `<!-- tron-retro -->` marker (the OS reviewer requires it); use `<!-- tron-note -->` on any other comment you post on this PR.
