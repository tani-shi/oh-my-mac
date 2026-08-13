## Subagents & Agent Teams

- Run read-only work (searches, finders, verifiers, reviews) under a subagent type whose tool grants cannot write — `Explore`, not the default `general-purpose` — and fan it out as unnamed subagents, never a team. `Explore` and `Plan` do not receive CLAUDE.md, so a rule they must honor is restated in the delegation prompt.
- Use named teammates (Agent Teams) only for stateful collaboration where agents must respond to each other across turns. Compose by orthogonal roles, not headcount: 2 for pair work (implementer + reviewer), 3 for discussion (proponent, opponent, synthesizer) — 3 is the upper bound, since communication paths and coordination cost grow quadratically.
- When more perspectives are needed than a team allows, generate them independently with unnamed subagents and synthesize; independent generation preserves diversity that live discussion collapses.
