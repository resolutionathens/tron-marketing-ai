#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SKILLS="brainstorm case-study creative-request email-campaign grill initiative-report keyword-research landing-page-seo md-to-pdf onesheet press-release seo-report social-post spotlight video-brief video-publish weekly-update"
EVALUATIONS="
evaluations/design/creative-request-brief.json
evaluations/drafting/brainstorm-campaign.json
evaluations/drafting/case-study-district.json
evaluations/drafting/email-campaign-newsletter.json
evaluations/drafting/grill-draft.json
evaluations/drafting/md-to-pdf-toolkit.json
evaluations/drafting/onesheet-product.json
evaluations/drafting/press-release-launch.json
evaluations/drafting/social-post-iglfli.json
evaluations/drafting/spotlight-newhire.json
evaluations/jira-ops/initiative-report-rollup.json
evaluations/jira-ops/weekly-update-status.json
evaluations/seo/keyword-research-cluster.json
evaluations/seo/landing-page-seo-spec.json
evaluations/seo/seo-report-monthly.json
evaluations/video/video-brief-feature.json
evaluations/video/video-publish-kit.json
"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ "$(wc -w <<<"$SKILLS" | tr -d ' ')" -eq 17 ]] || fail "durable skill inventory must contain exactly 17 skills"

for skill in $SKILLS; do
  file="$ROOT/skills/$skill/SKILL.md"
  rg -q 'tools/content/durable-deliverables\.md' "$file" || fail "$skill does not link the durable delivery contract"
  rg -q 'Resolve the durable destination before drafting' "$file" || fail "$skill does not resolve destination before drafting"
  rg -q 'return the complete success block' "$file" || fail "$skill does not return the complete durable metadata"
  rg -qi '(never|neither).*repositor.*Git' "$file" || fail "$skill does not prohibit repository and Git work"
done

contract="$ROOT/tools/content/durable-deliverables.md"
for field in \
  'Durable source:' \
  'Review state:' \
  'Owner:' \
  'Approver:' \
  'Target surface:' \
  'Jira:' \
  'Asset references:' \
  'Website handoff:'
do
  rg -q -F "$field" "$contract" || fail "durable contract is missing success field: $field"
done
rg -q 'Confluence space plus parent/page ID' "$contract" || fail "durable contract does not require an explicit Confluence destination"
rg -q 'explicit Google Drive folder/file ID' "$contract" || fail "durable contract does not require an explicit Drive destination"
rg -q 'explicit non-temporary local folder selected by the user' "$contract" || fail "durable contract does not require an explicit durable file destination"
rg -q 'mktemp -d .*tron-content\.XXXXXX' "$contract" || fail "durable contract does not create a unique scratch workspace"
rg -q 'success and failure both remove the workspace' "$contract" || fail "durable contract does not require cleanup on success and failure"
rg -q 'website handoff only.*content skill may use' "$contract" || fail "durable contract does not permit the worktree-first website handoff"
rg -q 'tron:start-ticket' "$contract" || fail "durable contract does not name the create-worktree path"
rg -q 'tron:open-worktree' "$contract" || fail "durable contract does not name the reopen-worktree path"
rg -q 'content skill never writes repository content, commits' "$contract" || fail "durable contract does not preserve the repository-write boundary"
if rg -q 'never create or switch branches, open worktrees' "$contract"; then
  fail "durable contract still contradicts the required worktree-first website handoff"
fi

[[ "$(wc -w <<<"$EVALUATIONS" | tr -d ' ')" -eq 17 ]] || fail "durable evaluation inventory must contain exactly 17 scenarios"
for relative in $EVALUATIONS; do
  file="$ROOT/$relative"
  rg -qi '(durable|approved-source)' "$file" || fail "$relative does not check a durable destination"
  for field in 'review state' 'owner' 'approver' 'target surface' 'Jira' 'asset' 'website handoff'; do
    rg -qi "$field" "$file" || fail "$relative does not check $field metadata"
  done
  rg -qi 'scratch workspace' "$file" || fail "$relative does not check scratch workspace ownership"
  rg -qi '(success and failure|success or failure|success and on failure|publishing success or failure)' "$file" || fail "$relative does not check cleanup on success and failure"
  rg -qi '(git-free|(never|no |does not|without ).*(repo|repository|Git|branch|worktree|commit|pull request| PR))' "$file" || fail "$relative does not check the repository/Git boundary"
done

if rg -n 'expects? .*deliverable.*(/tmp|\$TMPDIR)|Writes? .* to /tmp|output PDF under /tmp|draft path \(e\.g\. /tmp' "$ROOT/evaluations"; then
  fail "an evaluation still expects a completed deliverable under temporary storage"
fi

if rg -q '/tmp/facilitron-md-to-pdf' "$ROOT/skills/md-to-pdf/build.ts"; then
  fail "md-to-pdf renderer still has a temporary default destination"
fi
rg -q -- '--out is required' "$ROOT/skills/md-to-pdf/build.ts" || fail "md-to-pdf renderer does not require explicit scratch output"

if rg -q 'OUT:-/tmp' "$ROOT/skills/brainstorm/scripts/brainstorm.sh"; then
  fail "brainstorm helper still has a temporary default destination"
fi
rg -q 'save requires --out' "$ROOT/skills/brainstorm/scripts/brainstorm.sh" || fail "brainstorm helper does not require explicit scratch output"
echo "PASS: content durable destination and cleanup contract"
