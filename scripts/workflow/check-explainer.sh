#!/usr/bin/env bash
# Checks the change explainers of a branch. The stop hook and CI both run it.
#   1. A branch with code changes adds at least one explainer.
#   2. Each new explainer has a "## What changed and why" paragraph, a Mermaid diagram,
#      3 or more questions under "## Check your understanding", and 3 or more answers
#      in the Answers block.
# Usage: check-explainer.sh <base> <head> [--local]
#   --local also counts uncommitted and untracked files (for the stop hook).
# Settings come from .claude/workflow.json: paths.explainers, paths.nonCode.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

base=$1
head=${2:-HEAD}
local_mode=${3:-}
dir=$(jq -r '.paths.explainers // empty' .claude/workflow.json)
non_code=$(jq -r '.paths.nonCode // empty' .claude/workflow.json)
[ -n "$dir" ] || { echo "check-explainer: paths.explainers is not set in .claude/workflow.json" >&2; exit 1; }

changed=$(git diff --name-only "$base...$head")
added=$(git diff --name-only --diff-filter=A "$base...$head")
if [ "$local_mode" = --local ]; then
  changed+=$'\n'$(git diff --name-only HEAD; git ls-files --others --exclude-standard)
  added+=$'\n'$(git diff --name-only --diff-filter=A HEAD; git ls-files --others --exclude-standard)
fi

# Code means committed or tracked changes outside the non-code paths. A stray untracked
# file (a scratch script) does not count as code.
tracked=$(git diff --name-only "$base...$head"; [ "$local_mode" = --local ] && git diff --name-only HEAD)
code=$(echo "$tracked" | grep -v '^$' | grep -vE "${non_code:-^$}" | sort -u || true)
explainers=$(echo "$added" | grep -E "^$dir/[0-9]{4}-[0-9]{2}-[0-9]{2}-.+\.md$" | sort -u || true)

problems=""
if [ -n "$code" ] && [ -z "$explainers" ]; then
  problems+="This branch changes code but adds no $dir/YYYY-MM-DD-<short-name>.md. Copy $dir/TEMPLATE.md."$'\n'
fi

read_file() {
  if [ "$local_mode" = --local ] && [ -f "$1" ]; then cat "$1"; else git show "$head:$1" 2>/dev/null; fi
}

for f in $explainers; do
  text=$(read_file "$f")
  [ -n "$text" ] || continue # deleted again before commit
  # Lines of text under the heading, outside <!-- comments -->.
  why=$(awk '/^## What changed and why/{s=1; next} /^## /{s=0}
    s { if (/<!--/) c=1; if (!c && NF) n++; if (/-->/) c=0 } END{print n+0}' <<<"$text")
  mermaid=$(grep -c '^```mermaid' <<<"$text" || true)
  questions=$(awk '/^## Check your understanding/{s=1; next} /^<details>|^## /{s=0} s && /^[0-9]+\. /{n++} END{print n+0}' <<<"$text")
  answers=$(awk '/<summary>Answers/{s=1; next} /<\/details>/{s=0} s && /^[0-9]+\. /{n++} END{print n+0}' <<<"$text")
  [ "$why" -ge 1 ] || problems+="$f: no paragraph under \"## What changed and why\"."$'\n'
  [ "$mermaid" -ge 1 ] || problems+="$f: no \`\`\`mermaid diagram."$'\n'
  [ "$questions" -ge 3 ] || problems+="$f: $questions questions under \"## Check your understanding\"; 3 are needed."$'\n'
  [ "$answers" -ge 3 ] || problems+="$f: $answers answers in the Answers block; 3 are needed."$'\n'
  grep -q '<[A-Z][a-z]* [0-9]>' <<<"$text" && problems+="$f: template placeholders are still in the file."$'\n'
done

echo "Code files changed: $(echo "$code" | grep -c . || true). New explainers: ${explainers:-none}" | tr '\n' ' '
echo
if [ -n "$problems" ]; then
  printf '%s' "$problems" >&2
  exit 1
fi
exit 0
