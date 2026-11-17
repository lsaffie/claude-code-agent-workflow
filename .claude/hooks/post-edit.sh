#!/usr/bin/env bash
# PostToolUse (Write|Edit): fix and check the one file that changed.
# 1. commands.formatFile, for files in files.formatExtensions. With
#    files.formatNewFilesOnly, only for files that are new on this branch.
# 2. commands.lintFixFile, for files in files.lintExtensions.
# 3. commands.lintCheckFile. When it fails, exit 2 with commands.lintShowFile output.
# 4. commands.relatedTests, for files that match files.relatedTestsPattern.
#    When they fail, exit 2. A red test that Claude just wrote is expected in
#    test-first work, and the message says so.
# PostToolUse cannot undo the edit. Exit 2 sends the message to Claude.
source "$(dirname "$0")/lib.sh"

file=$(jq -r '.tool_input.file_path // empty')
[ -n "$file" ] && [ -f "$file" ] || exit 0
rel=${file#"$PWD"/}
[ "$rel" != "$file" ] || exit 0 # outside the project

ignore=$(wf '.files.ignoreEdits')
[ -n "$ignore" ] && [[ "$rel" =~ $ignore ]] && exit 0

ext=${rel##*.}
has_ext() {
  jq -e --arg e "$ext" --arg k "$1" '(.files[$k] // []) | index($e) != null' .claude/workflow.json >/dev/null 2>&1
}
is_new() { ! git cat-file -e "$(base_ref):$rel" 2>/dev/null; }

if has_ext formatExtensions; then
  if [ "$(wf '.files.formatNewFilesOnly')" != true ] || is_new; then
    run formatFile "$rel" >/dev/null 2>&1 || true
  fi
fi

if has_ext lintExtensions; then
  run lintFixFile "$rel" >/dev/null 2>&1 || true
  if ! out=$(run lintCheckFile "$rel" 2>&1); then
    details=$(run lintShowFile "$rel" 2>&1 | head -40)
    fail "post-edit hook: $rel has lint errors that the fix command could not fix.
$out
$details"
  fi
fi

pattern=$(wf '.files.relatedTestsPattern')
[ -n "$pattern" ] && [[ "$rel" =~ $pattern ]] || exit 0

if ! out=$(run relatedTests "$rel" 2>&1); then
  test_pattern=$(wf '.files.testFilePattern')
  if [ -n "$test_pattern" ] && [[ "$rel" =~ $test_pattern ]] && is_new; then
    fail "post-edit hook: the new test in $rel fails. Red is expected in test-first work: the test fails before the code exists. Now write the smallest code that makes it pass. If you did not expect red, fix the test.
$(echo "$out" | tail -40)"
  fi
  fail "post-edit hook: tests related to $rel fail. Fix the code, not the test, unless the test is wrong.
$(echo "$out" | tail -60)"
fi
exit 0
