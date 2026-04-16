"""Detect post-deployment memory anomalies on the worker fleet.

Stub analyzer: emits a deterministic finding structured as a real analyzer's output.
"""

from __future__ import annotations

from _common import build_arg_parser, configure_logging, emit


def analyze() -> dict[str, object]:
    return {
        "analyzer": "anomaly_detector",
        "service": "nawex-worker",
        "signal": "memory_usage",
        "anomaly_detected": True,
        "change_point": "post-deployment",
        "severity": "warning",
        "action": "worker_heap_profile",
        "recommendation": "inspect recent release and compare worker heap profile",
        "runbook": "k8s-troubleshooting.md",
    }


def main() -> int:
    configure_logging()
    args = build_arg_parser(__doc__ or "").parse_args()
    emit(analyze(), args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
