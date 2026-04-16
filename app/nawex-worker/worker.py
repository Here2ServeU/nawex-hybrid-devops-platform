import json
import os
import time


def main() -> None:
    service = os.getenv("NAWEX_SERVICE", "nawex-worker")
    interval = int(os.getenv("NAWEX_INTERVAL_SECONDS", "10"))
    while True:
        print(
            json.dumps(
                {
                    "service": service,
                    "status": "processing",
                    "queue": "mission-events",
                    "interval_seconds": interval,
                }
            ),
            flush=True,
        )
        time.sleep(interval)


if __name__ == "__main__":
    main()
