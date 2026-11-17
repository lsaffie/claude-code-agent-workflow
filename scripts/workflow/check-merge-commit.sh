#!/usr/bin/env bash
# Checks that a commit on the production branch is a merge commit (2 parents).
# The release PR must merge with "Create a merge commit". A squash, a rebase or a
# direct push gives 1 parent, and then the next release PR shows old changes again.
# Usage: check-merge-commit.sh <sha>     Exit 1 when the commit is not a merge commit.
set -uo pipefail
sha=${1:?usage: check-merge-commit.sh <sha>}
parents=$(git rev-list --parents -n 1 "$sha" | wc -w)
parents=$((parents - 1))
if [ "$parents" -eq 2 ]; then
  echo "ok: $sha is a merge commit."
  exit 0
fi
echo "not a merge commit: $sha has $parents parent(s): $(git log -1 --format=%s "$sha")" >&2
exit 1
