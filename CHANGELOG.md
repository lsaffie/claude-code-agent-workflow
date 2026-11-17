# Changelog

## v0.1.0 (2026-11-17)

First version.

- Rule files: global and project `CLAUDE.md` examples, `settings.json` and `workflow.json` examples.
- Hooks: `guard.sh`, `post-edit.sh` (format, lint, related tests), `stop.sh` (loop guard after 3 blocks), `lib.sh`.
- Guard tests: `scripts/workflow/guard.test.sh`.
- GitHub Actions examples: CI with a second AI review, autofix (3 attempts) and optional auto-merge; release PR; release tag; smoke test.
- PR template and change explainer template.
- README with a 25-point audit checklist, and `docs/flow.md`.
