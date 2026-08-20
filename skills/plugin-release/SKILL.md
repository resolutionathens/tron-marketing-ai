---
name: plugin-release
model: sonnet
effort: medium
description: "Cut the next Tron plugin release: select a semantic version bump, summarize unreleased changes, record the release boundary, and prepare the dedicated release PR. Use for 'cut the next Tron plugin release', 'release the Tron plugin', or 'publish the next plugin version'. Do not use for ordinary feature or fix work."
allowed-tools:
  - Bash
  - Read
scout:
  surface: developer
  effects: [publish]
---

# Cut a Tron plugin release

This is the only workflow that changes plugin versions. Ordinary feature, fix, documentation, and
package PRs are unreleased work: leave `.claude-plugin/plugin.json` and
`.codex-plugin/plugin.json` unchanged, even when they modify a skill.

## Release boundary

Start only from an explicit request to cut a release. Work on a dedicated release ticket and branch.
Find the prior boundary with `git tag --sort=-creatordate | head -1`; compare it to `HEAD` with
`git log --oneline <previous>..HEAD`. Select PATCH for compatible fixes/refinements, MINOR for
additive capability, and MAJOR for breaking changes. If the changes span levels, select the highest
required level and say why in the PR.

Update both manifests to the same selected version. Add `releases/v<version>.md` exactly as:

```md
# Tron v<version>

Previous release: v<previous>

## Changes

- <one concise item per commit since the previous boundary>
```

The immutable GitHub tag created by the release workflow is the recorded boundary; the checked-in
record preserves its source range and release notes. Do not change a version without this record,
and do not add a record without the matching synchronized version update.

Run `bash tools/release/validate-release-boundary.sh origin/master`, followed by the repository's
normal package and release checks. Then use `tron:git-commit` and `tron:git-pr`; the PR is the human
gate. After merge, `.github/workflows/release.yml` publishes the immutable release from that boundary.
