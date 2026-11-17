#!/usr/bin/env bash
# Creates the release tag and the GitHub Release for a commit on the production branch.
# The tag is release-YYYY-MM-DD.N (N counts the releases of that day, from 1).
# The notes are the body of the PR that brought the commit (the release PR).
# Without such a PR, the notes list the commits since the last release tag.
# When a release tag already points at the commit (a deploy script made it), it only
# makes the GitHub Release for that tag.
# Usage: release-tag.sh <sha>        DRY_RUN=1 prints the tag and notes, changes nothing.
# Needs GH_TOKEN with contents: write, and REPO=owner/name.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
sha=$(git rev-parse "${1:?usage: release-tag.sh <sha>}")
REPO=${REPO:?set REPO=owner/name}

git fetch -q --tags origin 2>/dev/null || true
tag=$(git tag --points-at "$sha" --list 'release-*' | head -1)
if [ -z "$tag" ]; then
  day=$(date -u +%Y-%m-%d)
  n=$(( $(git tag --list "release-$day.*" | wc -l) + 1 ))
  tag="release-$day.$n"
fi

pr=$(gh api "repos/$REPO/commits/$sha/pulls" --jq '[.[] | select(.merged_at != null)][0] // empty' 2>/dev/null || true)
if [ -n "$pr" ]; then
  title="$(jq -r .title <<<"$pr") (#$(jq -r .number <<<"$pr"))"
  notes=$(jq -r '.body // ""' <<<"$pr")
else
  prev=$(git describe --tags --abbrev=0 --match 'release-*' "$sha^" 2>/dev/null || true)
  title="commits since ${prev:-the first commit}"
  notes=$(git log --no-merges --format='- %s' "${prev:+$prev..}$sha")
fi

if [ "${DRY_RUN:-}" = 1 ]; then
  echo "TAG: $tag"
  echo "TARGET: $sha"
  echo "TITLE: $tag: $title"
  echo "NOTES (first 15 lines):"
  printf '%s\n' "$notes" | head -15
  exit 0
fi

notes_file=$(mktemp)
printf '%s\n' "$notes" >"$notes_file"
if gh release view "$tag" -R "$REPO" >/dev/null 2>&1; then
  echo "GitHub Release $tag exists. Nothing to do."
  exit 0
fi
gh release create "$tag" -R "$REPO" --target "$sha" --title "$tag: $title" --notes-file "$notes_file"
