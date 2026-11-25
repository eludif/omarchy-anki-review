"""Translate a widget action into requests to the local Anki reviewer."""

import fcntl
import http.client
import json
import os
import re
import shutil
import subprocess
import sys
import time
from html.parser import HTMLParser
from pathlib import Path

MAX_RESPONSE = 2 * 1024 * 1024


class ReviewError(Exception):
    pass


class CardText(HTMLParser):
    def __init__(self):
        super().__init__()
        self.parts = []
        self.hidden = None

    def handle_starttag(self, tag, attrs):
        if tag in {"script", "style", "template"} and self.hidden is None:
            self.hidden = tag
        elif self.hidden is None and tag in {"br", "hr", "div", "p", "li", "tr"}:
            self.parts.append("\n")

    def handle_endtag(self, tag):
        if tag == self.hidden:
            self.hidden = None
        elif self.hidden is None and tag in {"div", "p", "li", "tr"}:
            self.parts.append("\n")

    def handle_data(self, data):
        if self.hidden is None:
            self.parts.append(data)


def plain_text(html):
    parser = CardText()
    parser.feed(html)
    parser.close()
    text = re.sub(r"\[sound:[^\]]+\]", "", "".join(parser.parts))
    lines = [" ".join(line.split()) for line in text.splitlines()]
    return "\n".join(line for line in lines if line)[:16000]


def request(action, **params):
    connection = http.client.HTTPConnection("127.0.0.1", 8765, timeout=3)
    try:
        connection.request(
            "POST", "/", json.dumps(dict(action=action, version=6, params=params)),
            {"Content-Type": "application/json"},
        )
        response = connection.getresponse()
        body = response.read(MAX_RESPONSE + 1)
        if response.status != 200 or len(body) > MAX_RESPONSE:
            raise ReviewError("response")
        payload = json.loads(body)
    finally:
        connection.close()

    if not isinstance(payload, dict) or "result" not in payload or "error" not in payload:
        raise ReviewError("response")
    if payload["error"] is not None:
        raise ReviewError("api")
    return payload["result"]


def current_card():
    if request("guiReviewActive") is not True:
        return None

    card = request("guiCurrentCard")
    card_id = card["cardId"]
    if type(card_id) is not int or card_id <= 0:
        raise ReviewError("response")

    buttons = card["buttons"]
    # Anki uses physical rating positions after removing unavailable buttons.
    labels = {2: ["again", "good"], 3: ["again", "good", "easy"],
              4: ["again", "hard", "good", "easy"]}
    if buttons != list(range(1, len(buttons) + 1)) or len(buttons) not in labels:
        raise ReviewError("response")

    return {
        "id": str(card_id),
        "front": plain_text(card["question"]),
        "back": plain_text(
            re.split(r"<hr\b[^>]*\bid\s*=\s*[\"']?answer\b[^>]*>", card["answer"],
                     maxsplit=1, flags=re.IGNORECASE)[-1]
        ),
        "ratings": labels[len(buttons)],
    }


def review(operation, args):
    if operation == "launch":
        return launch_anki()

    if operation == "decks":
        decks = request("deckNames")
        if not isinstance(decks, list) or not all(isinstance(name, str) for name in decks):
            raise ReviewError("response")
        return {"decks": sorted(decks[:5000], key=str.casefold)}

    if operation == "start":
        if request("guiDeckReview", name=args[0]) is not True:
            raise ReviewError("deck")
        return {"card": current_card()}

    card = current_card()
    if not card or card["id"] != args[0]:
        raise ReviewError("changed")

    if operation == "reveal":
        if request("guiShowAnswer") is not True:
            raise ReviewError("changed")
        return {"card": card}

    if operation == "grade":
        ease = int(args[1])
        if not 1 <= ease <= len(card["ratings"]):
            raise ReviewError("changed")
        if request("guiAnswerCard", ease=ease) is not True:
            raise ReviewError("changed")
        return {"card": current_card()}

    raise ReviewError("response")


# The compositor starts the app with a per-launch workspace rule.
# The command is fixed so deck names and card data never reach the shell.
ANKI_COMMAND = 'if command -v anki >/dev/null 2>&1; then exec anki; else exec "$HOME/.local/bin/anki"; fi'
BACKGROUND_LAUNCH = 'hl.exec_cmd([[' + ANKI_COMMAND + ']], { workspace = "special:anki-review silent" })'


def launch_anki():
    runtime_dir = Path(os.environ["XDG_RUNTIME_DIR"])
    with (runtime_dir / "omarchy-anki-review.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ReviewError("launch_pending") from None

        try:
            return review("decks", [])
        except ConnectionRefusedError:
            pass

        if connection_error() == "addon_missing":
            raise ReviewError("addon_missing")

        local_anki = Path.home() / ".local/bin/anki"
        if not shutil.which("anki") and not os.access(local_anki, os.X_OK):
            raise ReviewError("anki_missing")

        try:
            result = subprocess.run(
                ["hyprctl", "-j", "clients"], capture_output=True, text=True,
                check=True, timeout=3,
            )
            clients = json.loads(result.stdout)
            if any(str(client.get(key, "")).lower() in {"anki", "net.ankiweb.anki"}
                   for client in clients for key in ("class", "initialClass")):
                raise ReviewError("anki_running")

            result = subprocess.run(
                ["hyprctl", "eval", BACKGROUND_LAUNCH], capture_output=True,
                text=True, check=True, timeout=3,
            )
            if result.stdout.strip() != "ok":
                raise ReviewError("launch_failed")
        except (OSError, subprocess.SubprocessError, ValueError):
            raise ReviewError("launch_failed") from None

        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            try:
                return review("decks", [])
            except ConnectionRefusedError:
                time.sleep(0.5)
        raise ReviewError("launch_timeout")


def connection_error():
    data_home = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share")
    addon_dir = data_home / "Anki2" / "addons21"
    if addon_dir.is_dir() and not (addon_dir / "2055492159").is_dir():
        return "addon_missing"
    return "connection"


def main():
    operation, *args = sys.argv[1:]
    try:
        result = review(operation, args)
    except ReviewError as error:
        result = {"error": str(error)}
    except (OSError, http.client.HTTPException):
        result = {"error": connection_error()}
    except (KeyError, TypeError, ValueError, IndexError):
        result = {"error": "response"}
    print(json.dumps(result))


if __name__ == "__main__":
    main()
