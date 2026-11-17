#!/usr/bin/env bash
# Stop: before Claude ends its turn, check the whole change.
#   1. commands.lint and commands.typecheck.
#   2. commands.coverage (unit tests and a coverage gate), or commands.unitTests
#      when the repo has no coverage command.
#   3. scripts/workflow/check-explainer.sh: an explainer for code changes, with a
#      "What changed and why" paragraph, a diagram and 3 questions.
# Loop guard: stop_hook_active is true when Claude already continues because of this hook.
# Then the hook blocks at most MAX_BLOCKS times in a row, and after that lets Claude stop
# and say what is still broken. Build and end-to-end tests run in CI, not here.
source "$(dirname "$0")/lib.sh"

MAX_BLOCKS=3
input=$(cat)
active=$(echo "$input" | jq -r '.stop_hook_active // false')
session=$(echo "$input" | jq -r '.session_id // "unknown"')
counter="${TMPDIR:-/tmp}/wf-stop-hook-$session"

[ "$active" = "true" ] || rm -f "$counter"

# Nothing changed on this branch: nothing to check.
[ -n "$(changed_files)" ] || exit 0

problems=""

if ! out=$(run lint 2>&1); then
  problems+=$'\n\n## Lint fails\n'"$(echo "$out" | tail -30)"
fi

if ! out=$(run typecheck 2>&1); then
  problems+=$'\n\n## Type check fails\n'"$(echo "$out" | tail -30)"
fi

tests=coverage
[ -n "$(wf '.commands.coverage')" ] || tests=unitTests
if ! out=$(run "$tests" 2>&1); then
  problems+=$'\n\n## Unit tests or coverage fail\n'"$(echo "$out" | grep -E 'FAIL|✗|×|AssertionError|Error:|expected|dropped|below' | head -40)"
fi

base=$(git merge-base "$(base_ref)" HEAD 2>/dev/null || echo HEAD)
if ! out=$(bash scripts/workflow/check-explainer.sh "$base" HEAD --local 2>&1); then
  problems+=$'\n\n## Change explainer\n'"$out"
fi

[ -n "$problems" ] || { rm -f "$counter"; exit 0; }

count=$(( $(cat "$counter" 2>/dev/null || echo 0) + 1 ))
echo "$count" > "$counter"
if [ "$count" -gt "$MAX_BLOCKS" ]; then
  rm -f "$counter"
  echo "stop hook: checks still fail after $MAX_BLOCKS fix attempts. Stopping. Report these failures to the owner:$problems" >&2
  exit 0
fi

fail "stop hook (attempt $count of $MAX_BLOCKS): fix these before you stop.$problems"
