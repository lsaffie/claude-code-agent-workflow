#!/usr/bin/env bash
# Maps a GitHub deployment to "staging", "production" or nothing.
# Usage: smoke-env.sh <deployment-environment> <sha>   (prints "env=<name>" or "env=")
# .claude/workflow.json, deploy.<env>.githubEnvironment, names the environment the host
# reports. When both share a name (a host that calls every branch deploy "Preview"),
# staging also needs the sha to be the head of the integration branch.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

deploy_env=$1
sha=$2
prod_env=$(jq -r '.deploy.production.githubEnvironment // empty' .claude/workflow.json)
stg_env=$(jq -r '.deploy.staging.githubEnvironment // empty' .claude/workflow.json)
integration=$(jq -r '.branches.integration' .claude/workflow.json)

if [ -n "$prod_env" ] && [ "$deploy_env" = "$prod_env" ]; then
  echo "env=production"
elif [ -n "$stg_env" ] && [ "$deploy_env" = "$stg_env" ]; then
  head=$(gh api "repos/${REPO:?}/branches/$integration" --jq .commit.sha)
  if [ "$head" = "$sha" ]; then echo "env=staging"; else echo "env="; fi
else
  echo "env="
fi
