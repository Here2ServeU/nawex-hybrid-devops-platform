import json


def main() -> None:
    report = {
        "service": "nawex-mission-data-api",
        "availability_slo": 99.9,
        "error_budget_remaining_percent": 61.4,
        "current_burn_rate": 1.8,
        "risk": "medium",
        "message": "Current burn rate suggests SLO breach within 18 hours if sustained.",
    }
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
