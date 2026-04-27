"""NAWEX LLM gateway.

Provider-agnostic completion proxy with prompt caching and token-usage telemetry.
The mock provider is deterministic and dependency-free so the service is fully
exercisable in CI, local dev, and the kind harness without an external API key.
The Anthropic provider is loaded lazily, so the SDK is only required when
LLM_PROVIDER=anthropic.
"""

from __future__ import annotations

import hashlib
import logging
import os
import threading
import time
from collections import OrderedDict, defaultdict
from collections.abc import Callable
from typing import Any

from flask import Flask, jsonify, request

logging.basicConfig(
    level=os.environ.get("LOG_LEVEL", "INFO"),
    format='{"ts":"%(asctime)s","level":"%(levelname)s","logger":"%(name)s","msg":"%(message)s"}',
)
logger = logging.getLogger("nawex.llm")


class _LRUCache:
    def __init__(self, capacity: int) -> None:
        self._capacity = max(1, capacity)
        self._data: OrderedDict[str, dict[str, Any]] = OrderedDict()
        self._lock = threading.Lock()

    def get(self, key: str) -> dict[str, Any] | None:
        with self._lock:
            if key not in self._data:
                return None
            self._data.move_to_end(key)
            return self._data[key]

    def put(self, key: str, value: dict[str, Any]) -> None:
        with self._lock:
            if key in self._data:
                self._data.move_to_end(key)
            self._data[key] = value
            while len(self._data) > self._capacity:
                self._data.popitem(last=False)


def _mock_complete(prompt: str, model: str, max_tokens: int) -> dict[str, Any]:
    digest = hashlib.sha256(prompt.encode("utf-8")).hexdigest()[:16]
    completion = f"[mock:{model}] {prompt[:128]} #{digest}"
    completion = completion[: max(16, max_tokens * 4)]
    return {
        "completion": completion,
        "model": model,
        "prompt_tokens": max(1, len(prompt) // 4),
        "completion_tokens": max(1, len(completion) // 4),
    }


def _anthropic_complete(prompt: str, model: str, max_tokens: int, api_key: str) -> dict[str, Any]:
    import anthropic  # lazy import — only required when LLM_PROVIDER=anthropic

    client = anthropic.Anthropic(api_key=api_key)
    msg = client.messages.create(
        model=model,
        max_tokens=max_tokens,
        messages=[{"role": "user", "content": prompt}],
    )
    text = "".join(getattr(block, "text", "") for block in msg.content)
    usage = getattr(msg, "usage", None)
    return {
        "completion": text,
        "model": getattr(msg, "model", model),
        "prompt_tokens": getattr(usage, "input_tokens", 0) if usage else 0,
        "completion_tokens": getattr(usage, "output_tokens", 0) if usage else 0,
    }


def create_app(provider_override: Callable[[str, str, int], dict[str, Any]] | None = None) -> Flask:
    app = Flask(__name__)
    started_at = time.time()
    provider = os.getenv("LLM_PROVIDER", "mock").lower()
    default_model = os.getenv("LLM_MODEL", "claude-haiku-4-5-20251001")
    api_key = os.getenv("LLM_API_KEY", "")
    cache_capacity = int(os.getenv("LLM_CACHE_CAPACITY", "256"))
    cache = _LRUCache(cache_capacity)
    usage_lock = threading.Lock()
    usage: dict[str, int] = defaultdict(int)

    def _dispatch(prompt: str, model: str, max_tokens: int) -> dict[str, Any]:
        if provider_override is not None:
            return provider_override(prompt, model, max_tokens)
        if provider == "mock":
            return _mock_complete(prompt, model, max_tokens)
        if provider == "anthropic":
            if not api_key:
                raise RuntimeError("LLM_API_KEY is required for provider=anthropic")
            return _anthropic_complete(prompt, model, max_tokens, api_key)
        raise ValueError(f"unknown provider: {provider}")

    @app.get("/healthz")
    def healthz():
        return jsonify({"status": "ok", "service": "nawex-llm-gateway"})

    @app.get("/readyz")
    def readyz():
        ready = provider_override is not None or provider == "mock" or bool(api_key)
        return (
            jsonify({"status": "ready" if ready else "not-ready", "provider": provider}),
            200 if ready else 503,
        )

    @app.get("/api/v1/llm/info")
    def info():
        return jsonify(
            {
                "service": "nawex-llm-gateway",
                "provider": provider,
                "model": default_model,
                "uptime_seconds": int(time.time() - started_at),
                "cache_capacity": cache_capacity,
            }
        )

    @app.get("/api/v1/llm/usage")
    def usage_view():
        with usage_lock:
            return jsonify(
                {
                    "requests": usage.get("requests", 0),
                    "cache_hits": usage.get("cache_hits", 0),
                    "prompt_tokens": usage.get("prompt_tokens", 0),
                    "completion_tokens": usage.get("completion_tokens", 0),
                }
            )

    @app.post("/api/v1/llm/complete")
    def complete():
        body = request.get_json(silent=True) or {}
        prompt = body.get("prompt")
        if not isinstance(prompt, str) or not prompt:
            return jsonify({"error": "prompt is required"}), 400
        model = body.get("model") or default_model
        try:
            max_tokens = int(body.get("max_tokens", 256))
            temperature = float(body.get("temperature", 0.0))
        except (TypeError, ValueError):
            return jsonify({"error": "max_tokens and temperature must be numeric"}), 400

        cache_key = hashlib.sha256(
            f"{provider}|{model}|{temperature}|{prompt}".encode()
        ).hexdigest()
        cached = cache.get(cache_key)
        if cached is not None:
            with usage_lock:
                usage["requests"] += 1
                usage["cache_hits"] += 1
            return jsonify({**cached, "cached": True})

        try:
            result = _dispatch(prompt, model, max_tokens)
        except RuntimeError as exc:
            return jsonify({"error": str(exc)}), 503
        except Exception as exc:
            logger.exception("llm provider error")
            return jsonify({"error": "provider error", "detail": str(exc)}), 502

        payload = {
            "completion": result["completion"],
            "model": result["model"],
            "usage": {
                "prompt_tokens": result["prompt_tokens"],
                "completion_tokens": result["completion_tokens"],
            },
            "cached": False,
        }
        cache.put(cache_key, payload)
        with usage_lock:
            usage["requests"] += 1
            usage["prompt_tokens"] += result["prompt_tokens"]
            usage["completion_tokens"] += result["completion_tokens"]
        logger.info(
            "complete provider=%s model=%s prompt_tokens=%d completion_tokens=%d",
            provider,
            model,
            result["prompt_tokens"],
            result["completion_tokens"],
        )
        return jsonify(payload)

    return app


app = create_app()


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)  # noqa: S104
