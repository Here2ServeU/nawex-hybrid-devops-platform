from __future__ import annotations

import pytest

from app import create_app


def _capturing_llm():
    captured: dict[str, str] = {}

    def caller(prompt: str) -> dict[str, object]:
        captured["prompt"] = prompt
        return {
            "completion": "synthesized answer",
            "model": "mock-model",
            "usage": {"prompt_tokens": 10, "completion_tokens": 5},
        }

    return caller, captured


@pytest.fixture()
def client_with_capture():
    caller, captured = _capturing_llm()
    app = create_app(llm_caller=caller)
    app.testing = True
    with app.test_client() as c:
        yield c, captured


def test_healthz(client_with_capture) -> None:
    client, _ = client_with_capture
    resp = client.get("/healthz")
    assert resp.status_code == 200
    assert resp.json["service"] == "nawex-rag"


def test_ingest_and_stats(client_with_capture) -> None:
    client, _ = client_with_capture
    resp = client.post(
        "/api/v1/rag/documents",
        json={
            "documents": [
                {
                    "id": "kube-1",
                    "text": "Kubernetes Pod Security Admission enforces restricted profiles.",
                },
                {
                    "id": "tf-1",
                    "text": "Terraform provisions infrastructure across AWS, Azure, and vSphere.",
                },
            ]
        },
    )
    assert resp.status_code == 202
    assert resp.json["ingested"] == 2
    stats = client.get("/api/v1/rag/stats").json
    assert stats["documents"] == 2


def test_ingest_skips_invalid_entries(client_with_capture) -> None:
    client, _ = client_with_capture
    resp = client.post(
        "/api/v1/rag/documents",
        json={
            "documents": [
                {"id": "ok", "text": "valid"},
                {"id": "", "text": "no id"},
                "not-a-dict",
            ],
        },
    )
    assert resp.status_code == 202
    assert resp.json["ingested"] == 1


def test_query_retrieves_relevant_doc_and_calls_llm(client_with_capture) -> None:
    client, captured = client_with_capture
    client.post(
        "/api/v1/rag/documents",
        json={
            "documents": [
                {
                    "id": "kube-1",
                    "text": "Kubernetes Pod Security Admission enforces restricted profiles.",
                },
                {
                    "id": "tf-1",
                    "text": "Terraform provisions infrastructure across AWS, Azure, and vSphere.",
                },
                {
                    "id": "argo-1",
                    "text": "Argo CD reconciles GitOps applications from a root app-of-apps.",
                },
            ]
        },
    )
    resp = client.post(
        "/api/v1/rag/query",
        json={"question": "How does Kubernetes enforce pod security?", "top_k": 2},
    )
    assert resp.status_code == 200
    body = resp.json
    assert body["answer"] == "synthesized answer"
    assert len(body["citations"]) == 2
    citation_ids = {c["id"] for c in body["citations"]}
    assert "kube-1" in citation_ids
    assert "Context:" in captured["prompt"]
    assert "[kube-1]" in captured["prompt"]


def test_query_rejects_missing_question(client_with_capture) -> None:
    client, _ = client_with_capture
    resp = client.post("/api/v1/rag/query", json={})
    assert resp.status_code == 400


def test_query_handles_llm_error() -> None:
    def broken(_prompt: str) -> dict[str, object]:
        raise RuntimeError("upstream is down")

    app = create_app(llm_caller=broken)
    app.testing = True
    with app.test_client() as client:
        client.post(
            "/api/v1/rag/documents",
            json={"documents": [{"id": "a", "text": "hello"}]},
        )
        resp = client.post("/api/v1/rag/query", json={"question": "hi"})
    assert resp.status_code == 502
    assert "error" in resp.json
