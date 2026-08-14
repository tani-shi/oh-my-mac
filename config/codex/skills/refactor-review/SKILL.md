---
name: refactor-review
description: Perform a read-only, evidence-based structural refactoring review of the current implementation goal, conversation context, and worktree changes; rank at most three material candidates as APPLY or ASK. Use only when explicitly invoked as $refactor-review. With the apply argument, apply only the preceding review's APPLY findings in the same conversation and run relevant tests. Do not use for general bug review.
---

# Refactor Review

Select Review mode for `$refactor-review` and Apply mode for `$refactor-review apply`.

## Review

1. Establish the implementation goal from the current request and conversation.
2. Inspect the staged, unstaged, and untracked worktree changes. Read each changed area as a complete structural unit, then inspect the callers and tests needed to establish its behavior.
3. Look for material structural improvements:
   - comments compensating for unclear code, naming, or structure;
   - append-driven growth that should reshape the touched unit;
   - duplication within the reviewed scope;
   - dead code exposed by the change;
   - files, functions, or directories whose scope no longer matches their cohesive contents.
4. Keep only candidates whose value justifies changing working code. Omit cosmetic, refuted, speculative, and low-value candidates.
5. Classify each remaining candidate:
   - `APPLY`: repository evidence proves the proposed change behavior-preserving;
   - `ASK`: an external contract or design choice requires human judgment.
6. Return at most three findings, ranked by value. Do not modify files.

Use this format for each finding:

```text
### APPLY 1 — <summary>
Location: <file:line>
Change: <specific refactoring>
Evidence: <repository evidence that proves behavior is preserved>
Validation: <tests or checks to run after applying>
```

For `ASK`, replace `Evidence` with `Decision` and state the choice the user must make. If no finding survives the filter, return `No material structural refactoring findings.` Do not report discarded candidates.

Keep ordinary correctness and bug findings in Codex's standard `/review`. Use an external `codex review` only when a high-risk change benefits from independent read-only confirmation, never as the default workflow.

## Apply

1. Read only the `APPLY` findings from the immediately preceding Refactor Review in this conversation. If none are available or their identity is ambiguous, make no changes and ask the user to run `$refactor-review` again.
2. Do not apply `ASK` findings and do not search for new candidates.
3. Re-read each target and its current diff. Skip a finding if the reviewed code changed or its behavior-preserving evidence no longer holds.
4. Apply the remaining findings within their reviewed scope.
5. Run the relevant tests or checks named by the findings, adding the smallest extra validation required by the resulting diff.
6. Report applied findings, skipped findings with reasons, and validation results.

Keep review state only in the conversation. Do not create refs, pending files, or review-history artifacts.
