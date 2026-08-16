INSTALL_STEPS := install-claude sync-claude-plugins install-node install-ntn install-codex

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
		trusted=$$(brew trust --json v1 2>/dev/null) || exit 1; \
		failed=0; \
		while IFS= read -r tap || [ -n "$$tap" ]; do \
			[ -z "$$tap" ] && continue; \
			case "$$tap" in \#*) continue ;; esac; \
			if printf '%s' "$$trusted" | grep -q "\"$$tap\""; then \
				continue; \
			fi; \
			echo "Trusting Homebrew tap: $$tap"; \
			if ! brew trust "$$tap" 2>&1; then \
				echo "Error: failed to trust $$tap" >&2; \
				failed=1; \
			fi; \
		done < config/homebrew/trusted-taps.txt; \
		[ "$$failed" -eq 0 ] || exit 1; \
	else \
		echo "Error: config/homebrew/trusted-taps.txt missing" >&2; \
		exit 1; \
	fi

test: ## Run the test suite
	@./scripts/test-discard.zsh
	@./scripts/test-commit-upgrade.zsh
	@./scripts/test-config-sync.zsh

CLAUDE_VERSION := $(shell cat config/claude/version 2>/dev/null)
NTN_VERSION := $(shell cat config/ntn/version 2>/dev/null)
CODEX_VERSION := $(shell cat config/codex/version 2>/dev/null)

install-claude:
	@if [ -z "$(CLAUDE_VERSION)" ]; then \
		echo "Error: config/claude/version not found"; exit 1; \
	fi
	@version="$(CLAUDE_VERSION)"; \
	current=$$(claude --version 2>/dev/null | awk '{print $$1}') || true; \
	if [ "$$current" = "$$version" ]; then \
		echo "Claude Code $$version already installed"; \
	else \
		echo "Installing Claude Code $$version..."; \
		claude install "$$version" 2>&1 || curl -fsSL https://claude.ai/install.sh | bash -s -- "$$version"; \
		installed=$$(claude --version 2>/dev/null | awk '{print $$1}') || true; \
		if [ "$$installed" != "$$version" ]; then \
			echo "Error: installed Claude Code version $${installed:-not found}, expected $$version" >&2; \
			exit 1; \
		fi; \
	fi

sync-claude-plugins:
	@if ! command -v claude >/dev/null 2>&1; then \
		echo "Error: claude not found" >&2; exit 1; \
	fi
	@if [ ! -f config/claude/plugins.txt ]; then \
		echo "Error: config/claude/plugins.txt missing" >&2; exit 1; \
	fi
	@settings="$$HOME/.claude/settings.json"; \
	while IFS= read -r plugin || [ -n "$$plugin" ]; do \
		[ -z "$$plugin" ] && continue; \
		if [ -f "$$settings" ] && jq -e --arg p "$$plugin" '.enabledPlugins[$$p]' "$$settings" >/dev/null 2>&1; then \
			continue; \
		fi; \
		echo "Installing plugin: $$plugin"; \
		claude plugin install "$$plugin" || exit 1; \
	done < config/claude/plugins.txt; \
	installed_json=$$(claude plugin list --json) || exit 1; \
	installed=$$(printf '%s\n' "$$installed_json" | jq -r '.[] | select(.scope == "user") | .id') || exit 1; \
	printf '%s\n' "$$installed" | while IFS= read -r plugin; do \
		[ -z "$$plugin" ] && continue; \
		if grep -qxF "$$plugin" config/claude/plugins.txt; then \
			continue; \
		fi; \
		echo "Uninstalling plugin: $$plugin"; \
		claude plugin uninstall "$$plugin" -y || exit 1; \
	done

install-node:
	@if ! command -v fnm >/dev/null 2>&1; then \
		echo "Error: fnm not found" >&2; exit 1; \
	fi
	@if [ ! -f config/fnm/version ]; then \
		echo "Error: config/fnm/version missing" >&2; exit 1; \
	fi
	@version=$$(cat config/fnm/version); \
	environment=$$(fnm env) || exit 1; \
	eval "$$environment" || exit 1; \
	if fnm list 2>/dev/null | grep -q "v$$version default"; then \
		echo "Node v$$version already installed and set as default"; \
	else \
		echo "Installing Node v$$version (fnm)..."; \
		fnm install "$$version" || exit 1; \
		fnm default "$$version" || exit 1; \
	fi

install-ntn:
	@if [ -z "$(NTN_VERSION)" ]; then \
		echo "Error: config/ntn/version missing" >&2; \
		exit 1; \
	else \
		if command -v fnm >/dev/null 2>&1; then \
			environment=$$(fnm env) || exit 1; \
			eval "$$environment" || exit 1; \
		fi; \
		if ! command -v npm >/dev/null 2>&1; then \
			echo "Error: npm not found" >&2; \
			exit 1; \
		else \
			current=$$(ntn --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1) || true; \
			if [ "$$current" = "$(NTN_VERSION)" ]; then \
				echo "Notion CLI (ntn) $(NTN_VERSION) already installed"; \
			else \
				echo "Installing Notion CLI (ntn) $(NTN_VERSION)..."; \
				npm install -g "ntn@$(NTN_VERSION)"; \
			fi; \
		fi; \
	fi

install-codex:
	@if [ -z "$(CODEX_VERSION)" ]; then \
		echo "Error: config/codex/version missing" >&2; \
		exit 1; \
	else \
		if command -v fnm >/dev/null 2>&1; then \
			environment=$$(fnm env) || exit 1; \
			eval "$$environment" || exit 1; \
		fi; \
		if ! command -v npm >/dev/null 2>&1; then \
			echo "Error: npm not found" >&2; \
			exit 1; \
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
				*) uv tool install "$$tool" 2>&1 || exit 1 ;; \
			esac; \
		done < config/uv/tools.txt; \
	else \
		echo "Error: uv not found or config/uv/tools.txt missing"; \
		exit 1; \
	fi
