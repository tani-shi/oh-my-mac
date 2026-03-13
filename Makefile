.PHONY: diff-config sync-config install update install-claude-plugins update-claude-plugins

diff-config:
	@./config.zsh diff

sync-config:
	@./config.zsh sync

install: sync-config install-claude-plugins
	brew bundle --no-upgrade --file=Brewfile

update: sync-config update-claude-plugins
	brew bundle --file=Brewfile
	brew cleanup

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
	@if command -v claude >/dev/null 2>&1; then \
		claude plugins update 2>/dev/null || echo "Warning: Failed to update Claude Code plugins"; \
	fi
