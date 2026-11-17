#!/usr/bin/env bash
# Runs one command from the repo adapter, .claude/workflow.json (commands.<name>).
# Usage: run.sh <name> [file ...]
#   {file} in the command becomes the first file; {files} becomes all files.
# A null command prints "skipped" and exits 0. The adapter's notes say why.
# A missing key fails, so a typo cannot skip a check.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

name=${1:?usage: run.sh <name> [file ...]}
shift
if ! jq -e --arg n "$name" '.commands | has($n)' .claude/workflow.json >/dev/null; then
  echo "run.sh: commands.$name is missing from .claude/workflow.json. Add it, or set it to null with a note." >&2
  exit 1
fi
cmd=$(jq -r --arg n "$name" '.commands[$n] // empty' .claude/workflow.json)
if [ -z "$cmd" ]; then
  echo "skipped: commands.$name is null. $(jq -r --arg n "$name" '.notes[$n] // ""' .claude/workflow.json)"
  exit 0
fi

quote_all() { local out="" a; for a in "$@"; do out+="$(printf '%q' "$a") "; done; printf '%s' "${out% }"; }
cmd=${cmd//\{files\}/$(quote_all "$@")}
cmd=${cmd//\{file\}/$(quote_all "${1:-}")}
exec bash -c "$cmd"
