"""Post FinOps/AIOps analyzer reports to Slack as a single consolidated message."""

from __future__ import annotations

import argparse
import json
import logging
import os
import sys
from pathlib import Path
from typing import Any

import requests

logger = logging.getLogger("nawex.notify")

SEVERITY_EMOJI = {
    "critical": ":rotating_light:",
    "warning": ":warning:",
    "info": ":information_source:",
}


def build_blocks(reports: list[dict[str, Any]], runbook_base: str) -> list[dict[str, Any]]:
    blocks: list[dict[str, Any]] = [
        {
            "type": "header",
            "text": {"type": "plain_text", "text": "NAWEX weekly FinOps/AIOps report"},
        }
    ]
    for report in reports:
        severity = str(report.get("severity", "info")).lower()
        emoji = SEVERITY_EMOJI.get(severity, ":information_source:")
        analyzer = report.get("analyzer", "unknown")
        recommendation = report.get("recommendation") or report.get(
            "message", "(no recommendation)"
        )
        action = report.get("action", "(none)")
        runbook = report.get("runbook")
        runbook_link = f"<{runbook_base}/{runbook}|{runbook}>" if runbook else "(no runbook)"
        blocks.append(
            {
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": (
                        f"{emoji} *{analyzer}* ({severity})\n"
                        f"{recommendation}\n"
                        f"*Action:* `{action}`  *Runbook:* {runbook_link}"
                    ),
                },
            }
        )
    blocks.append({"type": "divider"})
    blocks.append(
        {
            "type": "context",
            "elements": [
                {
                    "type": "mrkdwn",
                    "text": (
                        "Triage with `./scripts/incident_respond.sh list`"
                        " — approve or deny per finding."
                    ),
                }
            ],
        }
    )
    return blocks


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--webhook", required=True, help="Slack incoming webhook URL.")
    parser.add_argument(
        "--report",
        type=Path,
        action="append",
        required=True,
        help="Path to a JSON report file. Repeat for multiple reports.",
    )
    parser.add_argument(
        "--runbook-base",
        default=os.environ.get(
            "RUNBOOK_BASE_URL",
            "https://github.com/Here2ServeU/nawex-hybrid-devops-platform/blob/main/runbooks",
        ),
    )
    parser.add_argument(
        "--min-severity",
        choices=["info", "warning", "critical"],
        default="info",
        help="Only include reports at or above this severity.",
    )
    return parser.parse_args()


def severity_rank(sev: str) -> int:
    return {"info": 0, "warning": 1, "critical": 2}.get(sev.lower(), 0)


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    args = parse_args()
    min_rank = severity_rank(args.min_severity)
    reports: list[dict[str, Any]] = []
    for path in args.report:
        if not path.exists():
            logger.warning("report missing: %s", path)
            continue
        data = json.loads(path.read_text(encoding="utf-8"))
        if severity_rank(str(data.get("severity", "info"))) < min_rank:
            continue
        reports.append(data)
    if not reports:
        logger.info("no reports at or above %s, skipping Slack post", args.min_severity)
        return 0
    payload = {"blocks": build_blocks(reports, args.runbook_base.rstrip("/"))}
    resp = requests.post(args.webhook, json=payload, timeout=10)
    if resp.status_code >= 300:
        logger.error("Slack post failed: %s %s", resp.status_code, resp.text)
        return 1
    logger.info("posted %d report(s) to Slack", len(reports))
    return 0


if __name__ == "__main__":
    sys.exit(main())
