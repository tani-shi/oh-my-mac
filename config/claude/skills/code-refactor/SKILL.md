---
name: code-refactor
description: Review the changed code treating every comment as evidence of a design flaw, then restructure until the comment is unnecessary. Finds what-comments, comment-compensated naming and structure, append-driven growth, dead code, and file or directory scopes too narrow or too broad for their contents (consolidating over-fragmented files, splitting grab-bags, renaming units scoped to one operation up to their entity); applies behavior-preserving refactorings. Pass a path or diff target to scope the review; defaults to what changed since the last review, narrowed to the diff against the branch's base (PR base / default branch) plus the working tree.
---

# /code-refactor

A comment is treated as evidence that the design failed to express something. The goal of this skill is not to delete comments — it is to restructure code until each comment has nothing left to say, then delete it. A comment survives only by proving it carries *why*-knowledge the code cannot express: a spec reference, an upstream-bug workaround, an invariant or concurrency constraint, the rationale behind a non-obvious value, or the rationale for a decision deliberately *not* taken (why-not) where the alternative is plausible enough that a reader would otherwise re-introduce it or flag its absence. A surviving comment is measured by what it carries: every clause must add why-knowledge, so a clause that restates the code, narrates the change, or announces what comes next is filler even in a short comment — cut it. Comments carrying genuinely distinct why-knowledge each survive on their own merit; only when several compete to explain the *same* decision keep one, by descending rediscovery cost: spec reference > upstream-bug workaround > invariant or concurrency constraint > rationale behind a non-obvious value > why-not (path not taken).

## Phase 0 — Scope

Collect the list of touched files; later phases operate on those files in full, not just the hunks, because the flaw a comment marks usually spans more than the commented line.

**Mode** — a path/diff argument selects **path mode**: review that path (a file or directory), and the review ref below is neither read nor written. No argument selects **full-scope**.

**Current tree** (full-scope) — compute the working-tree tree SHA `cur` through a throwaway index so the real index is untouched:

```
idx="$(git rev-parse --git-path code-refactor-index)"
GIT_INDEX_FILE="$idx" git read-tree HEAD
GIT_INDEX_FILE="$idx" git add -A
cur="$(GIT_INDEX_FILE="$idx" git write-tree)"; rm -f "$idx"
```

**Base** (full-scope, in order):

- **PR base** — `gh pr view --json baseRefName -q .baseRefName`; on success the candidate is `origin/<baseRefName>`.
- **Default branch** — `git symbolic-ref --short refs/remotes/origin/HEAD` (already `origin/<name>`).
- **Ref guard** — verify each candidate with `git rev-parse --verify --quiet <candidate>` before use; a shallow or single-branch clone may lack the `origin/<base>` remote-tracking ref, which would make `git diff <base>...HEAD` fail. If the PR-base candidate is absent, fall through to the default branch; if that too is absent, there is no base.
- **No base** — none of the above resolved: review the working tree only, and note this in the Phase 7 report.

**Review ref** (full-scope) — Phase 7 records each completed review as `refs/code-refactor/<slug>`, where `<slug>` is the branch name with `/` replaced by `%` (`git rev-parse --abbrev-ref HEAD | tr '/' '%'`); the substitution keeps branches like `fix` and `fix/x` from colliding as a directory and a file in the ref namespace. Resolve in order, taking the first that `git rev-parse --verify --quiet <ref>^{tree}` resolves:

- the current branch's ref;
- the base branch's ref (`refs/code-refactor/` + the resolved base with its `origin/` prefix stripped and `/` substituted), so a review finished on the default branch carries into a branch cut from it;
- none — the whole diff is in scope, as it is on a first run in a repository.

**Diff** — with a review ref, the scope is what changed since that review; without one, it is the whole diff:

- **ref resolved** — `delta="$(git diff --name-only "$ref^{tree}" "$cur")"`. `git diff <commit>` omits untracked files, which the recorded tree includes.
  - `delta` empty → nothing changed since the last review: skip Phases 2–5 and go to Phase 1, which may still put carried-over findings to the human.
  - branch diff (`git diff --name-only <base>...HEAD`) non-empty → scope is `delta` intersected with the union of that branch diff, `git diff --name-only HEAD`, and `git ls-files --others --exclude-standard`. The intersection keeps a merge of the base branch from dragging other people's files in.
  - branch diff empty (working directly on the default branch) → scope is `delta` itself; intersecting would leave it permanently empty.
- **no ref** — base resolved → `git diff <base>...HEAD; git diff HEAD` (three-dot: the diff from the merge-base, matching the PR diff on GitHub — never the two-dot tip comparison); no base → `git diff HEAD` (working tree only).
- **path mode** → the given path.

## Phase 1 — Replay pending findings

Full-scope only. Phase 7 leaves the actionable PLAUSIBLE findings no human ruled on in `.git/code-refactor-pending.json` (`git rev-parse --git-path code-refactor-pending.json`), a JSON array of `{file, anchor, summary, refactoring, judgment}`:

```json
[
  {
    "file": "config/git/discard.zsh",
    "anchor": "Milliseconds keep the name strictly increasing, so refname order is creation order",
    "summary": "…", "refactoring": "extract", "judgment": "…"
  }
]
```

`anchor` is the target comment or construct as text, normalized — comment markers stripped, runs of whitespace collapsed to one space, trimmed, first 120 characters. It is a line-number-free handle that survives edits elsewhere in the file, held literally so this phase matches it by string comparison and a human can read the file and see what a finding refers to.

Read each entry's `file` and keep the finding if its `anchor` is still present under the same normalization; drop it otherwise. Survivors join the Phase 6 questions as they are — this phase spawns no finders and no verifiers.

## Phase 2 — Find candidates (6 angles, up to 6 each)

Run 6 independent finder angles in parallel via the Agent tool, each with `subagent_type: Explore` (read-only at the tool level — general-purpose would let a finder modify files, which these phases must never do) and the file list from Phase 0. Angles C and F additionally receive the pre-intersection branch file list as context — duplication and mis-scoped naming are judged against the whole branch — but report only on files in scope; a consolidation whose other half lies outside is tagged **out-of-scope** and emitted anyway, and Phase 3 routes it to the Phase 7 report. Give every finder the shared reviewer stance: work through a minimalism lens where design, naming, and small well-bounded units carry the meaning and comments are reserved for *why*-knowledge the code cannot express; report the restructuring that removes the need for each comment or growth, not cosmetic style nits.

Each angle surfaces up to 6 candidates as a JSON array of `{file, line, summary, refactoring, cost}` — `refactoring` names the specific restructuring (rename / extract / inline / restructure / delete) and `cost` states what a reader loses while the flaw remains. Angles overlap by design; a finder never suppresses a candidate because another angle owns it — where an angle's text says a candidate "belongs to" another, the finder tags it and emits it anyway. Cross-angle ownership is resolved once, centrally, in Phase 3 — not by messages between these parallel runs, which cannot reach each other.

### Angle A — what-comments
Comments that restate the code they sit above, section-divider comments narrating steps of an oversized unit, and comments describing what changed rather than what is. The refactoring names the unit boundaries or names that make the narration redundant. Brevity is no defense: a tidy one-liner whose subject is the code itself is still narration.

### Angle B — comment-compensated design
Comments that exist because a name is wrong or vague, a function does more than its name admits, a parameter's meaning is not derivable from its type and name, or a magic value is unexplained by a constant name. The comment is the patch; the refactoring fixes what it patches.

### Angle C — append-driven growth
Branches, flags, wrapper layers, and parameter lists that grew by accretion where a restructuring would unify them — including duplicated logic that appending created where an extraction exists or should. Comments marking special cases ("handle legacy path", "except when X") are the strongest signal here. The same accretion in prose: a comment or `*.md` doc extended by appending rather than restructured, or the same fact duplicated across homes that belongs in one — the refactoring rewrites from the structure, consolidates each fact to its single home, and keeps only the essential rather than tacking on.

### Angle D — dead weight
Dead code, unused parameters, speculative generality with no current caller, and commented-out code. Also TODO/FIXME comments older than the code around them — either the task is real (report it) or the comment is dead (delete it). A TODO/FIXME carrying both a rationale and a tracking reference (issue link, ticket) is why-not, not dead weight — tag it as why-not (Angle E) rather than proposing deletion; dead judgment is reserved for stale markers with neither reason nor reference.

### Angle E — why-comment audit
Comments claiming to be *why*-knowledge, including *why-not*. Challenge each against the survival test in the intro: is the "why" actually expressible in code (a named constant, an assertion, a type, a test), or does the constraint genuinely live outside it? Code cannot express the absence of a path not taken, so a why-not comment is its only carrier — this is the angle that owns why-not: a candidate flagged as a what-comment (Angle A) or special-case marker (Angle C) that is really why-not belongs here. A comment carrying any downstream effect the annotated code's names and types cannot reconstruct is why-knowledge however terse it looks — do not propose deleting it on grounds of symmetry or brevity.

The judgement rests on one stance: read as a new reader who knows nothing of the change that introduced this comment — sharing the in-progress intent of this diff is exactly what smuggles a doomed comment through. A why-not survives only by passing every gate; failing one routes it to deletion, except the last, which routes to structural repair:

- **New-reader test** — it must hold without the change's backstory. A why-not that only reads as rationale given the intent behind this diff ("we're consolidating these now") is change-narration in why-not's clothing — delete it.
- **Locality test** — the constraint must be specific to the annotated spot. If it applies uniformly to every same-kind element in the file or repo (e.g. "this isn't shared" said of one ID among many identical ones), a lone note only makes a reader ask "why only here" — delete it.
- **Plausible-alternative test** — a reader must actually be able to reach for the rejected path. If none would think to reintroduce it, the comment answers a question no one asked — delete it.
- **Single-source test** — a comment that exists only to keep duplicated or double-managed state in sync is masking a structural flaw, not carrying why-not. Tag it for Angle C's consolidation, or, if the restructuring lies outside the reviewed files, tag it **out-of-scope** — never keep it, and never route it to PLAUSIBLE, which is reserved for findings that turn on human judgment.

### Angle F — naming & scope
Names inconsistent with the surrounding vocabulary that force readers to translate. File and directory names whose scope mispredicts their contents in *either* direction:

- **Too broad** — grab-bag names (`common`, `utils`, `helpers`, `misc`) accumulate unrelated code and force readers and searches to scan everything; the refactoring splits them into cohesively-named homes.
- **Too narrow — fragment** — a lone export with a single consumer and no cohesive sibling that would ever join it partitions the namespace one-file-per-function, so a reader must open many fragments to assemble one responsibility. When the boundary carries less meaning than the navigation cost it imposes, the refactoring consolidates it into its natural home (`inline` / `delete` the boundary).
- **Too narrow — mis-scoped name** — a module that *is* a real, correctly-shared unit but is named after one operation on an entity rather than the entity itself (`team-identity.ts` among siblings named `team`, `forum`, `permission`). The name predicts only that operation, so the next cohesive sibling has nowhere to land and spawns another fragment; the refactoring `rename`s it up to the entity scope its siblings share — the unit stays, only the name widens.

Discriminate by the import graph and the project's own vocabulary, never by file size: many consumers across domains, or contents that fit the project's per-responsibility layout, mean the unit is correctly separate — the remaining question is only whether its name sits at the entity scope its siblings use. A file whose contents are cohesive and have room to grow is correctly scoped even when small. Judge directory structure against the project's own layout conventions, flagging deviations from that project's pattern, not from a universal ideal.

Pass every candidate with a nameable refactoring through — finders that silently drop half-believed candidates bypass the verify step and are the dominant cause of misses.

## Phase 3 — Consolidate

Merge the six candidate lists here, centrally:

- **Dedup** by `file:line` (and near-identical summary): collapse the same flaw surfaced by multiple angles into one candidate so Phase 4 verifies it once, not once per angle.
- **Resolve ownership** by the tags finders emitted: a candidate tagged why-not (from Angle A/C/D) is judged under Angle E's survival gates; an Angle E single-source tag becomes an Angle C consolidation candidate. Keep the classification that determines how Phase 4 verifies it.
- **Route out-of-scope** by the same tags: a candidate whose refactoring cannot be completed without editing files outside the Phase 0 scope is set aside here. It skips Phases 4–6 and reaches Phase 7 as an out-of-scope opportunity — outside the touched scope an opportunity is reported, not applied, and Phase 5 applies every CONFIRMED finding without asking where it lands.

Emit one deduped, classified candidate list for Phase 4, and the set-aside out-of-scope list for Phase 7.

## Phase 4 — Verify

For each candidate, spawn one verifier agent with `subagent_type: Explore`, under the same reviewer stance as the finders. The verifier takes the defendant's side: the burden of proof is on the refactoring, and the comment or code is presumed innocent until the verifier constructs the refactoring concretely — the new names, the extraction boundaries, the deleted lines — and shows it is behavior-preserving and clearly superior.

The verdict axis is the value removing the flaw returns, never the cost of verifying it: needing to read further in the repository is never grounds to downgrade. The verifier is therefore obligated to read the callers, tests, and imports of any in-scope change — confirming a mechanical, behavior-preserving follow-through (rewriting imports after a rename, move, or consolidation) is verification work to be done, not context that defers the finding. Verdicts:

- **CONFIRMED** — the refactoring is constructible and behavior-preserving, and everything needed to prove that is reconstructible from repository content the verifier can read (the reviewed files plus their callers, tests, and imports); the verifier states it precisely. For a `restructure` (the one open-ended verb that reshapes control or data flow), CONFIRMED requires the verifier to exhibit the concrete target shape *and* an explicit behavior-preservation argument; absent either, it caps at PLAUSIBLE.
- **PLAUSIBLE** — the flaw is real but no amount of in-repository reading settles the fix: it turns on a judgment only a human holds — the stability of an API or contract external consumers depend on, runtime or performance behavior the tests cannot catch, or a design-taste reshaping. State the judgment at stake. Tag the finding **actionable** when a human's yes/no would gate an apply-able refactoring, or **FYI** when it only informs; only actionable findings reach Phase 6.
- **REFUTED** — the comment proves its innocence: quote the *why*-knowledge and why code cannot carry it, or show the "growth" is the minimal expression of the requirement. A comment that carries even one downstream effect, behavioral consequence, or external constraint that the post-refactor names and types cannot reconstruct is REFUTED — it survives. "Symmetry" or consistency with a sibling is never grounds to delete a comment whose content the new signature cannot carry. A why-not that names a real rationale but fails any Angle E survival gate is still REFUTED, not retained.

Refute only from evidence in the code — never for being "too minor" or "matter of taste".

## Phase 5 — Apply

Apply CONFIRMED refactorings directly, one logical change at a time: apply the restructuring first, then delete the comment it obsoleted. Never delete a comment whose refactoring was not applied. Every change is behavior-preserving — run the project's tests or type checks after applying when they exist, and revert any change that breaks them; a failing test is evidence the refactoring is not behavior-preserving, so the candidate is discarded (REFUTED), never routed to PLAUSIBLE — it is refuted by evidence, not awaiting a human's judgment.

Tests catch behavior regressions but not a green-but-wrong reshaping, so a `restructure` reaches this apply step only by passing the Phase 4 proof gate; one that cannot be proven behavior-preserving never applies here — it caps at PLAUSIBLE and goes to the human in Phase 6 rather than being committed blind.

## Phase 6 — Adjudicate

This phase fires only when the session can put a question to a human. Under headless, piped, or `-p` invocation it is skipped: every PLAUSIBLE finding stays in the Phase 7 report unchanged, which keeps the skill portable. Gate on whether a human can be reached, not on any brittle environment probe.

The orchestrator (main loop) runs this phase — it, not the Explore verifiers of Phases 2–4, is what can call AskUserQuestion. Present the **actionable** PLAUSIBLE findings — this run's, together with the Phase 1 survivors — as the options of multi-select questions within a single AskUserQuestion call — findings are options, never a question apiece, which is the interrogation this batching exists to avoid. The call holds up to four questions of up to four options each; rank findings by value and group them into questions by file or theme. Findings past that sixteen-option ceiling are **deferred** to the Phase 7 report, not dropped silently. For each finding the human selects, loop back into the Phase 5 apply procedure (behavior-preserving, running the project's tests or type checks). A finding left unselected is **declined** — the human saw it and ruled, so it goes to the report but, unlike a deferred one, is not carried over as pending.

## Phase 7 — Report

Summarize in the final message: applied refactorings (`file:line — refactoring — comment removed`), separating those applied directly (Phase 5) from those applied after the human approved them in Phase 6; the PLAUSIBLE findings left for the user — every FYI finding, plus the actionable ones the human declined or that were deferred (all actionable findings when Phase 6 was skipped) — each with the judgment at stake; out-of-scope opportunities; how many findings carried over as pending; and REFUTED comments that earned their place (one line each). If nothing was found, say the reviewed scope is clean and what was checked.

**Carry the un-adjudicated forward** — write the actionable PLAUSIBLE findings no human ruled on, whether deferred past the question cap or left by a skipped Phase 6, to `.git/code-refactor-pending.json` in the Phase 1 shape, anchors normalized as described there. Include the Phase 1 survivors that went unruled again. Delete the file when nothing is left pending.

**Record the review ref** — only in full-scope with a resolved base (not the working-tree-only fallback), and only once the other phases have completed. Run the project's formatter first where it has one, so the next `format` run does not immediately invalidate the ref. Then recompute `cur` with the Phase 0 block — Phases 5 and 6 may have changed the tree — and point the branch's ref at it:

```
commit="$(git commit-tree "$cur" -p HEAD -m "code-refactor review")"
git update-ref "refs/code-refactor/$(git rev-parse --abbrev-ref HEAD | tr '/' '%')" "$commit"
```

The tree is wrapped in a commit and hung on a ref because an unreferenced object is collected by `git gc`. `refs/code-refactor/*` is outside the default push refspec, so it stays local.

Reading the ref needs no base; writing one does: advancing the ref after a working-tree-only review would drop the committed-but-unreviewed files out of every later delta. A repository with no commits records nothing either, since `commit-tree -p HEAD` has no parent to name. Un-adjudicated findings do not hold the ref back — they travel in the pending file, which costs one AskUserQuestion next run rather than a re-review of everything.
