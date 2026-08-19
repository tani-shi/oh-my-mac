---
name: deliver-change
description: Deliver one requested code change by creating a separate Codex GUI implementation task, supervising its pull request and revisions, and merging it when no repository gate requires outstanding human action. Stop with a merge-ready pull request when human approval or discussion is required. Use only when explicitly invoked as $deliver-change with an issue reference or plain-language objective. Every invocation starts a new delivery and requires an objective.
---

# Deliver Change

Run one change from implementation through merge in the invoking Codex GUI task. Treat the invoking task as the code-read-only supervisor and create one user-visible implementation task in a dedicated worktree. Keep GitHub review communication human-authored.

## Preflight

Before creating external state:

1. Require an objective on every invocation. Do not resume or adopt a delivery from an earlier invocation.
2. Require the Codex GUI capabilities for projects and tasks and a saved Git project. Run authenticated `gh` preflight commands with sandbox escalation and establish GitHub access and repository authority from the completed preflight. Merge authority may remain unavailable when the delivery can still produce a pull request.
3. Treat explicit invocation as authorization to create one implementation task and pull request and to merge when the repository exposes no outstanding human-controlled gate.
4. Inspect applicable repository instructions and its test, documentation, pull request, merge, cleanup, and deployment conventions.

## Resolve the objective

Accept a plain-language request, pasted requirements, a repository document, or a GitHub issue. When an issue is referenced, read its title, body, acceptance criteria, and relevant discussion; additional user text overrides it. Ask only when a missing decision would materially change public behavior, data, security, or scope.

## Create the implementation task

1. Use `list_projects` to identify the saved project for the invoking repository.
2. Call `create_thread` for that project with a worktree environment and no `startingState`, model, or reasoning override. Use a concise title derived from the objective and repository conventions.
3. If creation returns only a pending client ID, find the ready task by project and title. Never create a replacement merely because setup or progress is slow.
4. Give the implementation task this contract, adapted to the objective and repository:

```text
Implement the supplied objective in this dedicated worktree.

Follow every applicable repository instruction. Fetch the remote default branch
and start from its latest commit. Implement the complete change, add or update
tests, and update documentation when required. Run all relevant verification,
commit the related changes together, push one repository-conforming branch, and
create a pull request.

Do not merge or submit, reply to, or resolve GitHub review comments. Report the
PR URL and number, base and remote branches, head SHA, implementation summary,
and verification results. Remain available for private review follow-ups.
```

## Supervise implementation and review

1. Wait on the implementation task with `wait_threads`, reusing its latest cursor. Treat timeouts as normal and continue while work can progress safely.
2. Answer ordinary in-scope implementation questions from repository evidence with `send_message_to_thread`. Escalate only decisions that require new authority or materially change the requested result.
3. If the task stops before opening a pull request, send a focused recovery instruction to the same task and continue waiting.
4. After it reports a pull request, read the current metadata, complete diff, checks, reviews, discussions, conflicts, base branch, and head SHA. Keep the supervisor worktree read-only.
5. Review correctness, regressions, tests, documentation, error handling, compatibility, security boundaries, and integration with the latest base. Omit cosmetic and speculative findings.
6. Send actionable findings privately to the implementation task with evidence and precise locations. Require it to incorporate the latest remote base, address every finding, rerun verification, commit, push the same branch, and report the new SHA. Do not publish Codex-authored GitHub review communication.
7. Review the complete updated pull request after every new SHA. Continue until no actionable finding remains and all required checks pass.

## Merge and finish

1. Immediately before deciding whether to merge, refresh and classify the pull request's current SHA, checks, mergeability, reviews, discussions, branch protection, and repository policy.
2. If the SHA changed, required checks no longer pass, or a conflict makes the branch unmergeable, return to the implementation and review loop until the current revision is fully reviewed and machine-controlled gates pass.
3. If required human approval is missing or an actionable human-owned discussion or policy decision remains, stop successfully with the pull request ready for that action. Report the URL, reviewed SHA, checks, review result, exact human-controlled gates, and any manual verification steps. Leave the implementation task unarchived and its branch intact; do not deploy.
4. If no human-controlled gate remains but merge authority is unavailable or another policy prevents merging, stop as blocked and report the exact limitation.
5. Otherwise follow the repository's merge-method convention. Never bypass protection. Verify the merged state and merge commit instead of inferring success from the merge command.
6. Archive only the implementation task and confirm that it appears in `list_archived_threads`. Retry one archival request after a bounded wait, then report a persistent failure.
7. Delete the merged remote branch when repository policy permits it. Delete a same-named local branch only when no worktree uses it, then prune stale tracking refs.
8. When the repository defines automatic deployment, wait for the merged revision and run its documented non-destructive production checks. Confirm the deployed commit or version when exposed. Otherwise report deployment verification as not applicable or unavailable with the concrete reason.
9. Report the objective, pull request, reviewed and merge SHAs, implementation and verification, revision rounds, deployment result, task archival, branch cleanup, and any unresolved operational issue.

If progress becomes impossible, stop that invocation and report the implementation task ID, pull request, branch, head SHA, evidence, and remaining work. A later `$deliver-change <objective>` invocation is a new delivery, not an implicit recovery attempt.

Do not edit or commit from the supervisor worktree, merge an unreviewed SHA, create more than one implementation task, publish Codex-authored GitHub review communication, or merge while a human-controlled gate remains.
