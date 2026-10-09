"""Codex hook that forwards required-information stops to an ntfy topic."""

from __future__ import annotations

import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path


MAX_MESSAGE_LENGTH = 700
BLOCKING_STOP_PATTERNS = (
    re.compile(
        r"\b(?:blocked until|waiting for your (?:input|answer|response|choice|decision|confirmation)|"
        r"waiting on your (?:input|answer|response|choice|decision|confirmation)|"
        r"i need your (?:input|answer|response|choice|decision|confirmation|preference)|"
        r"i need to know|i need you to|i still need (?:you|your)|"
        r"before (?:i|we) can (?:continue|proceed|finish|complete)|"
        r"(?:i|we) (?:can't|cannot) (?:continue|proceed|finish|complete) without|"
        r"(?:i|we) (?:can't|cannot) (?:continue|proceed|finish|complete) until)\b",
        re.IGNORECASE,
    ),
    re.compile(
        r"\b(?:please|could you|can you)\s+(?:provide|confirm|clarify|choose|select|decide|"
        r"tell me|specify|share|answer)\b[^.!?]*"
        r"(?:\?|(?:so|before|until)\s+(?:i|we)\s+(?:can|know|proceed|continue)|"
        r"for me to (?:proceed|continue|finish))",
        re.IGNORECASE,
    ),
    re.compile(
        r"\b(?:which|what|where|when|who|how many|how much|how long)\b"
        r"[^?!.]{0,160}\b(?:should i|do you|can you|could you|please)\b[^?!.]*\?",
        re.IGNORECASE,
    ),
)


def config_path() -> Path:
    app_data = os.environ.get("APPDATA")
    if app_data:
        return Path(app_data) / "GptNotify" / "config.json"
    return Path.home() / ".config" / "gpt-notify" / "config.json"


def clean_text(value: object, limit: int = MAX_MESSAGE_LENGTH) -> str:
    if not isinstance(value, str):
        return ""
    text = re.sub(r"\s+", " ", value).strip()
    if len(text) > limit:
        text = text[: limit - 1].rstrip() + "…"
    return text


def stop_requests_required_input(value: object) -> bool:
    if not isinstance(value, str) or not value.strip():
        return False
    # Ignore code examples so a question embedded in code does not turn an
    # otherwise completed response into a notification.
    message = re.sub(r"```.*?```|`[^`]*`", " ", value, flags=re.DOTALL)
    return any(pattern.search(message) for pattern in BLOCKING_STOP_PATTERNS)


def build_notification(event: dict) -> tuple[str, str, str]:
    event_name = event.get("hook_event_name")
    if event_name == "Stop":
        raw_message = event.get("last_assistant_message")
        if not stop_requests_required_input(raw_message):
            return "", "", ""
        last_message = clean_text(raw_message)
        return "Codex needs your input", last_message, "question"

    return "", "", ""


def main() -> int:
    try:
        event = json.load(sys.stdin)
    except (json.JSONDecodeError, OSError):
        return 0
    if not isinstance(event, dict):
        return 0

    title, message, tag = build_notification(event)
    if not title:
        return 0

    try:
        config = json.loads(config_path().read_text(encoding="utf-8-sig"))
        topic = config.get("topic")
        server = config.get("server", "https://ntfy.sh").rstrip("/")
    except (OSError, json.JSONDecodeError, AttributeError):
        return 0

    if not isinstance(topic, str) or not re.fullmatch(r"[A-Za-z0-9_-]{16,128}", topic):
        return 0
    if not isinstance(server, str) or not server.startswith("https://"):
        return 0

    request = urllib.request.Request(
        f"{server}/{topic}",
        data=message.encode("utf-8"),
        headers={
            "Content-Type": "text/plain; charset=utf-8",
            "Title": title,
            "Priority": "high" if tag == "warning" else "default",
            "Tags": tag,
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=2):
            pass
    except (urllib.error.URLError, TimeoutError, OSError):
        # Notification failures must never block a Codex turn.
        return 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
