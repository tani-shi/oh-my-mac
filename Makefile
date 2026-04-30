.PHONY: help diff-config sync-config install update upgrade snapshot-versions install-claude install-claude-plugins install-pnpm-globals install-uv-tools install-vscode-extensions

.DEFAULT_GOAL := help

help: ## Show this help message
	@printf "Usage: make <target>\n\nTargets:\n"
	@awk -F':.*## ' '/^[a-zA-Z][a-zA-Z_-]*:.*## / {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

diff-config: ## Show differences between repo and local config
	@./config.zsh diff

sync-config: ## Sync config files only
	@./config.zsh sync

install: ## Install packages + sync config + install plugins
	brew bundle --no-upgrade --file=Brewfile
	$(MAKE) sync-config install-claude install-claude-plugins install-pnpm-globals install-uv-tools install-vscode-extensions

update: sync-config install-claude install-claude-plugins install-pnpm-globals install-uv-tools install-vscode-extensions ## Sync config + install missing packages (no upgrades)
	brew bundle --no-upgrade --file=Brewfile
	brew cleanup

upgrade: ## Investigate upgrades via Claude Agent SDK, apply them, and auto-commit
	@uv run scripts/upgrade.py
	brew upgrade
	brew cleanup
	$(MAKE) install-claude install-claude-plugins install-pnpm-globals install-uv-tools
	$(MAKE) snapshot-versions
	@./scripts/commit-upgrade.zsh

snapshot-versions: ## Save installed versions to versions.json
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

install-pnpm-globals:
	@if command -v pnpm >/dev/null 2>&1 && [ -f config/pnpm/globals.txt ]; then \
		installed=$$(pnpm list -g --depth=0 2>/dev/null); \
		while IFS= read -r pkg || [ -n "$$pkg" ]; do \
			[ -z "$$pkg" ] && continue; \
			name=$${pkg%%@*}; \
			if echo "$$installed" | grep -q "$$name"; then \
				continue; \
			fi; \
			echo "Installing pnpm global: $$pkg"; \
			pnpm add -g "$$pkg" 2>&1 || echo "Warning: Failed to install $$pkg"; \
		done < config/pnpm/globals.txt; \
	else \
		echo "Skipping pnpm globals (pnpm not found or globals.txt missing)"; \
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
