from __future__ import annotations

import pytest

from app import create_app


@pytest.fixture()
def client():
    app = create_app()
    app.testing = True
    with app.test_client() as c:
        yield c


def test_healthz(client) -> None:
    resp = client.get("/healthz")
    assert resp.status_code == 200
    assert resp.json == {"status": "ok", "service": "nawex-api"}


def test_readyz(client) -> None:
    resp = client.get("/readyz")
    assert resp.status_code == 200
    assert resp.json["status"] == "ready"


def test_mission_status_contains_slo(client) -> None:
    resp = client.get("/api/v1/mission")
    assert resp.status_code == 200
    assert resp.json["slo_target_availability"] == 99.9


def test_mission_ingest_counts_records(client) -> None:
    resp = client.post("/api/v1/mission", json={"records": [1, 2, 3], "tracking_id": "abc"})
    assert resp.status_code == 202
    assert resp.json == {"accepted": True, "records_received": 3, "tracking_id": "abc"}


def test_mission_ingest_handles_empty_body(client) -> None:
    resp = client.post("/api/v1/mission")
    assert resp.status_code == 202
    assert resp.json["records_received"] == 0
