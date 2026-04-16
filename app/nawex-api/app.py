"""NAWEX mission data API.

Small Flask app that exposes liveness, readiness, and a mission ingest endpoint.
"""

from __future__ import annotations

import logging
import os
import time

from flask import Flask, jsonify, request

logging.basicConfig(
    level=os.environ.get("LOG_LEVEL", "INFO"),
    format='{"ts":"%(asctime)s","level":"%(levelname)s","logger":"%(name)s","msg":"%(message)s"}',
)
logger = logging.getLogger("nawex.api")


def create_app() -> Flask:
    app = Flask(__name__)
    started_at = time.time()

    @app.get("/healthz")
    def healthz():
        return jsonify({"status": "ok", "service": "nawex-api"})

    @app.get("/readyz")
    def readyz():
        return jsonify({"status": "ready", "service": "nawex-api"})

    @app.get("/api/v1/mission")
    def mission_status():
        return jsonify(
            {
                "service": "nawex-mission-data-api",
                "environment": os.getenv("NAWEX_ENV", "dev"),
                "uptime_seconds": int(time.time() - started_at),
                "slo_target_availability": 99.9,
            }
        )

    @app.post("/api/v1/mission")
    def ingest_mission_data():
        payload = request.get_json(silent=True) or {}
        records = payload.get("records", [])
        tracking_id = payload.get("tracking_id", "demo-tracking-id")
        logger.info("accepted %d records tracking_id=%s", len(records), tracking_id)
        return (
            jsonify(
                {
                    "accepted": True,
                    "records_received": len(records),
                    "tracking_id": tracking_id,
                }
            ),
            202,
        )

    return app


app = create_app()


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)  # noqa: S104
