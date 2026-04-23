#!/usr/bin/env bash
#
# NAWEX Linux Baseline — cost_check.sh
#
# Surfaces host-level cost drift that compounds across a fleet:
#   - filesystems above a usage threshold
#   - individual log files over a size threshold
#   - stopped containers and dangling images taking disk
#
# Read-only. Exits 0 on clean, 1 on any breach. Intended for cron and the
# FinOps aggregator in finops-aiops/.

set -euo pipefail

DISK_PCT_LIMIT="${DISK_PCT_LIMIT:-85}"
LOG_MB_LIMIT="${LOG_MB_LIMIT:-500}"
STOPPED_CONTAINER_LIMIT="${STOPPED_CONTAINER_LIMIT:-10}"
exit_code=0

check_disk() {
    while read -r pct mount; do
        pct="${pct%\%}"
        [[ -z "${pct}" || "${pct}" == "-" ]] && continue
        if (( pct >= DISK_PCT_LIMIT )); then
            echo "DISK   ${mount} at ${pct}% (limit ${DISK_PCT_LIMIT}%)"
            exit_code=1
        fi
    done < <(df -hP --output=pcent,target 2>/dev/null | tail -n +2 | awk '{print $1, $2}')
}

check_logs() {
    local limit_bytes=$(( LOG_MB_LIMIT * 1024 * 1024 ))
    while read -r size path; do
        if (( size >= limit_bytes )); then
            echo "LOG    ${path} is $(( size / 1024 / 1024 ))MB (limit ${LOG_MB_LIMIT}MB)"
            exit_code=1
        fi
    done < <(find /var/log -type f -printf '%s %p\n' 2>/dev/null)
}

check_docker() {
    command -v docker >/dev/null 2>&1 || return 0
    local dangling stopped
    dangling="$(docker images --filter dangling=true --quiet 2>/dev/null | wc -l | tr -d ' ')"
    if (( dangling > 0 )); then
        echo "DOCKER ${dangling} dangling images (docker image prune -f)"
        exit_code=1
    fi
    stopped="$(docker ps -a --filter status=exited --quiet 2>/dev/null | wc -l | tr -d ' ')"
    if (( stopped > STOPPED_CONTAINER_LIMIT )); then
        echo "DOCKER ${stopped} stopped containers (docker container prune -f)"
        exit_code=1
    fi
}

main() {
    check_disk
    check_logs
    check_docker
    if (( exit_code == 0 )); then
        echo "cost_check: OK"
    fi
    exit "${exit_code}"
}

main "$@"
