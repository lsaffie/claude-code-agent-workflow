# Shared helpers for the Claude Code hooks. Source it; do not run it.
# Each hook exits 2 and writes to stderr on failure, so Claude goes back and fixes the problem.
# Repo-specific values come from the adapter, .claude/workflow.json. Nothing here names a repo.

cd "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}" || exit 0

# Read one value from the adapter. Prints nothing when the value is unset, null or false.
wf() {
  jq -r "$1 // empty" .claude/workflow.json 2>/dev/null
}

# Run commands.<name> from the adapter (see scripts/workflow/run.sh).
run() {
  bash scripts/workflow/run.sh "$@"
}

# The branch the PR goes into. Fall back to the production branch when the
# integration branch is not fetched.
base_ref() {
  local integration production
  integration=$(wf '.branches.integration')
  production=$(wf '.branches.production')
  if git rev-parse --verify -q "origin/$integration" >/dev/null; then
    echo "origin/$integration"
  else
    echo "${production:-HEAD}"
  fi
}

# Files changed on this branch plus uncommitted and untracked files, one per line.
changed_files() {
  local base
  base=$(git merge-base "$(base_ref)" HEAD 2>/dev/null || echo HEAD)
  { git diff --name-only "$base"...HEAD 2>/dev/null
    git diff --name-only HEAD 2>/dev/null
    git ls-files --others --exclude-standard 2>/dev/null
  } | sort -u | while read -r f; do [ -f "$f" ] && echo "$f"; done
}

fail() {
  echo "$1" >&2
  exit 2
}
