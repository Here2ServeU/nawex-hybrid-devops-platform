"""Recommend CPU/memory request reductions based on observed utilization."""

from __future__ import annotations

from _common import build_arg_parser, configure_logging, emit


def analyze() -> dict[str, object]:
    cpu_req = 500
    cpu_obs = 180
    mem_req = 256
    mem_obs = 140
    cpu_headroom = round((1 - cpu_obs / cpu_req) * 100, 1)
    mem_headroom = round((1 - mem_obs / mem_req) * 100, 1)
    return {
        "analyzer": "rightsizing_engine",
        "workload": "nawex-api",
        "namespace": "nawex-platform",
        "cpu_request_millicores": cpu_req,
        "observed_cpu_millicores": cpu_obs,
        "cpu_headroom_percent": cpu_headroom,
        "memory_request_mib": mem_req,
        "observed_memory_mib": mem_obs,
        "memory_headroom_percent": mem_headroom,
        "severity": "info",
        "action": "reduce_requests",
        "recommendation": "reduce requests by 30-40 percent after validating p95 latency",
        "runbook": "cost-optimization.md",
    }


def main() -> int:
    configure_logging()
    args = build_arg_parser(__doc__ or "").parse_args()
    emit(analyze(), args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
