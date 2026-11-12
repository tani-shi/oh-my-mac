# /// script
# requires-python = ">=3.12"
# ///
"""Search X through the xAI Responses API x_search tool."""

import argparse
import datetime
import http.client
import json
import os
import pwd
import subprocess
import sys
import urllib.error
import urllib.request

KEYCHAIN_SERVICE = "xai-api-key"
ENDPOINT = "https://api.x.ai/v1/responses"
MODEL = "grok-4.7"
MAX_TURNS_LIMIT = 5
MAX_HANDLES = 20


def api_key() -> str:
    result = subprocess.run(
        ["security", "find-generic-password", "-a", pwd.getpwuid(os.getuid()).pw_name, "-s", KEYCHAIN_SERVICE, "-w"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0 or not result.stdout.strip():
        sys.exit("Error: xAI API key not found in Keychain. Run `make set-xai-api-key` in oh-my-mac.")
    return result.stdout.strip()


def handles(value: str) -> list[str]:
    result = [h.strip().lstrip("@") for h in value.split(",") if h.strip()]
    if not result:
        raise argparse.ArgumentTypeError("no handles given")
    if len(result) > MAX_HANDLES:
        raise argparse.ArgumentTypeError(f"at most {MAX_HANDLES} handles")
    return result


def iso_date(value: str) -> str:
    try:
        return datetime.date.fromisoformat(value).isoformat()
    except ValueError:
        raise argparse.ArgumentTypeError("expected YYYY-MM-DD") from None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Search X via xAI x_search")
    parser.add_argument("query")
    parser.add_argument("--from", dest="from_date", type=iso_date, help="YYYY-MM-DD, inclusive (UTC)")
    parser.add_argument("--to", dest="to_date", type=iso_date, help="YYYY-MM-DD, exclusive (UTC)")
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--handles", type=handles, help="only these handles (max 20)")
    group.add_argument("--exclude-handles", type=handles, help="ignore these handles (max 20)")
    parser.add_argument("--max-turns", type=int, default=2, choices=range(1, MAX_TURNS_LIMIT + 1))
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if args.from_date and args.to_date and args.from_date >= args.to_date:
        sys.exit("Error: --from must be earlier than --to")
    tool: dict = {"type": "x_search"}
    if args.handles:
        tool["allowed_x_handles"] = args.handles
    if args.exclude_handles:
        tool["excluded_x_handles"] = args.exclude_handles
    if args.from_date:
        tool["from_date"] = args.from_date
    if args.to_date:
        tool["to_date"] = args.to_date

    body = {
        "model": MODEL,
        "input": [{"role": "user", "content": args.query}],
        "tools": [tool],
        # Billing is per post fetched; max_turns is the only request-side cap.
        "max_turns": args.max_turns,
    }
    request = urllib.request.Request(
        ENDPOINT,
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {api_key()}"},
    )
    try:
        with urllib.request.urlopen(request, timeout=300) as response:
            data = json.load(response)
    except urllib.error.HTTPError as e:
        sys.exit(f"Error: xAI API returned {e.code}: {e.read().decode(errors='replace')}")
    except (OSError, http.client.HTTPException, ValueError) as e:
        sys.exit(f"Error: xAI API request failed: {e!r}")
    if not isinstance(data, dict):
        sys.exit(f"Error: unexpected xAI API response: {str(data)[:200]}")

    # Sources arrive as url_citation annotations; top-level citations is null.
    citations = list(data.get("citations") or [])
    texts = []
    for item in data.get("output") or []:
        if not isinstance(item, dict) or item.get("type") != "message":
            continue
        for content in item.get("content") or []:
            if not isinstance(content, dict) or content.get("type") != "output_text":
                continue
            texts.append(content.get("text") or "")
            citations += [
                a["url"]
                for a in content.get("annotations") or []
                if isinstance(a, dict) and a.get("type") == "url_citation" and a.get("url")
            ]

    tool_usage = (data.get("usage") or {}).get("server_side_tool_usage_details") or {}
    print(
        f"(x_search_calls={tool_usage.get('x_search_calls', 0)}, "
        f"x_posts_fetched={tool_usage.get('x_posts_fetched', 0)}, "
        f"x_users_fetched={tool_usage.get('x_users_fetched', 0)})",
        file=sys.stderr,
    )

    # A search that runs out of max_turns can return HTTP 200 with no message.
    details = data.get("error") or data.get("incomplete_details")
    if not any(texts):
        sys.exit(f"Error: no answer returned (status={data.get('status')}, details={details})")
    if data.get("status") != "completed":
        print(f"Warning: status={data.get('status')}, details={details}", file=sys.stderr)
    print("\n".join(texts))

    citations = list(dict.fromkeys(citations))
    if citations:
        print("\n## Sources")
        for url in citations:
            print(f"- {url}")


if __name__ == "__main__":
    main()
