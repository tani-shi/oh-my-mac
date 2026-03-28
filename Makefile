.PHONY: diff-config sync-config install update upgrade snapshot-versions install-claude install-claude-plugins install-uv-tools install-vscode-extensions

diff-config:
	@./config.zsh diff

sync-config:
	@./config.zsh sync

install: sync-config install-claude install-claude-plugins install-uv-tools install-vscode-extensions
	brew bundle --no-upgrade --file=Brewfile

update: sync-config install-claude-plugins install-uv-tools install-vscode-extensions
	brew bundle --no-upgrade --file=Brewfile
	brew cleanup

upgrade:
	claude "Investigate available upgrades for oh-my-mac dependencies.\
	1. Run brew outdated to check for Homebrew package updates.\
	2. Check GitHub for newer tags of each plugin in config/sheldon/plugins.toml.\
	3. Check the latest Claude Code version and compare with config/claude/version.\
	4. For each update, research changelogs, security advisories, and incident reports.\
	5. Recommend security patches. Allow feature updates only if no incidents are reported.\
	6. Apply only user-approved updates (brew upgrade, plugins.toml tags, config/claude/version).\
	7. Run make snapshot-versions to update versions.json."

snapshot-versions:
	@echo "Snapshotting installed versions..."
	@./scripts/snapshot-versions.zsh > versions.json
	@echo "Saved to versions.json"

CLAUDE_VERSION := $(shell cat config/claude/version 2>/dev/null)

install-claude:
	@if [ -z "$(CLAUDE_VERSION)" ]; then \
		echo "Error: config/claude/version not found"; exit 1; \
	fi
	@current=$$(claude --version 2>/dev/null | awk '{print $$1}') || true; \
	if [ "$$current" = "$(CLAUDE_VERSION)" ]; then \
		echo "Claude Code $(CLAUDE_VERSION) already installed"; \
	else \
		echo "Installing Claude Code $(CLAUDE_VERSION)..."; \
		claude install "$(CLAUDE_VERSION)" 2>&1 || curl -fsSL https://claude.ai/install.sh | bash; \
	fi

install-claude-plugins:
	@if command -v claude >/dev/null 2>&1 && [ -f config/claude/plugins.txt ]; then \
		settings="$$HOME/.claude/settings.json"; \
		while IFS= read -r plugin || [ -n "$$plugin" ]; do \
			[ -z "$$plugin" ] && continue; \
			if [ -f "$$settings" ] && jq -e --arg p "$$plugin" '.enabledPlugins[$$p]' "$$settings" >/dev/null 2>&1; then \
				continue; \
			fi; \
			echo "Installing plugin: $$plugin"; \
			claude plugin install "$$plugin" 2>/dev/null || echo "Warning: Failed to install $$plugin"; \
		done < config/claude/plugins.txt; \
	else \
		echo "Skipping Claude Code plugins (claude not found or plugins.txt missing)"; \
	fi

install-vscode-extensions:
	@if command -v code >/dev/null 2>&1 && [ -f config/vscode/extensions.txt ]; then \
		installed=$$(code --list-extensions 2>/dev/null); \
		while IFS= read -r ext || [ -n "$$ext" ]; do \
			[ -z "$$ext" ] && continue; \
			case "$$ext" in \#*) continue ;; esac; \
			if ! echo "$$installed" | grep -qix "$$ext"; then \
				echo "Installing VSCode extension: $$ext"; \
				code --install-extension "$$ext" 2>/dev/null || echo "Warning: Failed to install $$ext"; \
			fi; \
		done < config/vscode/extensions.txt; \
	else \
		echo "Skipping VSCode extensions (code not found or extensions.txt missing)"; \
	fi

install-uv-tools:
	@if command -v uv >/dev/null 2>&1 && [ -f config/uv/tools.txt ]; then \
		while IFS= read -r tool || [ -n "$$tool" ]; do \
			[ -z "$$tool" ] && continue; \
			echo "Installing uv tool: $$tool"; \
			uv tool install "$$tool" 2>&1 || echo "Warning: Failed to install $$tool"; \
		done < config/uv/tools.txt; \
	else \
		echo "Skipping uv tools (uv not found or tools.txt missing)"; \
	fi
