---
name: deliver-change
description: Start or resume one requested code change in a separate Codex GUI implementation task, supervise its pull request through implementation and private review-revision loops, pause for human verification, then merge, archive the implementation task, and perform applicable post-deployment verification. Use only when explicitly invoked as $deliver-change. Supply an issue reference or plain-language objective to start a delivery; invoke it without an objective in the same supervisor task to reconcile and continue the active delivery idempotently.
---

# Deliver Change

Run one stateful delivery workflow in the invoking Codex GUI task. Treat that task as the code-read-only supervisor and create one user-visible implementation task in a dedicated worktree. Keep GitHub review communication human-authored. Do not return while supervised work can still progress safely, but always pause before merge so the user can verify the pull request.

## Interpret each invocation

Allow at most one active delivery in a supervisor task. Reconcile existing state before creating anything.

1. If an active delivery exists and the invocation has no objective, refresh and continue it.
2. If an active delivery is at `READY_FOR_HUMAN_VERIFICATION`, treat another explicit `$deliver-change` invocation in the same supervisor task as confirmation that the user completed manual verification and authorization to continue. Revalidate every gate before merging.
3. If an objective is supplied and no active delivery exists, first reconcile any completed delivery that identifies the same objective. Report the completed state without duplication when one matches; otherwise start a delivery for it.
4. If the supplied objective identifies the active delivery, refresh and continue it rather than creating another task, branch, or pull request.
5. If a different objective is supplied while a delivery is active, ask whether to finish or abandon the active delivery. Do not start a second delivery silently.
6. If no objective and no active or completed delivery can be identified, ask for an issue reference or implementation request.
7. If the delivery is complete, reconcile its final state and report it without repeating merge, archival, branch cleanup, or deployment actions.

Use GitHub and Codex task state as the source of truth. Conversation state is a pointer, not proof that an external action succeeded. Keep these identifiers in supervisor context and include them in every human-verification handoff:

- repository and objective;
- Codex project ID;
- implementation task title, thread ID, and host ID;
- base branch and remote implementation branch;
- pull request URL and number;
- last fully reviewed head SHA;
- current phase: `IMPLEMENTING`, `REVIEWING`, `READY_FOR_HUMAN_VERIFICATION`, `MERGING`, `VERIFYING_DEPLOYMENT`, `COMPLETE`, or `BLOCKED`.

## Resolve the objective

Treat the objective as the requested implementation, not as a required issue identifier.

1. Accept a plain-language request, pasted requirements, a repository document reference, or a GitHub issue reference.
2. When a GitHub issue is referenced, read its title, body, acceptance criteria, and relevant discussion. Treat additional user text as an override or refinement.
3. Otherwise use the supplied request and relevant repository context directly. Do not require or create an issue.
4. Resolve details from the repository and applicable instructions. Ask the user only when a missing decision would materially change public behavior, data, security, or scope.

## Preflight

1. Require the Codex GUI capabilities for listing projects and active and archived tasks, creating a task, waiting for it, sending follow-ups, and changing its archived state. Stop with the missing capability; do not substitute an internal subagent.
2. Use `list_projects` to identify the saved project for the invoking repository. Require a Git repository and use the same project for the implementation task.
3. Select an authenticated GitHub capability available to the supervisor. Prefer an installed GitHub integration when available; otherwise use an authenticated `gh` CLI. Require permission to read pull requests, checks, reviews, and discussions, and require issue-read permission only when the objective references an issue. Determine whether the supervisor can merge, but do not block implementation merely because merge authority is unavailable; report that limitation at human verification. Do not require permission to submit reviews because this workflow leaves GitHub review communication to the user.
4. Inspect applicable repository instructions and the test, documentation, pull request, merge, branch cleanup, and deployment conventions needed for the objective.
5. Treat an explicit invocation with a new objective as authorization to create the one implementation task required by this workflow. Do not create unrelated tasks.

## Reconcile the active delivery

Before creating or advancing work:

1. Resolve the recorded implementation task and pull request. If an identifier is absent after conversation compaction, use the repository, unique implementation-task title, remote branch, and open pull request to recover it. Bind only an unambiguous match; ask instead of guessing.
2. Refresh the pull request, checks, reviews, discussions, branch, and implementation task.
3. If the pull request is merged, skip directly to idempotent archival, branch cleanup, and deployment verification.
4. If it is closed without merge, enter `BLOCKED` and ask whether to reopen it, replace it, or end the delivery.
5. If the implementation task exists but no pull request does, continue waiting or send a focused recovery instruction to that task.
6. Create a replacement implementation task only when the recorded task or worktree is unusable. Never create a duplicate merely because progress is slow or a task ID was temporarily unavailable.

## Create the implementation task

1. Call `create_thread` for the same saved project with a worktree environment. Omit model and reasoning overrides unless the user explicitly requested them. Use a concise, unique title derived from the objective and applicable task-title conventions.
2. Omit `startingState` so the task starts from the project's default branch. Require the implementation task to fetch the remote default branch and detach at its latest commit before editing; never assume the local default branch is current.
3. Keep the returned thread ID and host ID for the entire workflow. If creation returns only a pending client ID, poll `list_threads` for the matching project and unique title until the ready task has a thread ID. Do not create a duplicate task.
4. Give the implementation task this contract, adapted to the objective and repository:

```text
Implement the supplied objective in this dedicated worktree.

Read and follow every applicable repository instruction. Determine the remote
default branch, fetch it, and detach at the latest origin/<default-branch>
before editing. Keep the worktree detached. Choose one repository-conforming
remote branch name and retain it for all pushes.

Implement the complete change, add or update tests, and update documentation
when the repository instructions or user-visible behavior require it. Run all
relevant verification. Commit the related changes together. Push the detached
HEAD explicitly with `git push origin HEAD:refs/heads/<remote-branch>` and use
that same refspec for later pushes. Create a pull request from that branch.

Do not merge the pull request. Do not submit, reply to, or resolve GitHub review
comments. Report the PR URL and number, base branch, remote branch, head SHA,
implementation summary, and verification results, then yield to the supervisor.
Remain available for private review follow-ups.
```

## Supervise without exiting

1. Wait on the implementation task with `wait_threads`. Reuse the latest cursor so completed output is not delivered twice.
2. Treat a wait timeout or unchanged progress as normal. Continue waiting without asking the user to resume. Report only meaningful progress and keep updates concise.
3. If the implementation task requests an ordinary in-scope decision, inspect the repository and answer it with `send_message_to_thread`. Escalate only decisions that require new authority or materially change the requested result.
4. If the implementation task stops before opening a pull request, send a focused recovery instruction to the same task and wait again.
5. Preserve review independence: do not edit the implementation worktree from the supervisor task.

## Review and revise privately

After the implementation task reports a pull request:

1. Read the current metadata, base branch, head SHA, complete diff, checks, reviews, and discussions. Fetch refs for read-only inspection when useful; do not check out the implementation branch in the supervisor worktree.
2. Review the entire change against the objective and applicable repository instructions. Check correctness, regressions, tests, documentation, error handling, compatibility, security boundaries, and integration with the latest base branch. Omit cosmetic or speculative findings.
3. Run safe read-only checks or independent verification in the supervisor environment when they materially strengthen the review. Do not modify the implementation.
4. If the supervisor finds actionable issues, send them directly to the implementation task with precise file locations, evidence, expected behavior, and correction direction. Do not post a GitHub review or GitHub comment unless the user explicitly asks.
5. Instruct the implementation task to address every private finding, rerun relevant verification, commit, push with the explicit detached-HEAD refspec, and report the new head SHA without posting GitHub replies or merging.
6. Treat an advanced base branch or merge conflict as a normal revision. Require the implementation task to incorporate the latest remote base, resolve textual and semantic conflicts according to intended behavior, and run relevant full tests.
7. Review the complete updated pull request after every new head SHA. Continue until no actionable private finding remains and machine-controlled checks pass. Do not impose an arbitrary iteration limit while progress continues.

Use this follow-up shape:

```text
Address every private supervisor finding below in this same worktree. Fetch the
latest remote base first and resolve any textual or semantic conflicts while
preserving the objective. Rerun all relevant verification, commit, and push
with `git push origin HEAD:refs/heads/<remote-branch>`. Report the new head SHA
and a resolution summary. Do not post or resolve GitHub review comments and do
not merge.

<findings>
```

## Pause for human verification

After private review is clean and machine-controlled checks finish:

1. Refresh the branch protection, review decision, submitted reviews, required checks, merge state, conflicts, and unresolved discussions.
2. Enter `READY_FOR_HUMAN_VERIFICATION` for every pull request, even when branch protection does not require human approval. Never merge during the invocation that first reaches this phase.
3. Report the pull request URL, reviewed head SHA, implementation summary, verification evidence, private-review result, known risks, relevant manual test steps, approval state, unresolved discussions, and every remaining merge requirement.
4. State that the user should review the pull request and own any GitHub review comments or replies. Keep the implementation task unarchived and do not start deployment verification.
5. Tell the user to invoke `$deliver-change` again in this same supervisor task after manual verification. This exact invocation is the continuation signal; a `resume` argument is unnecessary.

On that later invocation:

1. Refresh the complete external state before acting.
2. If human review requested changes or added actionable unresolved comments, forward the substance to the existing implementation task. Require code changes and a resolution report, but leave GitHub replies and discussion resolution to the user.
3. After any new head SHA, repeat full private review and checks, then stop again at `READY_FOR_HUMAN_VERIFICATION`. The earlier continuation signal does not authorize merging an unreviewed revision.
4. If required human approvals are missing or any required or actionable human-owned discussion remains unresolved, remain at `READY_FOR_HUMAN_VERIFICATION` and report the exact gate.
5. If the reviewed head SHA is unchanged and all required checks, approvals, discussions, and policies are satisfied, treat the invocation as human-verification confirmation and continue to merge.

## Merge safely

Immediately before merging:

1. Require a prior `READY_FOR_HUMAN_VERIFICATION` handoff and a later explicit `$deliver-change` invocation in the same supervisor task.
2. Refresh the pull request and confirm its current head SHA is exactly the SHA reviewed privately and presented for human verification. Return to full review and another human-verification pause if it changed.
3. Confirm that required checks pass, the pull request is mergeable, review findings are addressed, required human approvals exist, required and actionable human-owned discussions are resolved, merge authority is available, and no repository policy or branch protection remains unsatisfied.
4. Follow the repository's merge-method convention and merge from the supervisor task. Never bypass branch protection or submit an approval as a substitute for a human reviewer.
5. Verify the merged state and record the pull request URL, reviewed head SHA, and merge commit SHA. Never infer success from the merge command alone.

## Archive, clean up, and verify

1. After confirming the merge, check `list_archived_threads`, following pagination as needed, for the stored implementation task ID. If it is not already archived, request archival with `set_thread_archived`; archive only the implementation task, never the invoking supervisor task.
2. Because archival runs in the background, poll `list_archived_threads` on the stored host, following pagination as needed, until the implementation task ID appears. If it does not appear after a bounded wait, request archival once more with the stored thread ID and host ID and poll again. Report success only after observing the archived task; otherwise report the persistent failure explicitly.
3. Delete the merged implementation branch from the remote when repository policy permits it. Delete a same-named local branch only when it exists and no worktree uses it, then prune stale remote-tracking refs. Treat an already absent branch as success.
4. Make archival and branch cleanup idempotent. Continue deployment verification when they were already completed by the user or another system.
5. When the repository defines automatic deployment, wait for the merged revision's deployment rather than accepting an unrelated successful environment. Confirm the deployed commit or version when the platform exposes it.
6. Run the repository's documented production smoke checks. Verify authentication and fallback behavior when relevant to the objective. Use test accounts, feature flags, synthetic endpoints, or other non-destructive paths; do not induce a real outage to exercise fallback.
7. When the repository has no deployment or no authorized verification path, mark post-deployment verification as not applicable or unavailable with the concrete reason. Do not invent success.
8. If deployment verification fails, keep the supervisor task active, diagnose the failure, and create a separate recovery task only when a code change is required. The completed implementation task remains archived.

## Finish

At `READY_FOR_HUMAN_VERIFICATION`, report:

- the objective, pull request URL, base and remote branches, and reviewed head SHA;
- the implementation, tests, checks, and private review performed;
- risks and concrete manual verification steps;
- approvals, unresolved discussions, and remaining merge requirements;
- the implementation task title and its retained identifier;
- the instruction to invoke `$deliver-change` again in this supervisor task after verification.

At `COMPLETE`, report:

- the delivered objective, pull request URL, reviewed head SHA, and merge commit;
- implementation, verification, and revision rounds;
- deployment verification or why it was not applicable;
- implementation-task archival and local and remote branch cleanup;
- any unresolved operational issue.

Do not commit changes from the supervisor worktree, publish Codex-authored review communication without explicit user direction, merge before a human-verification pause and later invocation, archive the implementation task before merge, or repeat an external side effect whose completed state can be verified.
