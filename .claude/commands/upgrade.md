---
description: Investigate dependency upgrades, apply the approved ones, and commit
allowed-tools: Read, Glob, Grep, Edit, WebSearch, WebFetch, Bash(brew outdated:*), Bash(npm view:*), Bash(gh api:*), Bash(claude plugin list:*), Bash(git diff:*), Bash(git status:*), Bash(make upgrade-apply), Bash(./scripts/commit-upgrade.zsh:*)
---

Investigate available upgrades for this repository's pinned dependencies, apply
the ones the user approves, and commit the result.

## Scope

Only these upgrade-managed version sources may be edited in this workflow:

- `config/claude/version` — Claude Code
- `config/ntn/version` — Notion CLI (ntn)
- `config/codex/version` — Codex CLI
- `config/sheldon/plugins.toml` — zsh plugins
- `config/uv/tools.txt` — uv tools

`config/fnm/version` and `config/uv/config-tools.txt` also contain pins, but the
routine upgrade workflow does not investigate or change them.

Homebrew formulae and casks carry no pin: `make upgrade-apply` upgrades every
`Brewfile` entry. Report what `brew outdated` lists so the user can decide, but
there is nothing to edit for them.

Claude Code plugins also carry no repository pin. `config/claude/plugins.txt`
declares membership only and must not be edited for a routine plugin update.
Approval of the upgrade plan authorizes `make upgrade-apply` to update every
declared plugin to the latest version available from its marketplace.

## 1. Investigate

Run these in parallel where you can:

1. `brew outdated` — formulae and casks.
2. For each GitHub-sourced plugin in `config/sheldon/plugins.toml`, compare the
   pinned tag with `gh api repos/{owner}/{repo}/tags --jq '.[0].name'`.
3. `npm view @anthropic-ai/claude-code version` — the latest Claude Code.
4. `npm view ntn version` — the latest Notion CLI.
5. `npm view @openai/codex version` — the latest Codex CLI.
6. `config/uv/tools.txt` — tools that carry an `@tag`/`@commit` suffix.
7. `claude plugin list --json` — installed versions of the Claude Code plugins
   declared in `config/claude/plugins.txt`. The CLI resolves their latest
   marketplace versions only when `claude plugin update` runs.
8. Research changelogs, security advisories, and incident reports for every
   candidate.

## 2. Decide

- Apply security patches unconditionally.
- Take feature updates only when changelogs and advisories report no incidents.
- **Claude Code**: track the latest release. Upgrade to it unless either
  (a) the CHANGELOG.md at `anthropics/claude-code` documents breaking changes
  between the current pin and the latest that reach this repo's configuration
  surface (settings.json schema, hooks, slash commands, MCP, plugins, agents,
  skills, keybindings), or (b) GitHub Issues at `anthropics/claude-code` show
  trending critical bug reports against the latest version — multiple distinct
  users reporting the same unresolved regression (crashes, hangs, data loss,
  broken core flows). Stale or single-user reports do not count. On either risk,
  hold the current pin and say why. Release recency is not a criterion.
- **Notion CLI (ntn)**: track the latest release under the same two criteria,
  read against the CLI surface this repo relies on (auth, `ntn api`, global npm
  install).
- **Codex CLI**: track the latest release under the same two criteria, read
  against the surface this repo relies on (`config.toml`, `AGENTS.md` discovery,
  and global npm install).
- **Sheldon plugins**: pin by tag, or by rev when the repository has no tags.
- **uv tools**: pin with an `@tag`/`@commit` suffix, except `agent-sentinel`
  and `claude-sessions`, which the user owns and whose source requirements
  reference HEAD. `make upgrade-apply` does not pass `--upgrade`, so it does not
  advance an existing installation when an unchanged requirement still points
  to HEAD.
  Refresh agent-sentinel separately with `make refresh-agent-sentinel` because
  its generated Claude configuration is part of the repository.
- **Claude Code plugins**: update every declaration in
  `config/claude/plugins.txt`, regardless of whether it is already enabled.
  Record the installed version in the report and describe the latest version as
  resolved at apply time when the marketplace does not expose it beforehand.

## 3. Report and apply

Present the findings as a table — package, current, latest, verdict, reason —
and get the user's approval before editing any pin.

Once approved, write the pins, then run `make upgrade-apply` without asking again.
It trusts the taps, runs `brew bundle`, installs the pinned Claude Code / changed
uv requirements / ntn / codex, reconciles the declared plugin set, and explicitly
updates every declared plugin. It does not run `sync-config`, so an approved
Sheldon reference change reaches the local checkout on the next `make install`
or `make update`. Read its output and stop if any step fails; a plugin update
failure prevents the later tools from being installed.

## 4. Commit

Run `./scripts/commit-upgrade.zsh prepare`. It refuses changes outside the pin
files, stages only those files, and prints the exact `git diff --cached` proposed
for the commit. Show that diff and get the user's approval. Once approved, run
`./scripts/commit-upgrade.zsh commit`, which verifies that the prepared state has
not changed and derives the commit message from the staged pin files. If the user
does not approve the commit, run `./scripts/commit-upgrade.zsh abort` to unstage
the pin files and discard the prepared state while preserving their working-tree
changes.
