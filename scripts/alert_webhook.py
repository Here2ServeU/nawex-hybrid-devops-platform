"""Minimal AlertManager webhook receiver.

AlertManager can be configured to POST firing/resolved alerts to an HTTP endpoint.
This tiny server persists each alert to `.incidents/<fingerprint>.json` so engineers
can triage with `scripts/incident_respond.sh`.

Run:
    python scripts/alert_webhook.py --host 0.0.0.0 --port 9099

Then add a receiver to alertmanager.yml:
    - name: nawex-webhook
      webhook_configs:
        - url: http://<host>:9099/alerts
          send_resolved: true
"""

from __future__ import annotations

import argparse
import json
import logging
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

logger = logging.getLogger("nawex.webhook")

INCIDENT_DIR = Path(os.environ.get("NAWEX_INCIDENT_DIR", ".incidents"))


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args: object) -> None:  # silence default stderr logging
        logger.info(fmt, *args)

    def do_POST(self) -> None:  # stdlib fixes the method name
        if self.path != "/alerts":
            self._respond(404, {"error": "not found"})
            return
        length = int(self.headers.get("Content-Length", "0") or "0")
        body = self.rfile.read(length) if length else b"{}"
        try:
            payload = json.loads(body)
        except json.JSONDecodeError as exc:
            self._respond(400, {"error": f"invalid json: {exc}"})
            return
        INCIDENT_DIR.mkdir(parents=True, exist_ok=True)
        written = 0
        for alert in payload.get("alerts", []):
            fingerprint = alert.get("fingerprint")
            if not fingerprint:
                continue
            target = INCIDENT_DIR / f"{fingerprint}.json"
            target.write_text(json.dumps(alert, indent=2, sort_keys=True), encoding="utf-8")
            written += 1
            logger.info("stored incident %s -> %s", fingerprint, target)
        self._respond(200, {"stored": written})

    def _respond(self, status: int, body: dict[str, object]) -> None:
        data = json.dumps(body).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=9099)
    args = parser.parse_args()
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    logger.info("listening on http://%s:%d/alerts", args.host, args.port)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        logger.info("shutting down")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
