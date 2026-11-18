#!/usr/bin/env bash
# Tests for .claude/hooks/guard.sh. Run from the repo root: bash scripts/workflow/guard.test.sh
# Each case is: expected exit code (2 = blocked, 0 = allowed), then the command.
# Branch names come from .claude/workflow.json, so the cases build them from it.
# The hook runs as if the command starts in the repo root.
set -u
root=$(git rev-parse --show-toplevel)
cfg="$root/.claude/workflow.json"
[ -f "$cfg" ] || { echo "Missing $cfg. Copy .claude/workflow.json.example first." >&2; exit 1; }
int=$(jq -r .branches.integration "$cfg")
prod=$(jq -r .branches.production "$cfg")
blk=$(jq -r '.deploy.blockedCommands[0] // "deploy-cli-not-set"' "$cfg")

cases=(
  # Force push and pushes to protected branches
  "2|git push --force origin feature"
  "2|git push origin +feature"
  "2|git push --force-with-lease origin feature"
  "2|git push origin HEAD:$prod"
  "2|git push origin $int"
  "2|git push -u origin feature:$int"
  "2|git push origin feature:refs/heads/$prod"
  "2|git -C /tmp/x push origin HEAD:$prod"
  "2|cd /tmp && git push origin $prod"
  "2|FOO=1 timeout 60 git push origin $prod"
  "2|echo \$(git push origin $prod)"
  "2|git push --all origin"
  # Deleting branches
  "2|git push origin --delete feature"
  "2|git push origin :feature"
  "2|git branch -D feature"
  "2|git branch --delete --force feature"
  "2|git branch -d $int"
  "2|git branch -d $prod"
  # Discarding work
  "2|git reset --hard HEAD"
  "2|git reset HEAD~1 --hard"
  "2|git clean -fd"
  "2|git clean --force"
  "2|git checkout ."
  "2|git checkout -- ."
  "2|git checkout -- src/a.ts"
  "2|git restore ."
  # Merges: CI merges feature PRs, a person merges the release PR
  "2|gh pr merge 12 --squash"
  "2|gh pr merge 42 --merge"
  "2|gh api -X PUT repos/o/r/pulls/7/merge"
  "2|gh api repos/o/r/merges -f base=$prod -f head=$int"
  # GitHub API deletes and branch protection
  "2|gh api -X DELETE repos/o/r/git/refs/heads/x"
  "2|gh api repos/o/r/git/refs/heads/x --method DELETE"
  "2|gh api -X PUT repos/o/r/branches/$prod/protection --input p.json"
  "2|gh api repos/o/r/branches/$prod/protection/required_status_checks -X PATCH -f strict=true"
  "2|gh api repos/o/r/rulesets -f name=x"
  "2|gh api repos/o/r/rulesets/1 --method delete"
  # rm -r outside the repo, of the repo, of .git, or of a path the hook cannot read
  "2|rm -rf /"
  "2|rm -rf ~"
  "2|rm -rf ~/projects"
  "2|rm -rf \$HOME/x"
  "2|rm -rf .."
  "2|rm -rf ../other-repo"
  "2|rm -rf /tmp/x"
  "2|rm -fr ../x"
  "2|rm --recursive --force /etc"
  "2|rm -rf ."
  "2|rm -rf *"
  "2|rm -rf .git"
  "2|rm -r -f \"\$DIR\""
  "2|cd .. && rm -rf repo-copy"
  "2|cd /tmp && rm -rf build"
  "2|find . -name x | xargs rm -rf"
  # Deploys: a person runs the deploy script
  "2|bash scripts/workflow/deploy.sh production"
  "2|./scripts/workflow/deploy.sh staging"
  "0|bash scripts/workflow/deploy-preflight.sh production"
  # Secrets
  "2|cat .env"
  "2|cat .env.local"
  "2|grep KEY config/.env.production"
  "2|source .env"
  "2|cat ~/.ssh/id_ed25519"
  "2|cp ~/.aws/credentials x"
  "2|printenv"
  "2|env"
  "2|env | grep KEY"
  # Code in bash -c, sh -c and eval is checked
  "2|bash -c \"git push origin $prod\""
  "2|sh -c 'git reset --hard'"
  "2|eval \"gh pr merge 3\""
  "2|cat > notes.txt <<'EOF'
text
EOF
git push origin $prod"
  # Allowed
  "0|grep -E \"a|hostcli|b\" file.txt"
  "0|git commit -m \"Docs: never git push origin $prod or run a host cli\""
  "0|cat > notes.txt <<'EOF'
git push origin $prod
$blk deploy
EOF"
  "0|echo $blk is the host"
  "0|git push -u origin feature/new-thing"
  "0|git push origin HEAD:feature/new-thing"
  "0|git status --short"
  "0|git reset --soft HEAD~1"
  "0|git clean -n"
  "0|git checkout -b feature/x"
  "0|git checkout $int"
  "0|git restore --staged src/a.ts"
  "0|git branch -d feature/done"
  "0|git branch --show-current"
  "0|gh pr create --base $int --title x --body y"
  "0|gh api repos/o/r/pulls"
  "0|gh api repos/o/r/branches/$prod/protection"
  "0|gh api repos/o/r/rulesets"
  "0|gh api repos/o/r/pulls/7/merge"
  "0|rm -rf node_modules"
  "0|rm -rf dist/*"
  "0|rm -rf ./build coverage"
  "0|rm -f /tmp/x.log"
  "0|rm file.txt"
  "0|cat .env.example"
  "0|env NODE_ENV=test npm test"
  "0|grep -r process.env src"
  "0|make test"
)

# Host CLI cases only when the adapter blocks one.
if jq -e '.deploy.blockedCommands | length > 0' "$cfg" >/dev/null 2>&1; then
  cases+=("2|$blk deploy --prod" "2|npx $blk --prod" "2|npx $blk@latest deploy")
fi
# Repo cases from the adapter, guard.testCases ("want|command"), for example for guard.allowEnvCommands.
while IFS= read -r c; do [ -n "$c" ] && cases+=("$c"); done < <(jq -r '.guard.testCases // [] | .[]' "$cfg")
# Deploy command cases only when the adapter sets one.
dep=$(jq -r '.deploy.production.command // .deploy.staging.command // empty' "$cfg")
[ -n "$dep" ] && cases+=("2|$dep")

fail=0
for c in "${cases[@]}"; do
  want=${c%%|*}
  cmd=${c#*|}
  jq -n --arg c "$cmd" '{tool_input: {command: $c}}' |
    CLAUDE_PROJECT_DIR=$root bash "$root/.claude/hooks/guard.sh" >/dev/null 2>&1
  got=$?
  if [ "$got" = "$want" ]; then
    echo "ok   $want  $cmd"
  else
    echo "FAIL want $want got $got  $cmd"
    fail=1
  fi
done
exit $fail
