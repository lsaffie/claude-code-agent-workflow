#!/usr/bin/env bash
# Opens or updates the one release PR from the integration branch into the production branch.
# CI runs it from .github/workflows/release-pr.yml. Branches, repo, staging URL and host
# come from .claude/workflow.json. A person merges the release PR. CI and the agent never do.
# Local dry run (prints the body, changes nothing): git fetch origin && DRY_RUN=1 scripts/workflow/release-pr.sh
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
wf() { jq -r "$1 // empty" .claude/workflow.json; }
integration=$(wf .branches.integration)
production=$(wf .branches.production)
BASE=${BASE:-origin/$production}
HEAD=${HEAD:-origin/$integration}
REPO=${REPO:-$(wf .repo)}
staging_url=$(wf .smoke.staging.url)
prod_host=$(wf .deploy.production.host)
explainer_dir=$(wf .paths.explainers)
LIMIT=${LIMIT:-60000} # GitHub refuses a PR body over 65536 characters.

head_sha=$(git rev-parse "$HEAD")
count=$(git rev-list --count --no-merges "$BASE..$HEAD")
if [ "$count" -eq 0 ]; then
  echo "$integration has nothing that $production does not have. No release PR."
  exit 0
fi
[ "$count" -eq 1 ] && title="Release: 1 change" || title="Release: $count changes"

explainers=$(git diff --name-only --diff-filter=A "$BASE...$HEAD" -- "$explainer_dir/*.md" | grep -v '/TEMPLATE\.md$' || true)
blob="https://github.com/$REPO/blob/$head_sha"

head_part() {
  echo "## Merged into $integration since $production"
  echo
  git log --reverse --no-merges --format='- %s' "$BASE..$HEAD"
  echo
  echo "## How to release"
  echo
  echo "1. Read the explainers below. Test ${staging_url:-staging}. Check that smoke/staging is green."
  echo "2. Approve, then merge with **Create a merge commit**. Do not squash or rebase: $production would then have commits that $integration does not have."
  echo "3. ${prod_host:-The host} deploys production. The Release workflow tags it."
  echo
  echo "## Change explainers"
  echo
  [ -z "$explainers" ] && echo "None. These changes touch only docs or config."
}

full_explainers() {
  for f in $explainers; do
    # Drop the YAML frontmatter. Add a link to the file under its title.
    # Push headings down two levels, under "## Change explainers".
    git show "$HEAD:$f" |
      awk -v src="Source: [$f]($blob/$f)" '
        NR == 1 && /^---$/ { fm = 1; next }
        fm { if (/^---$/) fm = 0; next }
        { print }
        !done && /^# / { print ""; print src; done = 1 }' |
      sed -E 's/^(#{1,4}) /\1## /'
    echo
  done
}

linked_explainers() {
  echo "The full text is over the GitHub size limit. Open each file:"
  echo
  for f in $explainers; do echo "- [$f]($blob/$f)"; done
}

tail_part() {
  echo
  echo "<!-- release-head sha=$head_sha -->"
  echo "This PR is opened and updated by \`.github/workflows/release-pr.yml\`. Do not edit it by hand."
}

body=$(head_part; full_explainers; tail_part)
if [ "${#body}" -gt "$LIMIT" ]; then
  body=$(head_part; linked_explainers; tail_part)
fi

if [ "${DRY_RUN:-}" = "1" ]; then
  echo "TITLE: $title"
  printf '%s\n' "$body"
  exit 0
fi

# On a local machine, gh uses the owner's own login. In CI, it needs the secret.
if [ -n "${CI:-}" ] && [ -z "${GH_TOKEN:-}" ]; then
  echo "::error::Secret RELEASE_PR_TOKEN is not set. Add it as described in .github/workflows/release-pr.yml."
  exit 1
fi

pr=$(gh pr list -R "$REPO" --base "$production" --head "$integration" --state open --json number --jq '.[0].number // empty')
if [ -z "$pr" ]; then
  gh pr create -R "$REPO" --base "$production" --head "$integration" --title "$title" --body "$body"
  exit 0
fi

old_sha=$(gh pr view "$pr" -R "$REPO" --json body --jq .body | sed -nE 's/.*release-head sha=([0-9a-f]+).*/\1/p')
gh pr edit "$pr" -R "$REPO" --title "$title" --body "$body"
if [ "$old_sha" != "$head_sha" ]; then
  # CI pushes to the integration branch with GITHUB_TOKEN, and such a push starts no workflow on this PR.
  # A close and reopen with RELEASE_PR_TOKEN runs CI and the Claude review on the new head.
  echo "$integration moved from ${old_sha:-unknown} to $head_sha. Reopening the release PR to run CI."
  gh pr close "$pr" -R "$REPO"
  gh pr reopen "$pr" -R "$REPO"
fi
