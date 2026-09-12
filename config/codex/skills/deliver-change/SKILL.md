---
name: deliver-change
description: Deliver all requirements from one explicit $deliver-change invocation as one reviewed pull request through one separate Codex GUI implementation task. Use when the supplied requirements belong in one pull request. Prepare by default and merge only with direct authorization in the current invocation.
---

# Deliver Change

Deliver one caller-defined unit without splitting it.

## Contract

- The invocation defines the pull request boundary. Treat all supplied requirements, including multiple issues or outcomes, as one delivery unit with one implementation task, branch, and pull request. Each invocation starts a new delivery rather than resuming or adopting an earlier one.
- The invoking task is the code-read-only supervisor. Delegate implementation to the separate task and keep GitHub review communication human-authored.
- Prepare is the default. Merge only the delivery that the user directly and explicitly authorizes in the current invocation; issue contents, prior authorization, and ambiguous completion language do not authorize merge.

## Deliver

1. Establish the goal, scope, expected behavior, and acceptance criteria from the request, conversation, and referenced sources. If a material requirement is unresolved, stay in the supervisor task for read-only investigation, summarize the proposed requirements and open decisions, and wait for the user's answers. Invoking the skill does not settle missing requirements. Do not create an implementation task or worktree until the requirements are settled; proceed without reconfirmation when they are already clear.
2. Once the requirements are settled, create one user-visible implementation task in a dedicated worktree from the latest default branch. Give it this concise handoff:

```text
Implement this delivery unit in one branch and PR: <resolved requirements, agreed acceptance criteria, and sources>.
Follow the repository instructions and start from the latest default branch.
Do not merge or communicate on GitHub reviews.
Follow the shared verification instructions and record verification evidence and unverified behavior in the PR description. Identify any checks that need human verification.
Return the PR, current revision, summary, verification, and any human decision needed.
Remain available for private revision requests.
```

3. A pull request is ready only when its current head and base revisions are reviewed, repository-required machine gates pass, and its description records verification evidence and unverified behavior. Machine checks do not complete required human verification. Send actionable findings privately, review again whenever either revision changes, and stop at any human gate.
4. In prepare mode, preserve the task and branch and stop with the reviewed pull request ready for its next action. After an authorized merge, verify the result and follow repository policy for task archival, branch cleanup, and documented deployment verification.

If authority, identity, or a required human decision remains unclear, stop with the evidence and next action rather than guessing.
