from flask import Flask, jsonify, request
import os
import time

app = Flask(__name__)
STARTED_AT = time.time()


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
            "uptime_seconds": int(time.time() - STARTED_AT),
            "slo_target_availability": 99.9,
        }
    )


@app.post("/api/v1/mission")
def ingest_mission_data():
    payload = request.get_json(silent=True) or {}
    return (
        jsonify(
            {
                "accepted": True,
                "records_received": len(payload.get("records", [])),
                "tracking_id": payload.get("tracking_id", "demo-tracking-id"),
            }
        ),
        202,
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
