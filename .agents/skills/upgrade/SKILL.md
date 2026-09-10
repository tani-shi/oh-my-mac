---
name: upgrade
description: Research pinned dependency updates and create a pull request for this repository. Use only when explicitly invoked as $upgrade.
---

# Upgrade

Create one reviewed pull request updating the repository's pinned dependencies. The user reviews and merges it, then applies the merged checkout with `make update`.

## Scope

An explicit `$upgrade` invocation authorizes version research, edits to the sources below, a commit, push, and pull request creation. The workflow changes repository declarations only; package installation, configuration sync, and merge are outside its scope.

| Source | Allowed changes |
| --- | --- |
| `config/claude/version` | Claude Code version |
| `config/ntn/version` | Notion CLI version |
| `config/sheldon/plugins.toml` | Existing remote plugin `tag` and `rev` values |
| `config/uv/tools.txt` | Existing pinned `@tag` and `@commit` requirements |

Keep dependency membership unchanged. Node, Codex CLI, the config-tools environment, HEAD-tracking uv requirements, Homebrew packages, and Claude Code plugins are outside this workflow. Claude Code is a dependency to assess, not an agent, judge, or workflow host.

## Version selection

Use authoritative registries and upstream releases to find the latest stable versions. Check release notes, security notices, and reported regressions against the behavior used here, including Claude's settings, hooks, plugins and keybindings, and ntn's authentication and API commands. Prefer security fixes and stable updates; leave a pin unchanged when compatibility is uncertain or a relevant regression is documented, and report the reason.

Keep Sheldon plugins on tags when available and revisions otherwise. Keep pinned uv tools on tags or commits.

## Delivery

- Work in one dedicated clean worktree on a `chore/` branch from the latest fetched default branch. Preserve unrelated work in the invoking checkout. If an isolated worktree cannot be prepared, report the blocker before editing.
- Update only the allowed declarations. Validate their syntax and the selected versions against upstream evidence, then review the complete diff against the base branch and fix material findings. Verification is limited to declarations and source evidence; report that the updates have not been installed locally.
- If no declaration changes, report the outcome without creating a commit or pull request.
- Stage the changed source files explicitly, inspect the staged diff, and commit with ordinary Git commands. Push and create one pull request with a conventional Japanese title and a concise Japanese description covering the updates, supporting sources, skipped updates when relevant, and verification.
- Return the pull request URL and finish. Leave the branch available for human review and merge.
