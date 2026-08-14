INSTALL_STEPS := install-claude sync-claude-plugins install-vscode-extensions install-node install-ntn install-codex

.PHONY: help diff-config sync-config install update upgrade upgrade-apply refresh-agent-sentinel trust-taps test install-uv-tools $(INSTALL_STEPS)

.DEFAULT_GOAL := help

help: ## Show this help message
	@printf "Usage: make <target>\n\nTargets:\n"
	@awk -F':.*## ' '/^[a-zA-Z][a-zA-Z_-]*:.*## / {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

diff-config: ## Show differences between repo and local config
	@./config.zsh diff

sync-config: ## Sync config files only
	@./config.zsh sync

install: ## Install packages + sync config + install plugins
	$(MAKE) trust-taps
	brew bundle --no-upgrade --file=Brewfile
	$(MAKE) install-uv-tools
	$(MAKE) sync-config
	$(MAKE) $(INSTALL_STEPS)

update: ## Sync config + install missing packages (no upgrades)
	$(MAKE) trust-taps
	brew bundle --no-upgrade --file=Brewfile
	$(MAKE) install-uv-tools
	$(MAKE) sync-config
	$(MAKE) $(INSTALL_STEPS)
	brew cleanup

upgrade: ## Investigate upgrades in a Claude Code session, apply them, and commit
	claude "/upgrade"

refresh-agent-sentinel: ## Update agent-sentinel HEAD and refresh generated config
	$(MAKE) install-uv-tools AGENT_SENTINEL_UPGRADE=1
	@./scripts/refresh-agent-sentinel.zsh
	$(MAKE) test
	$(MAKE) diff-config

upgrade-apply: ## Apply the pinned versions (invoked from /upgrade)
	$(MAKE) trust-taps
	HOMEBREW_NO_INTERACTIVE=1 brew bundle --file=Brewfile
	brew cleanup
	$(MAKE) install-uv-tools
	$(MAKE) install-claude sync-claude-plugins install-ntn install-codex

trust-taps:
	@if [ -f config/homebrew/trusted-taps.txt ]; then \
		trusted=$$(brew trust --json v1 2>/dev/null); \
		while IFS= read -r tap || [ -n "$$tap" ]; do \
			[ -z "$$tap" ] && continue; \
			case "$$tap" in \#*) continue ;; esac; \
			if printf '%s' "$$trusted" | grep -q "\"$$tap\""; then \
				continue; \
			fi; \
			echo "Trusting Homebrew tap: $$tap"; \
			brew trust "$$tap" 2>&1 || echo "Warning: Failed to trust $$tap"; \
		done < config/homebrew/trusted-taps.txt; \
	else \
		echo "Skipping tap trust (trusted-taps.txt missing)"; \
	fi

test: ## Run the test suite
	@./scripts/test-discard.zsh
	@./scripts/test-config-sync.zsh

CLAUDE_VERSION := $(shell cat config/claude/version 2>/dev/null)
NTN_VERSION := $(shell cat config/ntn/version 2>/dev/null)
CODEX_VERSION := $(shell cat config/codex/version 2>/dev/null)

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

sync-claude-plugins:
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
		claude plugin list --json 2>/dev/null | jq -r '.[] | select(.scope == "user") | .id' | \
		while IFS= read -r plugin; do \
			[ -z "$$plugin" ] && continue; \
			if grep -qxF "$$plugin" config/claude/plugins.txt; then \
				continue; \
			fi; \
			echo "Uninstalling plugin: $$plugin"; \
			claude plugin uninstall "$$plugin" -y 2>/dev/null || echo "Warning: Failed to uninstall $$plugin"; \
		done; \
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

install-node:
	@if command -v fnm >/dev/null 2>&1 && [ -f config/fnm/version ]; then \
		version=$$(cat config/fnm/version); \
		eval "$$(fnm env)"; \
		if fnm list 2>/dev/null | grep -q "v$$version default"; then \
			echo "Node v$$version already installed and set as default"; \
		else \
			echo "Installing Node v$$version (fnm)..."; \
			fnm install "$$version" 2>&1 && fnm default "$$version" 2>&1 || echo "Warning: fnm install failed"; \
		fi; \
	else \
		echo "Skipping Node install (fnm not found or config/fnm/version missing)"; \
	fi

install-ntn:
	@if [ -z "$(NTN_VERSION)" ]; then \
		echo "Skipping Notion CLI (config/ntn/version missing)"; \
	else \
		command -v fnm >/dev/null 2>&1 && eval "$$(fnm env)"; \
		if ! command -v npm >/dev/null 2>&1; then \
			echo "Skipping Notion CLI (npm not found)"; \
		else \
			current=$$(ntn --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1) || true; \
			if [ "$$current" = "$(NTN_VERSION)" ]; then \
				echo "Notion CLI (ntn) $(NTN_VERSION) already installed"; \
			else \
				echo "Installing Notion CLI (ntn) $(NTN_VERSION)..."; \
				npm install -g "ntn@$(NTN_VERSION)" 2>&1 || echo "Warning: Failed to install ntn"; \
			fi; \
		fi; \
	fi

install-codex:
	@if [ -z "$(CODEX_VERSION)" ]; then \
		echo "Skipping Codex CLI (config/codex/version missing)"; \
	else \
		command -v fnm >/dev/null 2>&1 && eval "$$(fnm env)"; \
		if ! command -v npm >/dev/null 2>&1; then \
			echo "Skipping Codex CLI (npm not found)"; \
		else \
			current=$$(npm ls -g --depth=0 --json @openai/codex 2>/dev/null | jq -r '.dependencies["@openai/codex"].version // empty'); \
			if [ "$$current" = "$(CODEX_VERSION)" ]; then \
				echo "Codex CLI $(CODEX_VERSION) already installed"; \
			else \
				echo "Installing Codex CLI $(CODEX_VERSION)..."; \
				npm install -g "@openai/codex@$(CODEX_VERSION)"; \
			fi; \
		fi; \
	fi

install-uv-tools:
	@if command -v uv >/dev/null 2>&1 && [ -f config/uv/tools.txt ]; then \
		installed=$$(uv tool list 2>&1) || { echo "$$installed"; exit 1; }; \
		while IFS= read -r tool || [ -n "$$tool" ]; do \
			[ -z "$$tool" ] && continue; \
			echo "Installing uv tool: $$tool"; \
			case "$$tool" in \
				agent-sentinel*) \
					options=""; \
					if echo "$$installed" | grep -q '^claude-sentinel ' && ! echo "$$installed" | grep -q '^agent-sentinel '; then \
						options="--force"; \
					fi; \
					if [ "$(AGENT_SENTINEL_UPGRADE)" = "1" ]; then \
						options="$$options --upgrade"; \
					fi; \
					uv tool install $$options "$$tool" 2>&1 || exit 1; \
					command -v agent-sentinel >/dev/null 2>&1 || { echo "Error: agent-sentinel executable not found after install"; exit 1; }; \
					agent-sentinel --help >/dev/null 2>&1 || { echo "Error: agent-sentinel executable check failed"; exit 1; }; \
					;; \
				*) uv tool install "$$tool" 2>&1 || echo "Warning: Failed to install $$tool" ;; \
			esac; \
		done < config/uv/tools.txt; \
	else \
		echo "Error: uv not found or config/uv/tools.txt missing"; \
		exit 1; \
	fi
