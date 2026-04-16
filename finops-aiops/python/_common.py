"""Shared helpers for FinOps/AIOps analyzers.

These analyzers are intentionally deterministic stubs in this reference repo: they emit
a structured JSON report in the shape a real analyzer would. They share the same CLI
surface (`--output`, `--pretty`) so the CI workflow and Slack notifier can treat all
reports uniformly.
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
from pathlib import Path
from typing import Any

logger = logging.getLogger("nawex.finops")


def configure_logging() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format='{"ts":"%(asctime)s","level":"%(levelname)s","logger":"%(name)s","msg":"%(message)s"}',
    )


def build_arg_parser(description: str) -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=description)
    parser.add_argument(
        "--output",
        type=Path,
        default=None,
        help="Write the JSON report to this file in addition to stdout.",
    )
    parser.add_argument(
        "--pretty",
        action="store_true",
        help="Pretty-print JSON to stdout (default: compact).",
    )
    return parser


def emit(report: dict[str, Any], args: argparse.Namespace) -> None:
    text = json.dumps(report, indent=2 if args.pretty else None, sort_keys=True)
    sys.stdout.write(text + "\n")
    if args.output is not None:
        args.output.write_text(text + "\n", encoding="utf-8")
        logger.info("wrote report to %s", args.output)


def risk_from_burn_rate(burn_rate: float) -> str:
    if burn_rate >= 4.0:
        return "critical"
    if burn_rate >= 2.0:
        return "high"
    if burn_rate >= 1.0:
        return "medium"
    return "low"
