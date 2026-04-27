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
    assert resp.json == {"status": "ok", "service": "nawex-llm-gateway"}


def test_readyz_mock_provider_is_ready(client) -> None:
    resp = client.get("/readyz")
    assert resp.status_code == 200
    assert resp.json["status"] == "ready"


def test_complete_returns_completion_and_usage(client) -> None:
    resp = client.post("/api/v1/llm/complete", json={"prompt": "hello world"})
    assert resp.status_code == 200
    body = resp.json
    assert "completion" in body
    assert body["cached"] is False
    assert body["usage"]["prompt_tokens"] >= 1
    assert body["usage"]["completion_tokens"] >= 1


def test_complete_caches_identical_prompts(client) -> None:
    first = client.post("/api/v1/llm/complete", json={"prompt": "cache-me"})
    second = client.post("/api/v1/llm/complete", json={"prompt": "cache-me"})
    assert first.status_code == 200 and second.status_code == 200
    assert first.json["completion"] == second.json["completion"]
    assert second.json["cached"] is True


def test_complete_rejects_missing_prompt(client) -> None:
    resp = client.post("/api/v1/llm/complete", json={})
    assert resp.status_code == 400
    assert "error" in resp.json


def test_usage_endpoint_tracks_requests(client) -> None:
    client.post("/api/v1/llm/complete", json={"prompt": "usage-track-1"})
    client.post("/api/v1/llm/complete", json={"prompt": "usage-track-2"})
    resp = client.get("/api/v1/llm/usage")
    assert resp.status_code == 200
    assert resp.json["requests"] >= 2
    assert resp.json["completion_tokens"] >= 1


def test_provider_override_is_used_when_supplied() -> None:
    captured = {}

    def fake_provider(prompt: str, model: str, max_tokens: int):
        captured["prompt"] = prompt
        return {
            "completion": "FAKE",
            "model": model,
            "prompt_tokens": 7,
            "completion_tokens": 11,
        }

    app = create_app(provider_override=fake_provider)
    app.testing = True
    with app.test_client() as c:
        resp = c.post("/api/v1/llm/complete", json={"prompt": "ping"})
    assert resp.status_code == 200
    assert resp.json["completion"] == "FAKE"
    assert resp.json["usage"] == {"prompt_tokens": 7, "completion_tokens": 11}
    assert captured["prompt"] == "ping"
