# /// script
# requires-python = ">=3.11"
# dependencies = ["claude-agent-sdk", "anyio"]
# ///
"""Non-interactive dependency upgrade investigation using Claude Agent SDK."""

import anyio
import sys
import threading
import time
from pathlib import Path

from claude_agent_sdk import (
    AssistantMessage,
    ClaudeAgentOptions,
    ResultMessage,
    query,
)

PROJECT_ROOT = Path(__file__).resolve().parent.parent

SYSTEM_PROMPT = """\
You are a dependency upgrade investigator for the oh-my-mac dotfiles repository.

CRITICAL CONSTRAINTS:
- You may READ any file and RUN read-only commands (brew outdated, gh api, cat, etc.)
- You may UPDATE these config files ONLY:
  config/claude/version, config/sheldon/plugins.toml, config/uv/tools.txt
- You must NEVER run: brew upgrade, brew install, brew uninstall, pip install, \
uv install, uv tool install, claude install, npm install, or ANY command that \
modifies installed software
- You must NEVER run: make snapshot-versions or any make target

UPGRADE POLICY:
- Apply security patches unconditionally
- Allow feature updates only if no incidents are reported in changelogs/advisories
- For Claude Code: aim to keep the pinned version at the latest release. \
Check the latest version via `npm view @anthropic-ai/claude-code version`. \
Upgrade to that version UNLESS one of the following risks is detected:
  (a) Breaking changes documented in the CHANGELOG.md at anthropics/claude-code \
      between the current pinned version and the latest that affect this \
      repo's configuration surface (settings.json schema, hooks, slash \
      commands, MCP, plugins, agents, skills, keybindings).
  (b) Trending critical bug reports on GitHub Issues at anthropics/claude-code \
      against the latest version — meaning multiple distinct users report \
      the same unresolved regression (crashes, hangs, data loss, broken \
      core flows). A handful of stale or single-user reports does NOT count.
  If either risk is detected, keep the current version and note the reason \
  in the summary. Otherwise upgrade to the latest published version regardless \
  of how recently it was released.
- For sheldon plugins, always use tag pinning (or rev if no tags exist)
- For uv tools, use @tag or @commit suffix (except claude-sentinel which uses HEAD)

Use the Agent tool to investigate multiple dependencies in parallel when possible.\
"""

PROMPT = """\
Investigate available upgrades for oh-my-mac dependencies.

1. Run `brew outdated` to check for Homebrew package updates (both formulae and casks).
2. For each plugin in config/sheldon/plugins.toml that has a GitHub source, \
check for newer tags using `gh api repos/{owner}/{repo}/tags --jq '.[0].name'` \
and compare with the current tag/rev.
3. Check the latest Claude Code version via \
`npm view @anthropic-ai/claude-code version`. Default action: upgrade \
config/claude/version to that latest version. Skip the upgrade only if \
either (a) the CHANGELOG.md at anthropics/claude-code shows breaking \
changes between the current pinned version and the latest that affect \
this repo's config surface, or (b) GitHub Issues at anthropics/claude-code \
show trending unresolved critical bug reports (crashes, hangs, data loss) \
from multiple users against the latest version. Publish date is no longer \
a gating criterion — pursue the latest release whenever it is safe.
4. Check config/uv/tools.txt for any tools that can be updated.
5. For each potential update, research changelogs, security advisories, and \
incident reports via web search.
6. Update ONLY the config files for approved upgrades. Do not run any \
installation commands.
7. Print a summary of all changes made and any updates that were skipped \
(with reasons).\
"""


SPINNER_FRAMES = ["\u280b", "\u2819", "\u2839", "\u2838", "\u283c", "\u2834", "\u2826", "\u2827", "\u2807", "\u280f"]


class LoadingSpinner:
    """Animated spinner shown while waiting for the first tool use."""

    def __init__(self) -> None:
        self._thinking: str = ""
        self._active = True
        self._lock = threading.Lock()
        self._thread = threading.Thread(target=self._run, daemon=True)

    def start(self) -> None:
        self._thread.start()

    def set_thinking(self, text: str) -> None:
        with self._lock:
            first_line = text.strip().split("\n")[0][:80]
            self._thinking = first_line

    def stop(self) -> None:
        self._active = False
        self._thread.join(timeout=1)
        sys.stderr.write("\r\033[K")
        sys.stderr.flush()

    def _run(self) -> None:
        idx = 0
        while self._active:
            frame = SPINNER_FRAMES[idx % len(SPINNER_FRAMES)]
            with self._lock:
                label = self._thinking or "Starting upgrade investigation..."
            sys.stderr.write(f"\r\033[K{frame} {label}")
            sys.stderr.flush()
            idx += 1
            time.sleep(0.1)


TOOL_ICONS = {
    "Read": "\U0001f50d",
    "Glob": "\U0001f50d",
    "Grep": "\U0001f50d",
    "Write": "\u270f\ufe0f ",
    "Edit": "\u270f\ufe0f ",
    "Bash": "\u26a1",
    "WebSearch": "\U0001f310",
    "WebFetch": "\U0001f310",
    "Agent": "\U0001f916",
}


def _format_tool_use(block: object) -> str:
    name = getattr(block, "name", "")
    inp = getattr(block, "input", {})
    icon = TOOL_ICONS.get(name, "\u2022")

    if name in ("Read", "Glob", "Grep"):
        target = inp.get("file_path") or inp.get("pattern") or inp.get("path", "")
        return f"{icon} {name} {target}"
    if name == "Bash":
        desc = inp.get("description", "")
        cmd = inp.get("command", "")
        label = desc if desc else cmd.split("\n")[0][:80]
        return f"{icon} {label}"
    if name in ("Write", "Edit"):
        path = inp.get("file_path", "")
        return f"{icon} {name} {path}"
    if name == "WebSearch":
        return f"{icon} WebSearch: {inp.get('query', '')}"
    if name == "WebFetch":
        return f"{icon} WebFetch: {inp.get('url', '')}"
    if name == "Agent":
        desc = inp.get("description", "")
        return f"{icon} Agent: {desc}"

    return f"\u2022 {name}"


def log_message(message: AssistantMessage, spinner: LoadingSpinner | None) -> bool:
    """Log an assistant message. Returns True if spinner should be stopped."""
    should_stop_spinner = False
    for block in message.content:
        block_type = getattr(block, "type", None)
        if block_type == "thinking":
            text = getattr(block, "thinking", "")
            if spinner and text:
                spinner.set_thinking(text)
        elif block_type == "tool_use":
            should_stop_spinner = True
            print(_format_tool_use(block))
        elif block_type == "text":
            text = getattr(block, "text", "")
            if text.strip():
                should_stop_spinner = True
                print(f"\n{text}")
    return should_stop_spinner


async def main() -> int:
    spinner = LoadingSpinner()
    spinner.start()
    spinner_active = True

    async for message in query(
        prompt=PROMPT,
        options=ClaudeAgentOptions(
            cwd=str(PROJECT_ROOT),
            system_prompt=SYSTEM_PROMPT,
            allowed_tools=[
                "Read",
                "Glob",
                "Grep",
                "Write",
                "Edit",
                "Bash",
                "WebSearch",
                "WebFetch",
                "Agent",
            ],
            permission_mode="bypassPermissions",
            max_turns=50,
            setting_sources=["project"],
        ),
    ):
        if isinstance(message, AssistantMessage):
            stop = log_message(message, spinner if spinner_active else None)
            if stop and spinner_active:
                spinner.stop()
                spinner_active = False
        elif isinstance(message, ResultMessage):
            if spinner_active:
                spinner.stop()
                spinner_active = False
            print("\n--- Upgrade investigation complete ---")
            if message.result:
                print(message.result)
            return 0
    if spinner_active:
        spinner.stop()
    return 0


if __name__ == "__main__":
    sys.exit(anyio.run(main))
