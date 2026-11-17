#!/usr/bin/env bash
# PreToolUse (Bash): block actions that only the repo owner may take, in any spelling.
# Deny rules in settings.json match command text, so `git -C dir push origin <branch>`
# or `git checkout .` get past them. This hook parses each subcommand instead.
#
# Blocked:
#   - force push, push or delete of a protected branch, remote branch delete
#   - git branch -D, or a delete of a protected branch
#   - reset --hard, clean -f, checkout or restore of the whole tree
#   - merge while on the production branch, gh pr merge, merge calls to the GitHub API
#   - gh api DELETE, and writes to branch protection or rulesets
#   - rm -r outside the repo, of the repo itself, of .git, or of a path the hook cannot read
#   - commands that name .env files (not .env.example) or credential folders; printenv; bare env
#   - host deploy CLIs (deploy.blockedCommands) and the deploy command (deploy.<env>.command)
#
# Exit 2 blocks the call and sends the reason to Claude. Exit 0 lets the deny rules decide.
# Limits: it reads words split on spaces. Text in quotes is data, so a quoted refspec is
# not parsed. A commit message that names a .env file is blocked: rephrase it.
source "$(dirname "$0")/lib.sh"

input=$(cat)
cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
[ -n "$cmd" ] || exit 0

root=$(pwd -P)
cur_dir=$(jq -r '.cwd // empty' <<<"$input")
[ -n "$cur_dir" ] && [ -d "$cur_dir" ] && cur_dir=$(cd "$cur_dir" && pwd -P) || cur_dir=$root

integration=$(wf '.branches.integration')
production=$(wf '.branches.production')
deploy_cmds=$(jq -r '[.deploy.staging.command, .deploy.production.command] | .[] | select(. != null and . != "")' .claude/workflow.json 2>/dev/null)
blocked_cmds=$(jq -r '.deploy.blockedCommands // [] | .[]' .claude/workflow.json 2>/dev/null)
protected=" $integration $production "
QUOTED=__QUOTED__

seg=$cmd
block() { fail "guard hook: blocked \"$seg\". $1 Ask the repo owner to do this."; }

is_protected_ref() {
  local ref=${1#refs/heads/}
  [ -n "$ref" ] && [[ "$protected" == *" $ref "* ]]
}

current_branch() { git -C "${git_dir:-.}" branch --show-current 2>/dev/null; }

# Normalize an absolute path: drop "." and empty parts, resolve "..". The path need not exist.
norm() {
  local IFS=/ part
  local -a parts stack=()
  read -ra parts <<<"$1"
  for part in "${parts[@]}"; do
    case "$part" in
      "" | .) ;;
      ..) stack=("${stack[@]:0:${#stack[@]}-1}") ;;
      *) stack+=("$part") ;;
    esac
  done
  echo "/${stack[*]}"
}

# Absolute path of a word, from the folder the command runs in.
abs_path() {
  local t=$1 p parent
  case "$t" in
    '~' | '~/'*) t="$HOME${t#\~}" ;;
    /*) ;;
    *) t="$cur_dir/$t" ;;
  esac
  p=$(norm "$t")
  # Follow links in the parent folder when it exists (/tmp is /private/tmp on macOS).
  parent=${p%/*}
  [ -n "$parent" ] || parent=/
  if [ -d "$parent" ]; then
    parent=$(cd "$parent" && pwd -P)
    p="${parent%/}/${p##*/}"
  fi
  echo "$p"
}

check_git() {
  # $@ = words after "git"
  git_dir=.
  while [ $# -gt 0 ]; do
    case "$1" in
      -C) git_dir=$2; shift 2 ;;
      -c | --git-dir | --work-tree | --namespace) shift 2 ;;
      -*) shift ;;
      *) break ;;
    esac
  done
  local sub=$1
  shift || true
  case "$sub" in
    push)
      local refspecs=() a
      local skip_next=0
      for a in "$@"; do
        if [ "$skip_next" = 1 ]; then skip_next=0; continue; fi
        case "$a" in
          -f | --force | --force-with-lease* | --force-if-includes | --mirror) block "Force push rewrites history." ;;
          -d | --delete) block "Deleting a remote branch is not allowed." ;;
          --all | --branches) block "Pushing all branches includes protected ones." ;;
          -o | --push-option | --repo | --receive-pack | --exec) skip_next=1 ;;
          -*) ;;
          *) refspecs+=("$a") ;;
        esac
      done
      # The first word is the remote. With no refspec, git pushes the current branch.
      if [ "${#refspecs[@]}" -le 1 ]; then
        is_protected_ref "$(current_branch)" && block "This pushes the current protected branch."
        return 0
      fi
      local r
      for r in "${refspecs[@]:1}"; do
        case "$r" in
          +*) block "A + refspec is a force push." ;;
          :*) block "An empty source deletes the remote branch." ;;
        esac
        local dst=${r##*:}
        [ "$dst" = HEAD ] && dst=$(current_branch)
        is_protected_ref "$dst" && block "Pushes to $integration and $production go through a PR."
      done
      ;;
    branch)
      local del=0 force=0 names=() a
      for a in "$@"; do
        case "$a" in
          -D) del=1; force=1 ;;
          -d | --delete) del=1 ;;
          -f | --force) force=1 ;;
          -*) ;;
          *) names+=("$a") ;;
        esac
      done
      if [ "$del" = 1 ]; then
        [ "$force" = 1 ] && block "A forced branch delete loses work that is not merged."
        local n
        for n in "${names[@]}"; do
          is_protected_ref "$n" && block "$integration and $production are never deleted."
        done
      fi
      ;;
    reset)
      [[ " $* " == *" --hard "* ]] && block "reset --hard discards work."
      ;;
    clean)
      local a
      for a in "$@"; do
        case "$a" in
          --force) block "clean -f deletes untracked files." ;;
          --*) ;;
          -*f*) block "clean -f deletes untracked files." ;;
        esac
      done
      ;;
    checkout | restore)
      [[ " $* " == *" . "* || " $* " == *" :/ "* ]] && block "This discards every change in the tree."
      [ "$sub" = checkout ] && [[ " $* " == *" -- "* ]] && block "checkout -- <path> discards changes."
      ;;
    merge)
      [ "$(current_branch)" = "$production" ] && block "Merges into $production go through the release PR."
      ;;
  esac
  return 0
}

check_gh_api() {
  # $@ = words after "gh api"
  local method="" path="" fields=0 a
  local re_merge='/pulls/[^/]+/merge$' re_merges='/merges$'
  while [ $# -gt 0 ]; do
    a=$1
    shift
    case "$a" in
      -X | --method) method=${1:-}; shift || true ;;
      --method=*) method=${a#--method=} ;;
      -X*) method=${a#-X} ;;
      -f | -F | --field | --raw-field | --input) fields=1; shift || true ;;
      --field=* | --raw-field=* | --input=* | -f* | -F*) fields=1 ;;
      -H | --header | -q | --jq | -t | --template | --hostname | --cache | -p | --preview) shift || true ;;
      -*) ;;
      *) [ -n "$path" ] || path=$a ;;
    esac
  done
  method=$(printf '%s' "$method" | tr '[:lower:]' '[:upper:]')
  # gh api sends POST when fields are given and no method is set.
  [ -n "$method" ] || { [ "$fields" = 1 ] && method=POST || method=GET; }
  [ "$method" = DELETE ] && block "DELETE calls to the GitHub API are not allowed."
  [ "$method" = GET ] && return 0
  [[ "$path" =~ $re_merge || "$path" =~ $re_merges ]] && block "CI merges PRs into $integration. The repo owner merges the release PR."
  [[ "$path" == *protection* || "$path" == *rulesets* ]] && block "Branch protection and rulesets belong to the repo owner."
  return 0
}

check_gh() {
  local sub="$1 ${2:-}"
  [ "$sub" = "pr merge" ] && block "CI merges PRs into $integration. The repo owner merges the release PR."
  [ "$1" = api ] && check_gh_api "${@:2}"
  return 0
}

check_rm() {
  # $@ = words after "rm"
  local recursive=0 targets=() a opts_done=0
  for a in "$@"; do
    if [ "$opts_done" = 0 ]; then
      case "$a" in
        --) opts_done=1; continue ;;
        --recursive) recursive=1; continue ;;
        --*) continue ;;
        -*) [[ "$a" == *[rR]* ]] && recursive=1; continue ;;
      esac
    fi
    targets+=("$a")
  done
  [ "$recursive" = 1 ] || return 0
  [ ${#targets[@]} -gt 0 ] || block "rm -r needs a target the hook can read. Quoted or piped targets are not checked."
  local t p prefix
  for t in "${targets[@]}"; do
    case "$t" in
      *'$'* | *'`'* | *"$QUOTED"*) block "rm -r of a variable or a quoted path. The hook cannot check where it points." ;;
    esac
    # A glob deletes inside its folder. Check that folder: "dist/*" -> dist, "*" -> the current folder.
    prefix=${t%%[*?[]*}
    if [ "$prefix" != "$t" ]; then
      case "$prefix" in
        */*) t=${prefix%/*}; [ -n "$t" ] || t=/ ;;
        *) t=. ;;
      esac
    fi
    p=$(abs_path "$t")
    if [ "$p" = "$root" ] || [[ "$p" != "$root"/* ]]; then
      block "rm -r outside the repo, or of the repo itself, is not allowed ($p)."
    fi
    [[ "$p" == "$root/.git" || "$p" == "$root/.git/"* ]] && block "rm -r of .git destroys the history."
  done
  return 0
}

# Heredoc bodies are data: keep the line with <<WORD, drop the lines up to WORD.
no_heredoc=$(printf '%s\n' "$cmd" | awk '
  term != "" { if ($0 ~ "^[ \t]*" term "[ \t]*$") term = ""; next }
  { print }
  match($0, /<<-?[ \t]*["\047]?[A-Za-z_][A-Za-z0-9_]*/) {
    t = substr($0, RSTART, RLENGTH); gsub(/<<-?[ \t]*["\047]?/, "", t); term = t
  }')

# Secrets: any mention of a .env file or a credential folder, quoted or not.
env_files=$(printf '%s\n' "$no_heredoc" |
  grep -oE '(^|[^A-Za-z0-9_.-])\.env(\.[A-Za-z0-9_-]+)*([^A-Za-z0-9_.-]|$)' |
  sed -E 's/^[^.]//; s/[^A-Za-z0-9_.-]$//' | grep -vxE '\.env\.example' || true)
[ -z "$env_files" ] || block "It names a .env file. Secret values stay with the owner. Use .env.example for names."
if printf '%s\n' "$no_heredoc" | grep -qE '(^|[^A-Za-z0-9_-])(\.ssh|\.aws|\.gnupg|\.config/gh|\.netrc|\.npmrc)([/[:space:]"'"'"']|$)'; then
  block "It names a credential folder or file."
fi

# Text in quotes is data (a grep pattern, a commit message), so it becomes one placeholder
# word before the split. Text run by bash -c, sh -c or eval is code, so it is checked as extra lines.
inner=""
rest=$cmd
re_dq='(-c|eval)[[:space:]]+"([^"]*)"'
re_sq="(-c|eval)[[:space:]]+'([^']*)'"
while [[ "$rest" =~ $re_dq ]] || [[ "$rest" =~ $re_sq ]]; do
  inner+=$'\n'"${BASH_REMATCH[2]}"
  rest=${rest/"${BASH_REMATCH[0]}"/}
done
unquoted=$(printf '%s\n' "$no_heredoc" | sed -E "s/'[^']*'/$QUOTED/g; s/\"[^\"]*\"/$QUOTED/g")

# Split into subcommands on && || ; | & newlines, subshells and command substitution.
segments=$(printf '%s\n%s\n' "$unquoted" "$inner" | awk '{ gsub(/&&|\|\||;|\||&|\$\(|`|\(|\)/, "\n"); print }')

while IFS= read -r seg; do
  seg="${seg#"${seg%%[![:space:]]*}"}"
  read -ra w <<<"$seg"
  [ ${#w[@]} -gt 0 ] || continue
  # Bare env (with only options or assignments) prints every variable.
  if [ "${w[0]}" = env ]; then
    only_opts=1
    for a in "${w[@]:1}"; do [[ "$a" == -* || "$a" == *=* ]] || only_opts=0; done
    [ "$only_opts" = 1 ] && block "It prints every environment variable, secrets included."
  fi
  # Drop leading VAR=value assignments and wrappers the deny rules also strip.
  while [ ${#w[@]} -gt 0 ]; do
    case "${w[0]}" in
      *=*) w=("${w[@]:1}") ;;
      timeout)
        # timeout [-options] DURATION command
        w=("${w[@]:1}")
        while [ ${#w[@]} -gt 0 ] && [[ "${w[0]}" == -* ]]; do w=("${w[@]:1}"); done
        w=("${w[@]:1}")
        ;;
      time | nice | nohup | stdbuf | command | builtin | noglob | xargs | env | sudo) w=("${w[@]:1}") ;;
      *) break ;;
    esac
  done
  [ ${#w[@]} -gt 0 ] || continue
  case "${w[0]}" in
    git) check_git "${w[@]:1}" ;;
    gh) check_gh "${w[@]:1}" ;;
    rm) check_rm "${w[@]:1}" ;;
    printenv) block "It prints environment variables, secrets included." ;;
    cd)
      # Track the folder for later rm checks. An unknown folder makes every relative rm -r fail.
      d=${w[1]:-$HOME}
      case "$d" in
        *'$'* | *'`'* | *"$QUOTED"* | -) cur_dir=/unknown-folder ;;
        *) cur_dir=$(abs_path "$d") ;;
      esac
      ;;
  esac
  # deploy.blockedCommands: host CLIs that deploy by hand.
  words=" ${w[*]} "
  while IFS= read -r b; do
    [ -n "$b" ] || continue
    if [[ "$words" == " $b "* || "$words" == " npx $b "* || "$words" == " npx $b@"* ]]; then
      block "Deploys use the deploy method in .claude/workflow.json, not a CLI by hand."
    fi
  done <<<"$blocked_cmds"
  while IFS= read -r d; do
    [ -n "$d" ] && [[ "$seg" == *"$d"* ]] && block "A person runs the deploy command, never Claude."
  done <<<"$deploy_cmds"
done <<<"$segments"

exit 0
