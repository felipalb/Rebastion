#!/usr/bin/env python3
"""Dependency-free MVP backend for Rebastion."""

from __future__ import annotations

import json
import threading
from datetime import datetime, timezone
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import urlparse


HOST = "127.0.0.1"
PORT = 8000
DATA_FILE = Path(__file__).with_name("scores.json")
LOCK = threading.Lock()


def load_scores() -> list[dict[str, Any]]:
    if not DATA_FILE.exists():
        return []
    try:
        return json.loads(DATA_FILE.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return []


def save_scores(scores: list[dict[str, Any]]) -> None:
    DATA_FILE.write_text(json.dumps(scores, ensure_ascii=False, indent=2), encoding="utf-8")


class GameAPI(BaseHTTPRequestHandler):
    server_version = "Rebastion/0.1"

    def do_GET(self) -> None:  # noqa: N802
        path = urlparse(self.path).path
        if path == "/health":
            self.respond({"status": "ok"})
            return
        if path == "/daily":
            seed = int(datetime.now(timezone.utc).strftime("%Y%m%d"))
            self.respond({"seed": seed, "modifier": "fast_enemies", "bonus": 1.25})
            return
        if path == "/leaderboard":
            with LOCK:
                scores = sorted(load_scores(), key=lambda item: item["score"], reverse=True)[:20]
            self.respond({"scores": scores})
            return
        self.respond({"error": "not_found"}, HTTPStatus.NOT_FOUND)

    def do_POST(self) -> None:  # noqa: N802
        if urlparse(self.path).path != "/scores":
            self.respond({"error": "not_found"}, HTTPStatus.NOT_FOUND)
            return

        try:
            length = int(self.headers.get("Content-Length", "0"))
            payload = json.loads(self.rfile.read(length))
            player = str(payload["player"]).strip()[:24]
            score = int(payload["score"])
            wave = int(payload["wave"])
            if not player or score < 0 or wave < 1:
                raise ValueError
        except (KeyError, TypeError, ValueError, json.JSONDecodeError):
            self.respond({"error": "invalid_score"}, HTTPStatus.BAD_REQUEST)
            return

        entry = {
            "player": player,
            "score": score,
            "wave": wave,
            "created_at": datetime.now(timezone.utc).isoformat(),
        }
        with LOCK:
            scores = load_scores()
            scores.append(entry)
            save_scores(scores[-1000:])
        self.respond(entry, HTTPStatus.CREATED)

    def respond(self, payload: dict[str, Any], status: HTTPStatus = HTTPStatus.OK) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format: str, *args: Any) -> None:
        print(f"[{self.log_date_time_string()}] {format % args}")


if __name__ == "__main__":
    print(f"Rebastion API running at http://{HOST}:{PORT}")
    ThreadingHTTPServer((HOST, PORT), GameAPI).serve_forever()
