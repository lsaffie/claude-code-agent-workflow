# Changelog

## Unreleased

- CI autofix: the checkout no longer saves `GITHUB_TOKEN` for git. The fix push uses the Claude GitHub App token, so CI runs on it without an approval.
- CI review gate fails closed: a PR into staging with no review comment for its head commit fails. The Claude action skips when the workflow differs from the default branch; before, that skip passed as green.

## v0.1.0 (2026-11-17)

First version.

- Rule files: global and project `CLAUDE.md` examples, `settings.json` and `workflow.json` examples.
- Hooks: `guard.sh`, `post-edit.sh` (format, lint, related tests), `stop.sh` (loop guard after 3 blocks), `lib.sh`.
- Guard tests: `scripts/workflow/guard.test.sh`. Adapter keys `guard.allowEnvCommands` and `guard.testCases` for repo-specific exceptions and their tests.
- GitHub Actions examples: CI with a second AI review, autofix (3 attempts) and optional auto-merge; release PR; release tag; smoke test.
- PR template and change explainer template.
- Quick start: ignore `.claude/worktrees/` in git, the linter and the type checker.
- README with a 25-point audit checklist, and `docs/flow.md`.
