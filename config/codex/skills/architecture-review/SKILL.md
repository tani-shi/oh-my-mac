---
name: architecture-review
description: Diagnose a repository or a specified path for high-value architectural simplification opportunities using read-only evidence from entry points, responsibility boundaries, dependencies, references, tests, and history. Use only when explicitly invoked as $architecture-review or $architecture-review path PATH. Do not use for current-diff refactoring review, bug review, or automatic changes.
---

# Architecture Review

Perform a low-frequency structural diagnosis. Do not modify files, create artifacts, or apply findings during the diagnosis.

## Scope

- For `$architecture-review`, inspect the whole repository.
- For `$architecture-review path <path>`, restrict candidate discovery to that file or directory. Inspect callers, dependencies, tests, and history outside the path only as evidence about the scoped code.
- If the path does not exist or resolves outside the repository, stop and report that the scope is invalid.
- Exclude the current working diff as a special source of review context. Use `$refactor-review` for structural review of an implementation session and `/review` for correctness findings.

## Diagnose

1. Preserve live state. Use only read operations; do not edit files, install dependencies, create branches, write reports, or run commands that update caches, snapshots, fixtures, or generated files.
2. Establish the repository shape before proposing candidates:
   - identify executable, service, library, and configuration entry points relevant to the scope;
   - map the major responsibility boundaries and the files or modules that implement them;
   - trace dependency direction across those boundaries, including external interfaces.
3. Search for material simplification opportunities within the scope:
   - responsibilities mixed across one unit or split across mismatched units;
   - duplicated responsibilities or implementations;
   - abstractions without a current second caller or meaningful policy boundary;
   - append-driven growth that accumulated branches, flags, wrappers, or unrelated operations;
   - dead paths that no reachable entry point uses.
4. Verify each candidate against repository evidence. Trace references and callers, read tests that define behavior, and inspect history when it can explain ownership, compatibility, or deliberate structure. Treat absence from a single search as insufficient proof that a path is dead.
5. Determine what deletion, consolidation, or boundary change would make simpler. Identify any behavior, compatibility promise, data migration, extension point, or other external contract that could be lost.
6. Reject cosmetic, speculative, refuted, and low-value candidates. Rank the survivors by expected reduction in maintenance cost, cognitive load, and change risk; return at most three.
7. Recommend `ISSUE` when the evidence supports a bounded follow-up with testable completion criteria. Recommend `DROP` when the concern is material enough to record but the likely contract loss or implementation cost outweighs the simplification. Do not apply either recommendation.

## Report

Use this format for every surviving candidate, in value order:

```text
### ISSUE 1 — <short summary>
Target and evidence: <paths, symbols, references, tests, and history>
Responsibility simplified: <responsibility made smaller, clearer, or singular>
Possible loss: <behavior or external contract at risk, or "None found">
Recommendation: ISSUE
Issue title: <short actionable title>
Acceptance criteria:
- <observable completion criterion>
- <required compatibility or test criterion>
```

For a `DROP`, use this format and omit `Issue title` and `Acceptance criteria`:

```text
### DROP <n> — <short summary>
Target and evidence: <paths, symbols, references, tests, and history>
Responsibility simplified: <responsibility that could become smaller, clearer, or singular>
Possible loss: <behavior or external contract at risk>
Recommendation: DROP — <reason not to track this as an issue>
```

Support every reported candidate with concrete repository evidence. Do not list explored or rejected candidates. If none survive, return `No material architecture findings.`
