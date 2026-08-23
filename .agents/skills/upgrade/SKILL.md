---
name: upgrade
description: Select, apply, review, and merge routine dependency upgrades for this repository. Use only when explicitly invoked as $upgrade.
---

# Upgrade

Deliver the safe routine dependency upgrades available now as one merged pull request without asking the user to choose versions or separately approve the commit, pull request, or merge.

## Contract

- An explicit `$upgrade` invocation authorizes version selection, edits to the managed version sources, package and plugin installation, commits, a pull request, and merge after the gates below pass. Do not request intermediate approval.
- Keep the delivery to one dedicated clean worktree, one `chore/` branch from the latest default branch, and one pull request. Never absorb unrelated changes from the invoking checkout.
- Claude Code remains a managed dependency. Invoke `claude` only to inspect or install Claude Code itself and to reconcile its declared plugins; never invoke it with a prompt or use it as an agent, judge, reviewer, or workflow host.
- Do not change dependency membership, the excluded pins below, GitHub repository settings, or unrelated files. Do not merge through a failing or unresolved gate.

## Managed upgrades

The routine workflow may edit only:

- `config/claude/version` — Claude Code
- `config/ntn/version` — Notion CLI
- `config/codex/version` — Codex CLI
- `config/sheldon/plugins.toml` — remote Sheldon `tag` and `rev` values
- `config/uv/tools.txt` — pinned `@tag` and `@commit` requirements

`config/fnm/version` and `config/uv/config-tools.txt` are outside this workflow. Homebrew entries and Claude Code plugins declare membership rather than versions; their available updates are applied as complete groups without editing their declaration files. Preflight every outdated member because the apply step cannot hold one unsafe member of either group. The user-owned `agent-sentinel` and `claude-sessions` requirements intentionally track HEAD, and routine upgrade does not advance an unchanged HEAD requirement. Refresh `agent-sentinel` through its separate workflow and leave `claude-sessions` unchanged.

## Select versions

Investigate independent sources in parallel. Use authoritative registries and upstream releases for the latest stable versions, then read the changelog, security notices, and current incident reports that could affect the surfaces used here.

- Take security fixes.
- Take the latest stable feature and maintenance release unless documented breaking behavior or multiple current reports establish a critical regression in a surface this repository uses.
- Judge Claude Code against its installer, settings, hooks, plugins, agents, skills, and keybindings. Judge Codex against its npm install, `config.toml`, `AGENTS.md`, hooks, rules, and skills. Judge ntn against its npm install, authentication, and `ntn api` surface.
- Keep a remote Sheldon plugin on a tag when tags exist and on a revision otherwise. Keep ordinary uv tools pinned to a tag or commit.
- Hold only the affected pinned dependency when evidence makes its latest release unsafe or incompatible; continue with the other safe pinned upgrades and record the hold in the pull request. If any outdated Homebrew entry or declared Claude Code plugin is unsafe, stop before applying anything because those unpinned groups cannot be updated selectively.

## Deliver

1. Resolve the repository, its latest default branch, authentication, and the exact current version sources. Start the dedicated branch from the fetched default-branch revision. Stop before mutation if a clean isolated worktree cannot be established.
2. Investigate and select versions under the policy above. Complete the atomic Homebrew and Claude Code plugin preflight, then write every selected pin before applying upgrades.
3. Run `make upgrade-apply`. It updates Homebrew, installs the declared pins, reconciles and updates Claude Code plugins, and intentionally does not run config sync. Diagnose a failure and repair it only within this workflow's scope; otherwise stop without committing.
4. Run `make test`. Inspect the complete diff and verify that only the managed version sources changed. If no repository file changed, report the applied unpinned updates and finish without creating an empty pull request.
5. Run `./scripts/commit-upgrade.zsh prepare`, inspect its staged diff, and run `./scripts/commit-upgrade.zsh commit` without requesting approval. The script is the authority for the allowed commit paths and message.
6. Push the branch and create a pull request titled `chore: 管理対象の依存関係を更新`. Write its description in Japanese with the selected versions, held dependencies and evidence, unpinned updates applied at runtime, and verification results.
7. Review the exact pull-request head against its current base without modifying code during the review. Repair material findings, rerun the apply and test gates as relevant, push, and review again whenever the head or base revision changes.
8. Wait for every repository-required machine gate reported for the pull request. If the base advances, update the branch and repeat the affected verification and review. Once the current revisions are reviewed and all gates pass, squash-merge with remote-branch deletion without asking again.
9. Verify the pull request is merged into the default branch, then follow repository policy for local branch and worktree cleanup. Report the merged pull request, versions selected or held, verification, and any unpinned updates.

## Stop conditions

Stop with the preserved branch, pull request when one exists, evidence, and the exact next action only when progress requires new authority or unsafe guessing: authentication or permission failure, an unsafe member of an atomic unpinned update group, an unresolved install or test failure, an ambiguous compatibility decision that cannot be settled from repository and upstream evidence, a merge conflict without a behavior-preserving resolution, or a required external human gate. A held pinned dependency does not block safe independent pinned upgrades.
