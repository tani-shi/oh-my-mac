# Project instructions

This repository configures a macOS workstation.

## Configuration sources

- Edit files under `config/`, not their installed copies.
- `config/agents/instructions.md` contains user-global CLI instructions. `config/claude/instructions.md` and `config/codex/instructions.md` add CLI-specific instructions.
- These instructions apply in every repository. This repository's rules belong in `AGENTS.md`.
- Use `make diff-config` to inspect configuration changes and `make sync-config` to apply them separately from installation.
- Authentication belongs in the tools' local auth storage or environment, never in this repository.

## Dependency versioning

- Put self-updating apps in `config/homebrew/Brewfile.install-only`.
- Pin config-tools packages with `==` in `config/uv/config-tools.txt`.
- Remote Sheldon plugins use tags, or revisions when no tag exists.
- uv tools use tags or commits except the intentionally HEAD-tracking `agent-sentinel` and `claude-sessions`.
- Declare every required non-official Homebrew tap in `config/homebrew/trusted-taps.txt`, even when its resolved name differs from the requested tap.
