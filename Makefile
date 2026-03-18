.PHONY: diff-config sync-config install update install-claude install-claude-plugins update-claude update-claude-plugins install-uv-tools update-uv-tools

diff-config:
	@./config.zsh diff

sync-config:
	@./config.zsh sync

install: sync-config install-claude install-claude-plugins install-uv-tools
	brew bundle --no-upgrade --file=Brewfile

update: sync-config update-claude update-claude-plugins update-uv-tools
	brew bundle --file=Brewfile
	brew cleanup

install-claude:
	@if ! command -v claude >/dev/null 2>&1; then \
		echo "Installing Claude Code..."; \
		curl -fsSL https://claude.ai/install.sh | bash; \
	else \
		echo "Claude Code already installed"; \
	fi

update-claude:
	@if command -v claude >/dev/null 2>&1; then \
		echo "Updating Claude Code..."; \
		claude update 2>&1 || echo "Warning: Failed to update Claude Code"; \
	else \
		echo "Skipping Claude Code update (claude not found)"; \
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

update-claude-plugins:
	@if command -v claude >/dev/null 2>&1 && [ -f config/claude/plugins.txt ]; then \
		echo "Updating plugin marketplaces..."; \
		claude plugin marketplace update 2>/dev/null || echo "Warning: Failed to update marketplaces"; \
		while IFS= read -r plugin || [ -n "$$plugin" ]; do \
			[ -z "$$plugin" ] && continue; \
			echo "Updating plugin: $$plugin"; \
			claude plugin update "$$plugin" 2>/dev/null || echo "Warning: Failed to update $$plugin"; \
		done < config/claude/plugins.txt; \
	else \
		echo "Skipping Claude Code plugins (claude not found or plugins.txt missing)"; \
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

update-uv-tools:
	@if command -v uv >/dev/null 2>&1 && [ -f config/uv/tools.txt ]; then \
		while IFS= read -r tool || [ -n "$$tool" ]; do \
			[ -z "$$tool" ] && continue; \
			echo "Updating uv tool: $$tool"; \
			uv tool install --force "$$tool" 2>&1 || echo "Warning: Failed to update $$tool"; \
		done < config/uv/tools.txt; \
	else \
		echo "Skipping uv tools (uv not found or tools.txt missing)"; \
	fi
