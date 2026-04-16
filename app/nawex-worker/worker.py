"""NAWEX worker: emits structured heartbeat logs on a fixed interval."""

from __future__ import annotations

import json
import logging
import os
import signal
import sys
import time
from types import FrameType

logger = logging.getLogger("nawex.worker")

_shutdown = False


def _handle_signal(signum: int, _frame: FrameType | None) -> None:
    global _shutdown
    logger.info("received signal %s, shutting down", signum)
    _shutdown = True


def main() -> int:
    logging.basicConfig(level=os.environ.get("LOG_LEVEL", "INFO"), format="%(message)s")
    signal.signal(signal.SIGTERM, _handle_signal)
    signal.signal(signal.SIGINT, _handle_signal)

    service = os.getenv("NAWEX_SERVICE", "nawex-worker")
    interval = int(os.getenv("NAWEX_INTERVAL_SECONDS", "10"))

    while not _shutdown:
        sys.stdout.write(
            json.dumps(
                {
                    "service": service,
                    "status": "processing",
                    "queue": "mission-events",
                    "interval_seconds": interval,
                }
            )
            + "\n"
        )
        sys.stdout.flush()
        # Sleep in small chunks so signals land promptly.
        for _ in range(interval):
            if _shutdown:
                break
            time.sleep(1)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
