#!/usr/bin/env bash
# Read-only smoke test of a deployed environment. It sends GET requests only.
# Usage: smoke.sh <staging|production> [base-url]
# The URL and the checks come from .claude/workflow.json, smoke.<env>:
#   { "url": "https://...", "checks": [ { "path": "/login", "status": 200 } ] }
# Each check gets 3 tries, 15 seconds apart, because a new deploy can take a moment
# to reach its domain. Exit 1 when any check fails.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

env_name=${1:?usage: smoke.sh <staging|production> [base-url]}
cfg=$(jq -c --arg e "$env_name" '.smoke[$e] // empty' .claude/workflow.json)
[ -n "$cfg" ] || { echo "smoke: no smoke.$env_name in .claude/workflow.json" >&2; exit 1; }
url=${2:-$(jq -r '.url' <<<"$cfg")}
url=${url%/}

failed=0
while IFS=$'\t' read -r path want; do
  got=000
  for try in 1 2 3; do
    # -L follows redirects; the check reads the status of the last response.
    got=$(curl -sSL --max-redirs 5 -m 30 -o /dev/null -w '%{http_code}' "$url$path" 2>/dev/null || echo 000)
    [ "$got" = "$want" ] && break
    [ "$try" -lt 3 ] && sleep 15
  done
  if [ "$got" = "$want" ]; then
    echo "ok    GET $url$path -> $got"
  else
    echo "FAIL  GET $url$path -> $got (want $want)"
    failed=1
  fi
done < <(jq -r '.checks[] | "\(.path)\t\(.status)"' <<<"$cfg")

exit $failed
