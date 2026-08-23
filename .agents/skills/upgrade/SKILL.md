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

`config/fnm/version` and `config/uv/config-tools.txt` are outside this workflow. Homebrew entries and Claude Code plugins declare membership rather than versions, but the upgrade workflow applies their outdated members selectively without editing the declaration files. The user-owned `agent-sentinel` and `claude-sessions` requirements intentionally track HEAD, and routine upgrade does not advance an unchanged HEAD requirement. Refresh `agent-sentinel` through its separate workflow and leave `claude-sessions` unchanged.

## Select versions

Investigate independent sources in parallel. Use authoritative registries and upstream releases for the latest stable versions, then read the changelog, security notices, and current incident reports that could affect the surfaces used here.

- Take security fixes.
- Take the latest stable feature and maintenance release unless documented breaking behavior or multiple current reports establish a critical regression in a surface this repository uses.
- Judge Claude Code against its installer, settings, hooks, plugins, agents, skills, and keybindings. Judge Codex against its npm install, `config.toml`, `AGENTS.md`, hooks, rules, and skills. Judge ntn against its npm install, authentication, and `ntn api` surface.
- Keep a remote Sheldon plugin on a tag when tags exist and on a revision otherwise. Keep ordinary uv tools pinned to a tag or commit.
- Classify every candidate independently as `upgrade`, `risk-hold`, `incompatibility-hold`, `execution-blocked-hold`, or `unchanged`. A hold affects only that candidate unless it is an unavoidable transitive or shared dependency of another selected upgrade.
- Treat the `chatgpt` cask as independent from the pinned Codex CLI. A risk affecting ChatGPT or the bundled Codex GUI holds only that cask.
- A Codex safeguard, denied command, unavailable write path, or other blocked tool call is not evidence that a candidate is unsafe. Retry through a safer read-only source or authoritative upstream evidence; if the candidate still cannot be assessed, classify only it as `execution-blocked-hold` and continue.
- Hold only the affected candidate when evidence makes its latest release unsafe or incompatible. Holds do not fail review, test, or merge gates when the selected safe changes pass.

## Selective plan

Before mutation, write a temporary tab-separated plan outside the worktree with exactly four non-empty fields per candidate: kind, identifier, decision, and evidence. Use only these kinds:

- `homebrew-formula` and `homebrew-cask`, with the exact `Brewfile` identifier
- `claude-plugin`, with the exact `config/claude/plugins.txt` identifier
- `claude`, `ntn`, and `codex`, each repeating its kind as the identifier
- `uv-tool`, with the exact declaration line from `config/uv/tools.txt`
- `sheldon-plugin`, with the exact section name below `[plugins]`

Include every investigated outdated candidate and every changed pin. Every repository pin changed from `HEAD` must have its matching `upgrade` row; a changed pin cannot be omitted or classified as a hold after mutation. Keep unchanged candidates in the plan when they were materially assessed and belong in the delivery record. The apply script rejects an `upgrade` row for a uv tool whose Git requirement still tracks HEAD, validates every identifier against repository declarations before it executes any selected candidate, and never applies hold or unchanged rows.

## Deliver

1. Resolve the repository, its latest default branch, authentication, and the exact current version sources. Start the dedicated branch from the fetched default-branch revision. Stop before mutation if a clean isolated worktree cannot be established.
2. Investigate and classify candidates under the policy above, write only selected pin changes, and create the selective plan. Before selecting a Homebrew candidate, account for the dependencies its individual upgrade would change; stop if an unavoidable held transitive or shared dependency makes isolation unsafe.
3. Choose temporary paths for both the plan and its result report, then run `make upgrade-apply UPGRADE_PLAN=<plan> UPGRADE_REPORT=<report>`. It validates the complete plan first and applies selected Homebrew formulae and casks, Claude Code plugins, and direct pins one candidate at a time. Sheldon references are reported as `declaration-updated` and remain unapplied locally until the next config sync. The target intentionally does not run config sync, `brew bundle`, blanket plugin reconciliation, or bulk plugin update.
4. If one candidate fails to apply, the apply script compares package-manager state before and after the attempt. An unchanged readable state becomes an `execution-blocked-hold`; any selected direct-version or uv tool pin for that candidate is restored to the current revision before independent candidates continue. An unreadable or changed state, or inability to restore the held pin, is systemic because a partial update cannot be excluded; stop without committing. Diagnose only within this workflow's scope.
5. Run `make test`. Inspect the complete diff, the selective plan, and the result report. Verify that only the managed version sources changed, every selected candidate has a verification result, every hold has evidence, and no held candidate was applied. If no repository file changed, report applied unpinned updates and holds, then finish without creating an empty pull request.
6. Run `./scripts/commit-upgrade.zsh prepare`, inspect its staged diff, and run `./scripts/commit-upgrade.zsh commit` without requesting approval. The script is the authority for the allowed commit paths and message.
7. Push the branch and create a pull request titled `chore: 管理対象の依存関係を更新`. Write its description in Japanese with separate upgraded, risk-held, incompatible, execution-blocked, and unchanged sections, plus evidence, runtime application results, and verification results. A hold is reported, not treated as a failed gate.
8. Review the exact pull-request head against its current base without modifying code during the review. Repair material findings, rerun the selective apply and test gates as relevant, push, and review again whenever the head or base revision changes.
9. Wait for every repository-required machine gate reported for the pull request. If the base advances, update the branch and repeat the affected verification and review. Once the current revisions are reviewed and all gates pass, squash-merge with remote-branch deletion without asking again.
10. Verify the pull request is merged into the default branch, then follow repository policy for local branch and worktree cleanup. Report the merged pull request, candidates upgraded or held by category, verification, and any unpinned updates.

## Stop conditions

Stop with the preserved branch, pull request when one exists, evidence, and the exact next action only when safe isolation is impossible: authentication or permission failure; inability to create the clean worktree; an unavoidable held transitive or shared dependency; unreadable or changed package-manager state after a failed application; a test failure that cannot be isolated to one candidate; an unresolved required review or machine gate; a merge conflict without a behavior-preserving resolution; or a required external human gate. Candidate-specific risk, incompatibility, assessment blockage, or isolated application failure is a hold and does not stop safe independent upgrades.
