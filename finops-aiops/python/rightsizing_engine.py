import json


def main() -> None:
    report = {
        "workload": "nawex-api",
        "namespace": "nawex-platform",
        "cpu_request_millicores": 500,
        "observed_cpu_millicores": 180,
        "memory_request_mib": 256,
        "observed_memory_mib": 140,
        "recommendation": "reduce requests by 30-40 percent after validating p95 latency",
    }
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
