---
name: refactor
description: Review the changed code treating every comment as evidence of a design flaw, then restructure until the comment is unnecessary. Finds what-comments, comment-compensated naming and structure, append-driven growth, dead code, and names or scopes that no longer predict their contents; applies behavior-preserving refactorings. Pass a path or diff target to scope the review; defaults to the working tree diff.
---

# /refactor

A comment is treated as evidence that the design failed to express something. The goal of this skill is not to delete comments — it is to restructure code until each comment has nothing left to say, then delete it. A comment survives only by proving it carries *why*-knowledge the code cannot express: a spec reference, an upstream-bug workaround, an invariant or concurrency constraint, the rationale behind a non-obvious value, or the rationale for a decision deliberately *not* taken (why-not) where the alternative is plausible enough that a reader would otherwise re-introduce it or flag its absence. A surviving comment is measured by what it carries: every clause must add why-knowledge, so a clause that restates the code, narrates the change, or announces what comes next is filler even in a short comment — cut it. Comments carrying genuinely distinct why-knowledge each survive on their own merit; only when several compete to explain the *same* decision keep one, by descending rediscovery cost: spec reference > upstream-bug workaround > invariant or concurrency constraint > rationale behind a non-obvious value > why-not (path not taken).

## Phase 0 — Scope

One tool call: read the unified diff to cover both committed and uncommitted changes (`git diff @{upstream}...HEAD; git diff HEAD`), or use the target passed as an argument (a path scopes the review to that file or directory instead of a diff). `@{upstream}` fails with no tracking branch, on an initial commit, or when detached — fall back in order to the merge-base with the default branch (`git merge-base HEAD main` / `master`), then to `git diff HEAD` alone (working tree only). Collect the list of touched files; later phases operate on those files in full, not just the hunks, because the flaw a comment marks usually spans more than the commented line.

## Phase 1 — Find candidates (6 angles, up to 6 each)

Run 6 independent finder angles in parallel via the Agent tool, each with `subagent_type: Explore` (read-only at the tool level — general-purpose would let a finder modify files, which these phases must never do) and the file list from Phase 0. Give every finder the shared reviewer stance: work through a minimalism lens where design, naming, and small well-bounded units carry the meaning and comments are reserved for *why*-knowledge the code cannot express; report the restructuring that removes the need for each comment or growth, not cosmetic style nits.

Each angle surfaces up to 6 candidates as a JSON array of `{file, line, summary, refactoring, cost}` — `refactoring` names the specific restructuring (rename / extract / inline / restructure / delete) and `cost` states what a reader loses while the flaw remains. Angles overlap by design; a finder never suppresses a candidate because another angle owns it — where an angle's text says a candidate "belongs to" another, the finder tags it and emits it anyway. Cross-angle ownership is resolved once, centrally, in Phase 1.5 — not by messages between these parallel runs, which cannot reach each other.

### Angle A — what-comments
Comments that restate the code they sit above, section-divider comments narrating steps of an oversized unit, and comments describing what changed rather than what is. The refactoring names the unit boundaries or names that make the narration redundant. Brevity is no defense: a tidy one-liner whose subject is the code itself is still narration, and terseness or rhythm never earns a comment its place.

### Angle B — comment-compensated design
Comments that exist because a name is wrong or vague, a function does more than its name admits, a parameter's meaning is not derivable from its type and name, or a magic value is unexplained by a constant name. The comment is the patch; the refactoring fixes what it patches.

### Angle C — append-driven growth
Branches, flags, wrapper layers, and parameter lists that grew by accretion where a restructuring would unify them — including duplicated logic that appending created where an extraction exists or should. Comments marking special cases ("handle legacy path", "except when X") are the strongest signal here. The same accretion in prose: a comment or `*.md` doc extended by appending rather than restructured, or the same fact duplicated across homes that belongs in one — the refactoring rewrites from the structure, consolidates each fact to its single home, and keeps only the essential rather than tacking on.

### Angle D — dead weight
Dead code, unused parameters, speculative generality with no current caller, and commented-out code. Also TODO/FIXME comments older than the code around them — either the task is real (report it) or the comment is dead (delete it). A TODO/FIXME carrying both a rationale and a tracking reference (issue link, ticket) is why-not, not dead weight — tag it as why-not (Angle E) rather than proposing deletion; dead judgment is reserved for stale markers with neither reason nor reference.

### Angle E — why-comment audit
Comments claiming to be *why*-knowledge, including *why-not*. Challenge each against the survival test in the intro: is the "why" actually expressible in code (a named constant, an assertion, a type, a test), or does the constraint genuinely live outside it? Code cannot express the absence of a path not taken, so a why-not comment is its only carrier — this is the angle that owns why-not: a candidate flagged as a what-comment (Angle A) or special-case marker (Angle C) that is really why-not belongs here.

The judgement rests on one stance: read as a new reader who knows nothing of the change that introduced this comment — sharing the in-progress intent of this diff is exactly what smuggles a doomed comment through. A why-not survives only by passing every gate; failing one routes it to deletion, except the last, which routes to structural repair:

- **New-reader test** — it must hold without the change's backstory. A why-not that only reads as rationale given the intent behind this diff ("we're consolidating these now") is change-narration in why-not's clothing — delete it.
- **Locality test** — the constraint must be specific to the annotated spot. If it applies uniformly to every same-kind element in the file or repo (e.g. "this isn't shared" said of one ID among many identical ones), a lone note only makes a reader ask "why only here" — delete it.
- **Plausible-alternative test** — a reader must actually be able to reach for the rejected path. If none would think to reintroduce it, the comment answers a question no one asked — delete it.
- **Single-source test** — a comment that exists only to keep duplicated or double-managed state in sync is masking a structural flaw, not carrying why-not. Tag it for Angle C's consolidation, or report it PLAUSIBLE if the restructuring is out of scope — never keep it.

### Angle F — naming & scope
Names inconsistent with the surrounding vocabulary that force readers to translate. File and directory names whose scope no longer predicts their contents: a file named after one specific function has no room for cohesive growth, while grab-bag names (`common`, `utils`, `helpers`, `misc`) accumulate unrelated code and force readers and searches to scan everything. Directory structure that does not let a reader locate a responsibility from the name alone — judge against the project's own layout conventions, flagging deviations from that project's pattern, not from a universal ideal.

Pass every candidate with a nameable refactoring through — finders that silently drop half-believed candidates bypass the verify step and are the dominant cause of misses.

## Phase 1.5 — Consolidate

Merge the six candidate lists here, centrally:

- **Dedup** by `file:line` (and near-identical summary): collapse the same flaw surfaced by multiple angles into one candidate so Phase 2 verifies it once, not once per angle.
- **Resolve ownership** by the tags finders emitted: a candidate tagged why-not (from Angle A/C/D) is judged under Angle E's survival gates; an Angle E single-source tag becomes an Angle C consolidation candidate. Keep the classification that determines how Phase 2 verifies it.

Emit one deduped, classified candidate list for Phase 2.

## Phase 2 — Verify

For each candidate, spawn one verifier agent with `subagent_type: Explore`, under the same reviewer stance as the finders. The verifier takes the defendant's side: the burden of proof is on the refactoring, and the comment or code is presumed innocent until the verifier constructs the refactoring concretely — the new names, the extraction boundaries, the deleted lines — and shows it is behavior-preserving and clearly superior. Verdicts:

- **CONFIRMED** — the refactoring is constructible and behavior-preserving; the verifier states it precisely. For a `restructure` (the one open-ended verb that reshapes control or data flow), CONFIRMED requires the verifier to exhibit the concrete target shape *and* an explicit behavior-preservation argument; absent either, it caps at PLAUSIBLE.
- **PLAUSIBLE** — the flaw is real but the fix needs context beyond the reviewed files (callers, tests, API stability). State what would confirm it.
- **REFUTED** — the comment proves its innocence: quote the *why*-knowledge and why code cannot carry it, or show the "growth" is the minimal expression of the requirement. A why-not that names a real rationale but fails any Angle E survival gate is still REFUTED, not retained.

Refute only from evidence in the code — never for being "too minor" or "matter of taste".

## Phase 3 — Apply

Apply CONFIRMED refactorings directly, one logical change at a time: apply the restructuring first, then delete the comment it obsoleted. Never delete a comment whose refactoring was not applied. Every change is behavior-preserving — run the project's tests or type checks after applying when they exist, and revert any change that breaks them back to PLAUSIBLE.

A `restructure` reaches this apply step only through the Phase 2 proof gate; tests catch behavior regressions but not a green-but-wrong reshaping, so a wrong-but-passing abstraction is a taste judgment this skill routes to the human rather than commits blind.

## Phase 4 — Report

Summarize in the final message: applied refactorings (`file:line — refactoring — comment removed`), PLAUSIBLE findings left for the user with what would confirm each, and REFUTED comments that earned their place (one line each). If nothing was found, say the reviewed scope is clean and what was checked.
