"""NAWEX RAG service.

A retrieval-augmented generation pipeline that ingests documents into an
in-memory store, retrieves the top-k relevant passages for a query, and asks
the LLM gateway to ground a response with explicit citations.

The embedding implementation is a deterministic, signed hash-based bag-of-words
projection — pure-Python, no external model required — so the pipeline runs
in CI and the kind harness without GPU nodes or an embeddings API. Swap the
`_embed` function (or inject a different `Store`) to plug in a real embedding
model and a real vector database.
"""

from __future__ import annotations

import hashlib
import json as _json
import logging
import math
import os
import re
import threading
import time
import urllib.error
import urllib.request
from collections.abc import Callable
from typing import Any

from flask import Flask, jsonify, request

logging.basicConfig(
    level=os.environ.get("LOG_LEVEL", "INFO"),
    format='{"ts":"%(asctime)s","level":"%(levelname)s","logger":"%(name)s","msg":"%(message)s"}',
)
logger = logging.getLogger("nawex.rag")

EMBED_DIM = int(os.getenv("RAG_EMBED_DIM", "256"))
TOP_K_DEFAULT = int(os.getenv("RAG_TOP_K", "3"))
LLM_GATEWAY_URL = os.getenv(
    "LLM_GATEWAY_URL",
    "http://nawex-llm-gateway.nawex-platform.svc.cluster.local/api/v1/llm/complete",
)
LLM_TIMEOUT = float(os.getenv("LLM_TIMEOUT_SECONDS", "10"))

_TOKEN_RE = re.compile(r"[a-z0-9]+")


def _tokenize(text: str) -> list[str]:
    return _TOKEN_RE.findall(text.lower())


def _embed(text: str, dim: int = EMBED_DIM) -> list[float]:
    vec = [0.0] * dim
    for tok in _tokenize(text):
        h = int(hashlib.md5(tok.encode("utf-8")).hexdigest(), 16)  # noqa: S324 - non-cryptographic projection
        idx = h % dim
        sign = 1.0 if (h >> 8) & 1 else -1.0
        vec[idx] += sign
    norm = math.sqrt(sum(v * v for v in vec)) or 1.0
    return [v / norm for v in vec]


def _cosine(a: list[float], b: list[float]) -> float:
    return sum(x * y for x, y in zip(a, b, strict=True))


class Store:
    def __init__(self) -> None:
        self._docs: dict[str, dict[str, Any]] = {}
        self._lock = threading.Lock()

    def upsert(self, doc_id: str, text: str, metadata: dict[str, Any] | None) -> None:
        embedding = _embed(text)
        with self._lock:
            self._docs[doc_id] = {
                "id": doc_id,
                "text": text,
                "metadata": metadata or {},
                "embedding": embedding,
            }

    def search(self, query: str, top_k: int) -> list[dict[str, Any]]:
        q = _embed(query)
        with self._lock:
            scored = [(doc, _cosine(q, doc["embedding"])) for doc in self._docs.values()]
        scored.sort(key=lambda pair: pair[1], reverse=True)
        return [
            {"id": d["id"], "text": d["text"], "metadata": d["metadata"], "score": float(s)}
            for d, s in scored[: max(1, top_k)]
        ]

    def stats(self) -> dict[str, int]:
        with self._lock:
            return {"documents": len(self._docs)}


def _build_prompt(question: str, contexts: list[dict[str, Any]]) -> str:
    rendered = "\n\n".join(f"[{c['id']}] {c['text']}" for c in contexts) or "(no context retrieved)"
    return (
        "You are a retrieval-augmented assistant. Answer the question using only the context "
        "below. Cite sources by their bracketed id (for example [doc-7]). If the context is "
        "insufficient, say so explicitly.\n\n"
        f"Context:\n{rendered}\n\nQuestion: {question}\nAnswer:"
    )


def _default_llm_caller(prompt: str) -> dict[str, Any]:
    body = _json.dumps({"prompt": prompt}).encode("utf-8")
    req = urllib.request.Request(  # noqa: S310 - URL is admin-controlled via LLM_GATEWAY_URL
        LLM_GATEWAY_URL,
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=LLM_TIMEOUT) as resp:  # noqa: S310
        return _json.loads(resp.read().decode("utf-8"))


def create_app(
    llm_caller: Callable[[str], dict[str, Any]] | None = None,
    store: Store | None = None,
) -> Flask:
    app = Flask(__name__)
    started_at = time.time()
    _store = store or Store()
    _llm = llm_caller or _default_llm_caller

    @app.get("/healthz")
    def healthz():
        return jsonify({"status": "ok", "service": "nawex-rag"})

    @app.get("/readyz")
    def readyz():
        return jsonify({"status": "ready", "service": "nawex-rag"})

    @app.get("/api/v1/rag/stats")
    def stats():
        return jsonify({**_store.stats(), "uptime_seconds": int(time.time() - started_at)})

    @app.post("/api/v1/rag/documents")
    def ingest():
        body = request.get_json(silent=True) or {}
        docs = body.get("documents")
        if not isinstance(docs, list):
            return jsonify({"error": "documents must be a list"}), 400
        ingested = 0
        for entry in docs:
            if not isinstance(entry, dict):
                continue
            doc_id = str(entry.get("id") or "").strip()
            text = entry.get("text")
            if not doc_id or not isinstance(text, str) or not text:
                continue
            metadata = entry.get("metadata") if isinstance(entry.get("metadata"), dict) else None
            _store.upsert(doc_id, text, metadata)
            ingested += 1
        logger.info("ingested %d documents", ingested)
        return jsonify({"ingested": ingested, **_store.stats()}), 202

    @app.post("/api/v1/rag/query")
    def query():
        body = request.get_json(silent=True) or {}
        question = body.get("question")
        if not isinstance(question, str) or not question:
            return jsonify({"error": "question is required"}), 400
        try:
            top_k = int(body.get("top_k", TOP_K_DEFAULT))
        except (TypeError, ValueError):
            return jsonify({"error": "top_k must be an integer"}), 400

        contexts = _store.search(question, top_k)
        prompt = _build_prompt(question, contexts)
        try:
            llm = _llm(prompt)
        except (urllib.error.URLError, TimeoutError) as exc:
            logger.exception("llm gateway unreachable")
            return jsonify({"error": "llm gateway unreachable", "detail": str(exc)}), 502
        except Exception as exc:
            logger.exception("llm gateway error")
            return jsonify({"error": "llm gateway error", "detail": str(exc)}), 502

        citations = [{"id": c["id"], "score": c["score"]} for c in contexts]
        return jsonify(
            {
                "question": question,
                "answer": llm.get("completion"),
                "citations": citations,
                "model": llm.get("model"),
                "usage": llm.get("usage"),
            }
        )

    return app


app = create_app()


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)  # noqa: S104
