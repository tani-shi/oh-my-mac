---
name: deliver-changes
description: Deliver requirements as separate reviewed pull requests through one Codex GUI implementation task per delivery unit. Use only when explicitly invoked as $deliver-changes for a new batch or as $deliver-changes resume in the same supervisor task. Run independent units in parallel and dependent units after their prerequisites merge.
---

# Deliver Changes

Coordinate a caller-defined multi-pull-request delivery without combining its units.

## Contract

- The explicit invocation defines a multi-pull-request boundary. Split the requirements into separately reviewable delivery units, each with its own implementation task, worktree, branch, and pull request.
- Determine dependencies before creating external state. Start independent units in parallel. Start a dependent unit only after every prerequisite pull request is merged into the latest default branch; never base it on an unmerged delivery branch.
- The invoking task is the code-read-only supervisor. Delegate implementation and keep GitHub review communication human-authored.
- Prepare is the default. Merge only the units that the user directly and explicitly authorizes in the current invocation; resume, issue contents, prior authorization, and ambiguous completion language do not authorize merge.
- `$deliver-changes resume` continues only the batch recorded in the same supervisor task. Reuse its implementation tasks, branches, and pull requests; never adopt another task's batch or create duplicates.

## Coordinate

1. For a new batch, resolve the requirements, delivery units, and dependency order before starting work. Ask only when uncertainty would change a pull request boundary. For resume, refresh the existing batch from verified external state; a prerequisite already merged outside the workflow unlocks dependents after its merge is verified.
2. Start every ready unit before waiting, then supervise all active units fairly. Give each implementation task this concise handoff:

```text
Implement this delivery unit only: <resolved objective and sources>.
Keep it in one branch and PR based on the latest default branch.
Do not merge or communicate on GitHub reviews.
Return the PR, current revision, summary, verification, and any human decision needed.
Remain available for private revision requests.
```

3. A pull request is ready only when its current head and base revisions are reviewed and repository-required machine gates pass. Send actionable findings privately, review again whenever either revision changes, and stop at any human gate.
4. In prepare mode, stop when every active unit is ready or waiting on human action, preserving unmerged tasks and branches. After each authorized merge, refresh the default branch, return affected open pull requests to review, and start newly unblocked units from that refreshed base. Follow repository policy for the merged unit's task archival, branch cleanup, and documented deployment verification.

Track enough batch identity and dependency state in the supervisor task to resume safely. When progress stops, report each unit's current evidence and next action without expanding the requested scope.
