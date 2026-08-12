#!/usr/bin/env bash
# ship-notify.sh — post a Jira comment that @-mentions the person waiting on a
# repo when its work reaches production. Sourced, not executed:
#
#   source "$CLAUDE_PLUGIN_ROOT/tools/jira/ship-notify.sh"
#
# Why a script and not skill prose: instructions are advice an agent can skip.
# The notification has to fire on every production promotion, whether a worker
# or a human ran tron:git-pushtoprod, so it lives in the deterministic core.
#
# A plain-text "@dave" in a comment body posts those literal characters and
# notifies nobody. A real notification is an ADF `mention` node carrying the
# person's Jira accountId, which is why the body is built as ADF.

# Repo → Jira accountId of the person to mention on a production ship. The repo
# key is the origin remote's basename (no .git). A repo absent from this map
# notifies nobody — that is the default, and adding a repo here is the whole
# opt-in. Routing lives here rather than inline in the promotion script.
#
# accountIds (confirmed against their Jira profiles):
#   marketing-pages → David Fairbairn
SN_MENTION_REPOS=(marketing-pages)
SN_MENTION_IDS=(5d762d568b0e290c45a9f461)
SN_MENTION_NAMES=("David Fairbairn")

# Echo the repo slug for a checkout — the origin remote's basename, minus .git.
# Empty (return 1) when there is no origin remote.
#   sn_repo_slug <checkout>
sn_repo_slug() {
  local url
  url="$(git -C "$1" remote get-url origin 2>/dev/null)" || return 1
  [[ -z "$url" ]] && return 1
  url="${url%/}"; url="${url##*/}"; url="${url%.git}"
  [[ -z "$url" ]] && return 1
  printf '%s\n' "$url"
}

# Echo "<accountId>\t<displayName>" for a repo that has a mention configured;
# return 1 when it has none (the common case).
#   sn_mention_for <repo-slug>
sn_mention_for() {
  local repo="$1" i
  for i in "${!SN_MENTION_REPOS[@]}"; do
    if [[ "${SN_MENTION_REPOS[$i]}" == "$repo" ]]; then
      printf '%s\t%s\n' "${SN_MENTION_IDS[$i]}" "${SN_MENTION_NAMES[$i]}"
      return 0
    fi
  done
  return 1
}

# Echo the ADF comment body: a mention node followed by prose. Voice follows
# tron:jira-comment — a couple of plain sentences, no bullets, no em dashes.
#   sn_adf_body <accountId> <displayName>
sn_adf_body() {
  printf '{"type":"doc","version":1,"content":[{"type":"paragraph","content":[{"type":"mention","attrs":{"id":"%s","text":"@%s"}},{"type":"text","text":" this is live on production now. The work on this ticket has been merged and promoted, so it is running on the production site."}]}]}' \
    "$1" "$2"
}

# Post the production-shipped mention for <key> when <repo-slug> has one
# configured. Best-effort and silent about success detail: returns 0 when a
# comment was posted, 1 when there was nothing to post or the post failed. The
# caller must never let this change its own exit status or stdout.
#   sn_notify_shipped <key> <repo-slug>
sn_notify_shipped() {
  local key="$1" repo="$2" mention id name body
  [[ -z "$key" || -z "$repo" ]] && return 1
  command -v acli >/dev/null 2>&1 || return 1
  mention="$(sn_mention_for "$repo")" || return 1
  id="${mention%%$'\t'*}"; name="${mention#*$'\t'}"
  body="$(sn_adf_body "$id" "$name")"
  acli jira workitem comment create --key "$key" --body "$body" >/dev/null 2>&1 || return 1
  return 0
}
