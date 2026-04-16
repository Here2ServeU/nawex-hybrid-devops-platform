"""Inventory source VMs and emit one WorkloadProfile stub per VM.

Two input modes:
  --vcenter <host>   Live mode. Requires VMWARE_USER / VMWARE_PASSWORD env vars and
                     the `pyvmomi` package. Reads all powered-on VMs matching --filter.
  --from-json <path> Offline mode. Reads a JSON array of VM descriptors (same shape as
                     what the live mode produces) and treats it as the inventory.

The tool picks a plausible runtime based on the VM's guest OS and any detected
well-known service names, then writes one YAML file per VM into --out. The YAMLs
are intended as starting points: humans must review and edit before containerization.
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import sys
from pathlib import Path
from typing import Any

logger = logging.getLogger("nawex.assess")

RUNTIME_HINTS = {
    # (substring of guest_os, substring of vm name) -> runtime
    ("ubuntu", "report"): "python3.12",
    ("ubuntu", "worker"): "node20",
    ("ubuntu", "api"): "python3.12",
    ("rhel", "java"): "java17",
    ("debian", ""): "generic-debian",
}


def guess_runtime(guest_os: str, vm_name: str) -> str:
    g = (guest_os or "").lower()
    n = (vm_name or "").lower()
    for (os_part, name_part), runtime in RUNTIME_HINTS.items():
        if os_part in g and (not name_part or name_part in n):
            return runtime
    return "generic-debian"


def profile_from_vm(vm: dict[str, Any]) -> dict[str, Any]:
    name = vm["name"].lower().replace("_", "-")
    return {
        "apiVersion": "nawex.io/v1",
        "kind": "WorkloadProfile",
        "metadata": {
            "name": name,
            "source": {
                "hypervisor": "vsphere",
                "vm": vm["name"],
                "datacenter": vm.get("datacenter", ""),
            },
        },
        "spec": {
            "runtime": guess_runtime(vm.get("guest_os", ""), vm["name"]),
            "entrypoint": ["# TODO: fill in the command that starts the service"],
            "expose": [{"port": 8080, "protocol": "TCP"}],
            "env": [],
            "resources": {
                # Rightsize to 50% of the VM allocation as a starting point; the
                # rightsizing engine will tighten this after observing real usage.
                "cpu_millicores": max(100, int((vm.get("cpu_count", 2) * 1000) * 0.5)),
                "memory_mib": max(128, int(vm.get("memory_mib", 2048) * 0.5)),
            },
            "dependencies": {},
            "health": {"liveness": "/healthz", "readiness": "/readyz"},
            "target": {"cluster": "aws-eks", "namespace": "nawex-migrated", "replicas": 2},
        },
    }


def read_offline(path: Path) -> list[dict[str, Any]]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, list):
        raise ValueError("--from-json must contain a JSON array of VM descriptors")
    return data


def read_vcenter(host: str, name_filter: str) -> list[dict[str, Any]]:
    try:
        from pyVim.connect import Disconnect, SmartConnect  # type: ignore[import-not-found]
        from pyVmomi import vim  # type: ignore[import-not-found]
    except ImportError as exc:
        raise SystemExit(
            "pyvmomi not installed. Run: pip install pyvmomi  (or use --from-json)"
        ) from exc

    user = os.environ.get("VMWARE_USER")
    password = os.environ.get("VMWARE_PASSWORD")
    if not user or not password:
        raise SystemExit("set VMWARE_USER and VMWARE_PASSWORD environment variables")

    si = SmartConnect(host=host, user=user, pwd=password, disableSslVerification=True)
    try:
        content = si.RetrieveContent()
        container = content.viewManager.CreateContainerView(
            content.rootFolder, [vim.VirtualMachine], True
        )
        out: list[dict[str, Any]] = []
        for vm in container.view:
            if name_filter and name_filter not in vm.name:
                continue
            if str(vm.runtime.powerState) != "poweredOn":
                continue
            out.append(
                {
                    "name": vm.name,
                    "guest_os": getattr(vm.guest, "guestFullName", "") or "",
                    "cpu_count": vm.config.hardware.numCPU,
                    "memory_mib": vm.config.hardware.memoryMB,
                    "ip": getattr(vm.guest, "ipAddress", "") or "",
                    "datacenter": "",
                }
            )
        container.Destroy()
        return out
    finally:
        Disconnect(si)


def dump_yaml(data: dict[str, Any]) -> str:
    """Tiny deterministic YAML dumper — keeps stdlib-only so no PyYAML dep."""
    lines: list[str] = []

    def dump(obj: Any, indent: int) -> None:
        pad = "  " * indent
        if isinstance(obj, dict):
            for k, v in obj.items():
                if isinstance(v, (dict, list)) and v:
                    lines.append(f"{pad}{k}:")
                    dump(v, indent + 1)
                elif isinstance(v, (dict, list)):
                    lines.append(f"{pad}{k}: " + ("{}" if isinstance(v, dict) else "[]"))
                else:
                    lines.append(f"{pad}{k}: {_scalar(v)}")
        elif isinstance(obj, list):
            for item in obj:
                if isinstance(item, (dict, list)):
                    lines.append(f"{pad}-")
                    dump(item, indent + 1)
                else:
                    lines.append(f"{pad}- {_scalar(item)}")

    dump(data, 0)
    return "\n".join(lines) + "\n"


def _scalar(v: Any) -> str:
    if v is None:
        return "null"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return str(v)
    s = str(v)
    needs_quotes = any(ch in s for ch in ":#{}[],&*!|>'\"%@`") or s in {
        "yes",
        "no",
        "true",
        "false",
        "null",
        "",
    }
    if needs_quotes:
        return '"' + s.replace('"', '\\"') + '"'
    return s


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    src = p.add_mutually_exclusive_group(required=True)
    src.add_argument("--vcenter", help="vCenter FQDN / IP")
    src.add_argument("--from-json", type=Path, help="Offline JSON inventory file")
    p.add_argument("--filter", default="nawex", help="Substring filter on VM name (default: nawex)")
    p.add_argument(
        "--out", type=Path, required=True, help="Directory to write WorkloadProfile YAMLs"
    )
    return p.parse_args()


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    args = parse_args()
    vms = (
        read_offline(args.from_json)
        if args.from_json is not None
        else read_vcenter(args.vcenter, args.filter)
    )
    args.out.mkdir(parents=True, exist_ok=True)
    for vm in vms:
        profile = profile_from_vm(vm)
        path = args.out / f"{profile['metadata']['name']}.yaml"
        path.write_text(dump_yaml(profile), encoding="utf-8")
        logger.info("wrote %s", path)
    logger.info("%d WorkloadProfile(s) written to %s", len(vms), args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
