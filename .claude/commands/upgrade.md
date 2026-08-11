---
description: Investigate dependency upgrades, apply the approved ones, and commit
allowed-tools: Read, Glob, Grep, Edit, WebSearch, WebFetch, Bash(brew outdated:*), Bash(npm view:*), Bash(gh api:*), Bash(git diff:*), Bash(git status:*), Bash(make upgrade-apply)
---

Investigate available upgrades for this repository's pinned dependencies, apply
the ones the user approves, and commit the result.

## Scope

Only these files record a pinned version, and they are the only files you may edit:

- `config/claude/version` — Claude Code
- `config/ntn/version` — Notion CLI (ntn)
- `config/sheldon/plugins.toml` — zsh plugins
- `config/uv/tools.txt` — uv tools

Homebrew formulae and casks carry no pin: `make upgrade-apply` upgrades every
`Brewfile` entry. Report what `brew outdated` lists so the user can decide, but
there is nothing to edit for them.

## 1. Investigate

Run these in parallel where you can:

1. `brew outdated` — formulae and casks.
2. For each GitHub-sourced plugin in `config/sheldon/plugins.toml`, compare the
   pinned tag with `gh api repos/{owner}/{repo}/tags --jq '.[0].name'`.
3. `npm view @anthropic-ai/claude-code version` — the latest Claude Code.
4. `npm view ntn version` — the latest Notion CLI.
5. `config/uv/tools.txt` — tools that carry an `@tag`/`@commit` suffix.
6. Research changelogs, security advisories, and incident reports for every
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
- **Sheldon plugins**: pin by tag, or by rev when the repository has no tags.
- **uv tools**: pin with an `@tag`/`@commit` suffix, except `claude-sentinel`
  and `claude-sessions`, which the user owns and which track HEAD.

## 3. Report and apply

Present the findings as a table — package, current, latest, verdict, reason —
and get the user's approval before editing any pin.

Once approved, write the pins, then run `make upgrade-apply` without asking again
— it converges on whatever the pins say, so a repeat run costs nothing. It trusts
the taps, runs `brew bundle`, installs the pinned Claude Code / plugins / uv tools
/ ntn, and regenerates `versions.json`. Read its output and report any step that
failed.

## 4. Commit

Show `git diff`, and on the user's approval run `./scripts/commit-upgrade.zsh`,
which derives the commit message from the `versions.json` diff.
