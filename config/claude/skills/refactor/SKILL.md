---
name: refactor
description: Review the changed code treating every comment as evidence of a design flaw, then restructure until the comment is unnecessary. Finds what-comments, comment-compensated naming and structure, append-driven growth, and dead code; applies behavior-preserving refactorings. Pass a path or diff target to scope the review; defaults to the working tree diff.
---

# /refactor

A comment is treated as evidence that the design failed to express something. The goal of this skill is not to delete comments — it is to restructure code until each comment has nothing left to say, then delete it. A comment survives only by proving it carries *why*-knowledge the code cannot express: a spec reference, an upstream-bug workaround, an invariant or concurrency constraint, or the rationale behind a non-obvious value.

## Phase 0 — Scope

One tool call: read the unified diff (`git diff @{upstream}...HEAD; git diff HEAD` to cover both committed and uncommitted changes), or use the target passed as an argument (a path scopes the review to that file or directory instead of a diff). Collect the list of touched files; later phases operate on those files in full, not just the hunks, because the flaw a comment marks usually spans more than the commented line.

## Phase 1 — Find candidates (5 angles, up to 6 each)

Run 5 independent finder angles in parallel via the Agent tool, each with `subagent_type: refactoring-reviewer` and the file list from Phase 0. Each angle surfaces up to 6 candidates as a JSON array of `{file, line, summary, refactoring, cost}` — `refactoring` names the specific restructuring (rename / extract / inline / restructure / delete) and `cost` states what a reader loses while the flaw remains.

### Angle A — what-comments
Comments that restate the code they sit above, section-divider comments narrating steps of an oversized unit, and comments describing what changed rather than what is. The refactoring names the unit boundaries or names that make the narration redundant.

### Angle B — comment-compensated design
Comments that exist because a name is wrong or vague, a function does more than its name admits, a parameter's meaning is not derivable from its type and name, or a magic value is unexplained by a constant name. The comment is the patch; the refactoring fixes what it patches.

### Angle C — append-driven growth
Branches, flags, wrapper layers, and parameter lists that grew by accretion where a restructuring would unify them — including duplicated logic that appending created where an extraction exists or should. Comments marking special cases ("handle legacy path", "except when X") are the strongest signal here.

### Angle D — dead weight
Dead code, unused parameters, speculative generality with no current caller, and commented-out code. Also TODO/FIXME comments older than the code around them — either the task is real (report it) or the comment is dead (delete it).

### Angle E — why-comment audit
Comments claiming to be *why*-knowledge. Challenge each: is the "why" actually expressible in code (a named constant, an assertion, a type, a test)? A why-comment is legitimate only when the constraint lives outside the code — external specs, upstream bugs, protocol requirements, measured values.

Pass every candidate with a nameable refactoring through — finders that silently drop half-believed candidates bypass the verify step and are the dominant cause of misses.

## Phase 2 — Verify

For each candidate, spawn one verifier agent (read-only, `subagent_type: refactoring-reviewer`) that attempts to construct the refactoring concretely: the new names, the extraction boundaries, the deleted lines. Verdicts:

- **CONFIRMED** — the refactoring is constructible and behavior-preserving; the verifier states it precisely.
- **PLAUSIBLE** — the flaw is real but the fix needs context beyond the reviewed files (callers, tests, API stability). State what would confirm it.
- **REFUTED** — the comment proves its innocence: quote the *why*-knowledge and why code cannot carry it, or show the "growth" is the minimal expression of the requirement.

Refute only from evidence in the code — never for being "too minor" or "matter of taste".

## Phase 3 — Apply

Apply CONFIRMED refactorings directly, one logical change at a time: restructure first, then delete the comment the restructuring obsoleted. Never delete a comment whose refactoring was not applied. Every change is behavior-preserving — run the project's tests or type checks after applying when they exist, and revert any change that breaks them back to PLAUSIBLE.

## Phase 4 — Report

Summarize in the final message: applied refactorings (`file:line — refactoring — comment removed`), PLAUSIBLE findings left for the user with what would confirm each, and REFUTED comments that earned their place (one line each). If nothing was found, say the reviewed scope is clean and what was checked.
