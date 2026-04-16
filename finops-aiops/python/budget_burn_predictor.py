import json


def main() -> None:
    report = {
        "environment": "dev",
        "projected_monthly_spend_usd": 1840,
        "budget_usd": 1500,
        "drift_percent": 22.7,
        "recommendation": "scale down off-hours worker capacity and reduce idle node count",
    }
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
