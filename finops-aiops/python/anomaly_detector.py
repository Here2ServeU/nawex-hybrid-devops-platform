import json


def main() -> None:
    report = {
        "service": "nawex-worker",
        "signal": "memory_usage",
        "anomaly_detected": True,
        "change_point": "post-deployment",
        "recommendation": "inspect recent release and compare worker heap profile",
    }
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
