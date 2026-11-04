# Project instructions

This repository configures a macOS workstation.

## Configuration sources

- Edit files under `config/`, not their installed copies.
- `config/agents/instructions.md` contains user-global CLI instructions. `config/claude/instructions.md` and `config/codex/instructions.md` add CLI-specific instructions.
- These instructions apply in every repository. This repository's rules belong in `AGENTS.md`.
- Use `make diff-config` to inspect configuration changes and `make sync-config` to apply them separately from installation.
- Repository skills live in `.agents/skills/`. `.claude/skills` is a symlink to it so Claude Code loads the same skills.
- Authentication belongs in the tools' local auth storage or environment, never in this repository.

## Dependency versioning

### Homebrew

- `make update` must be safe to run at any time, without quitting running apps.
  - GUI apps go in `config/homebrew/Brewfile.install-only` and update themselves on restart.
  - CLI casks go in `Brewfile`. When a CLI has its own updater, such as `gcloud components update`, run it from `make update`.
- When dropping a package from either Brewfile, add it to `config/homebrew/Brewfile.removed` so existing machines uninstall it. Delete the entry if the package is added back.
- Declare every required non-official Homebrew tap in `config/homebrew/trusted-taps.txt`, even when its resolved name differs from the requested tap.

### Other tools

- Pin config-tools packages with `==` in `config/uv/config-tools.txt`.
- Remote Sheldon plugins use tags, or revisions when no tag exists.
- uv tools use tags or commits except the intentionally HEAD-tracking `agent-sentinel` and `claude-sessions`.
- tenv uses a project's `.terraform-version` as is. Otherwise it resolves `required_version` capped by `config/tenv/terraform-version`; raise that file when a project needs a newer Terraform.
