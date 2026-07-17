# Manual Review Fallback

Use this only when `git-pr-retro.sh` cannot be resolved.

- Skip a Copilot request only for a doc-only diff (`*.md` or `*.mdx`, at most three files and 40 changed lines).
- Otherwise request Copilot with `gh pr edit "<N>" --add-reviewer "@copilot" || true`.
- If `TRON_COPILOT_UNAVAILABLE` is set, do not poll. Post a `<!-- tron-note -->` status comment that no automated review ran and the PR is at the human approval gate.
- Otherwise poll the GitHub reviews endpoint for a submitted Copilot review for a bounded period. Read and address valid inline comments, commit the fixes, and post a status comment. If no review arrives, post the same explicit no-review status comment.
- For the retro, run `tools/git/token-usage.sh`, write the marker, headings, literal model ID, and token line to a unique `mktemp` file, then post it with `gh pr comment "<N>" --body-file "$RETRO_BODY"`.
