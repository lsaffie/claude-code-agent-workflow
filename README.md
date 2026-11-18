# Claude Code agent workflow

**Clone this repo, then adapt it: copy the files into your repo, fill in .claude/workflow.json from the example, and add your secrets.**

A spec goes in and pull requests come out. You ask questions until the spec is clear, and the spec becomes a GitHub issue. Agents split it into tickets, then build, test and review each ticket as a PR. CI merges the green PRs into staging. A person reads the release PR, tries staging and releases to production. Hooks on your machine and jobs in GitHub Actions block the actions that only a person may take. Read the full flow in [docs/flow.md](docs/flow.md).

## What is inside

| Path | What it does |
|---|---|
| `CLAUDE.md.example` | Global rules for the agent. Copy to `~/.claude/CLAUDE.md` |
| `CLAUDE.project.md.example` | Project rules. Copy to `CLAUDE.md` in your repo |
| `.claude/settings.json.example` | Deny rules, hook wiring, sandbox paths and hosts |
| `.claude/workflow.json.example` | The adapter: branches, commands, deploy, smoke checks, paths. Everything specific to your repo |
| `.claude/hooks/guard.sh` | Before each shell command: blocks force push, pushes to protected branches, `reset --hard`, branch deletes, `rm -r` outside the repo, merges, branch protection changes, secret reads |
| `.claude/hooks/post-edit.sh` | After each edit: format, lint, then the tests related to the file |
| `.claude/hooks/stop.sh` | Before the agent stops: lint, types, unit tests, explainer check. Gives up after 3 blocks |
| `.claude/hooks/lib.sh` | Shared helpers. `fail()` exits 2, which sends the message back to the agent |
| `scripts/workflow/` | `run.sh` runs adapter commands. `guard.test.sh` tests the guard. Explainer, release PR, smoke, tag and merge-commit scripts |
| `.github/workflows/*.yml.example` | CI with AI review, autofix and optional auto-merge; release PR; release tag; smoke test |
| `.github/pull_request_template.md` | Summary, Changes, Proof, Decisions, Risks, Explainer |
| `docs/changes/TEMPLATE.md` | The per-PR explainer: paragraph, diagram, files, risks, 3 questions |

Hooks and scripts need `bash` (3.2 or later), `git`, `jq`, `curl` and `gh`.

## Quick start

1. Clone this repo next to your project.
2. Copy `.claude/`, `scripts/workflow/`, `.github/` and `docs/changes/` into your repo.
3. Copy `.claude/workflow.json.example` to `.claude/workflow.json`. Set `repo`, the branch names, your commands, your smoke URLs and checks.
4. Copy `.claude/settings.json.example` to `.claude/settings.json`. Change `main` and `staging` in the deny rules if your branches differ. Add the hosts your tools need.
5. Copy `CLAUDE.project.md.example` to `CLAUDE.md` and fill it in. Copy `CLAUDE.md.example` to `~/.claude/CLAUDE.md`, or merge it into yours.
6. Copy each `.github/workflows/*.yml.example` to `*.yml`. Change the branch names in `on:` and `if:` if yours differ.
7. Add the secrets in GitHub (Settings > Secrets and variables > Actions): `ANTHROPIC_API_KEY` or `CLAUDE_CODE_OAUTH_TOKEN`, and `RELEASE_PR_TOKEN`. Install the Claude GitHub App on the repo (`/install-github-app` in Claude Code). The review and autofix jobs use its token, so the autofix push starts CI.
8. Create the labels `claude-review-blocking` and `no-auto-merge`.
9. Add `/.claude/worktrees/` to `.gitignore`, and to your linter's and type checker's ignores. Claude Code puts worktrees there. Without the ignore, the main checkout's hooks check every worktree file as new code.
10. Run `bash scripts/workflow/guard.test.sh`. Every line must start with `ok`.
11. Put the workflow files on the default branch first. The Claude action skips on a PR whose workflow differs from the default branch, and the review gate then fails that PR. The same holds after every CI change: release it before you trust a review. Then open a test PR into `staging`. When CI and the review behave as you expect, set the repository variable `AUTO_MERGE_ENABLED` to `true`.

In your user settings (`~/.claude/settings.json`), set `permissions.defaultMode` to `auto` and `sandbox.network.strictAllowlist` to `true`. Project settings cannot set them.

## Audit checklist

Answer each line yes or no. A "no" is a gap between your setup and this one.

### Plan

1. Does `CLAUDE.md` hold only the rules the agent cannot infer from the code, in about 100 lines or fewer?
2. Does each feature start with questions, and end as a spec in a GitHub issue?
3. Is each spec split into ticket issues labelled "ready for agent", one PR each?
4. Are the critical flows ranked in a file, with a current system map (architecture, data model, flows)?

### Build

5. Does the agent work on a feature branch and open a PR into the integration branch?
6. Does the agent write a failing test before the implementation, and a test that shows each bug before the fix?
7. Does the agent run in auto mode, with the trust boundary written in plain words in user settings?
8. Does a hook format and lint each edited file, then run its related tests, and send failures back to the agent?
9. Does a Stop hook run lint, types, unit tests and the explainer check, and give up after 3 blocks with a report?

### Verify

10. Does CI run lint, types, unit tests, build and end-to-end tests on every PR?
11. Does each critical flow have an end-to-end test that is green in CI?
12. Do your important tests fail when you break their code on purpose?
13. Does a coverage gate stop coverage from going down?
14. Does a second AI review check each PR diff against its linked spec or ticket, and block on gaps?
15. Does an autofix job push fixes for red PRs, stop after 3 attempts, and ask a person?
16. Does each PR have the template sections and an explainer with a "what changed and why" paragraph, a diagram and 3 questions, checked by CI?

### Release

17. Do only green, reviewed PRs merge into the integration branch, with a smoke test after each staging deploy?
18. Is there one release PR from the integration branch to production that collects the changes and the explainers?
19. Does a person approve and merge the release PR with a merge commit, and does CI flag any other merge method?
20. Does each production release get a tag, a GitHub Release and a smoke test, and is there a written rollback guide with expand-then-contract schema changes?

### Safety

21. Do deny rules block reads of `.env` files and credential folders, and the git and gh actions that only a person may take?
22. Does a guard hook block those actions in any spelling (`git -C`, `bash -c`, `eval`), with tests that run in CI?
23. Does the guard block `rm -r` outside the repo, branch deletes, release PR merges and branch protection changes?
24. Is the sandbox on, with credential folders denied and only the needed network hosts allowed?
25. Does GitHub branch protection (or a ruleset) require a PR and green checks on both protected branches, or does an ADR accept the risk?

## Credits

- [Claude Code docs](https://code.claude.com/docs): hooks, settings, sandbox and GitHub Actions.
- [Matt Pocock's skills](https://github.com/mattpocock/skills): the planning and building skills this workflow uses. Install them from his repo.
- AI Engineer talks:
  - Lydia Hallie, "Rethinking Claude Code Best Practices"
  - Lauren Tan, "All Code Is Slop (Except Mine)"
  - Zach Lloyd, "How to Build a Software Factory That Improves Itself"

## About

Built by Luis Saffie. Want this set up at your company? https://lsaffie.com/ai-dev-setup

## License

MIT. See [LICENSE](LICENSE).
