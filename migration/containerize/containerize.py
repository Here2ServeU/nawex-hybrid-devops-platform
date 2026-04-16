"""Containerize a WorkloadProfile: emit a Dockerfile + K8s Deployment/Service/Kustomization.

Run:
    python migration/containerize/containerize.py \
        --profile migration/samples/legacy-reporting-api.yaml \
        --out migration/containerize/out/

Output layout (per profile):
    out/<name>/Dockerfile
    out/<name>/deployment.yaml   # Deployment + Service
    out/<name>/kustomization.yaml

The generated manifests target the namespace specified by spec.target.namespace
(default: nawex-migrated) and are picked up by the EKS or AKS overlay via its
`resources:` list.
"""

from __future__ import annotations

import argparse
import json
import logging
import re
import sys
from pathlib import Path
from typing import Any

logger = logging.getLogger("nawex.containerize")

# Minimal YAML reader — no pyyaml dependency. Handles the subset our schema uses.
# If richer YAML is needed (anchors, complex types), install pyyaml and swap in safe_load.


def parse_yaml(text: str) -> Any:  # pragma: no cover — tested via integration
    try:
        import yaml  # type: ignore[import-untyped]

        return yaml.safe_load(text)
    except ImportError:
        return _parse_yaml_tiny(text)


def _parse_yaml_tiny(text: str) -> Any:
    """Very small YAML subset parser sufficient for WorkloadProfile files."""
    lines = [
        ln.rstrip() for ln in text.splitlines() if ln.strip() and not ln.lstrip().startswith("#")
    ]
    return _parse_block(lines, 0, 0)[0]


def _parse_block(lines: list[str], idx: int, indent: int) -> tuple[Any, int]:
    if idx >= len(lines):
        return None, idx
    first = lines[idx]
    first_indent = len(first) - len(first.lstrip())
    if first_indent < indent:
        return None, idx
    if first.lstrip().startswith("- "):
        return _parse_list(lines, idx, first_indent)
    return _parse_map(lines, idx, first_indent)


def _parse_map(lines: list[str], idx: int, indent: int) -> tuple[dict[str, Any], int]:
    out: dict[str, Any] = {}
    while idx < len(lines):
        ln = lines[idx]
        ind = len(ln) - len(ln.lstrip())
        if ind < indent:
            break
        if ind > indent:
            raise ValueError(f"unexpected indent at line: {ln!r}")
        if ln.lstrip().startswith("- "):
            break
        key, _, rest = ln.lstrip().partition(":")
        rest = rest.strip()
        idx += 1
        if rest:
            out[key] = _scalar(rest)
        else:
            value, idx = _parse_block(lines, idx, indent + 2)
            out[key] = value if value is not None else {}
    return out, idx


def _parse_list(lines: list[str], idx: int, indent: int) -> tuple[list[Any], int]:
    out: list[Any] = []
    while idx < len(lines):
        ln = lines[idx]
        ind = len(ln) - len(ln.lstrip())
        if ind < indent:
            break
        stripped = ln.lstrip()
        if not stripped.startswith("- "):
            break
        rest = stripped[2:].strip()
        idx += 1
        if not rest:
            value, idx = _parse_block(lines, idx, indent + 2)
            out.append(value if value is not None else {})
        elif ":" in rest and not rest.startswith('"'):
            # Inline map entry under a list.
            key, _, val = rest.partition(":")
            entry: dict[str, Any] = (
                {key.strip(): _scalar(val.strip())} if val.strip() else {key.strip(): None}
            )
            while idx < len(lines):
                ln2 = lines[idx]
                ind2 = len(ln2) - len(ln2.lstrip())
                if ind2 <= indent or ln2.lstrip().startswith("- "):
                    break
                k2, _, v2 = ln2.lstrip().partition(":")
                v2 = v2.strip()
                idx += 1
                if v2:
                    entry[k2.strip()] = _scalar(v2)
                else:
                    value, idx = _parse_block(lines, idx, indent + 4)
                    entry[k2.strip()] = value if value is not None else {}
            if entry and len(entry) == 1 and next(iter(entry.values())) is None:
                # Key with no value and no children — treat as empty map entry.
                pass
            out.append(entry)
        else:
            out.append(_scalar(rest))
    return out, idx


def _scalar(s: str) -> Any:
    if s.startswith('"') and s.endswith('"'):
        return s[1:-1]
    if s.startswith("'") and s.endswith("'"):
        return s[1:-1]
    if s in {"true", "false"}:
        return s == "true"
    if s == "null":
        return None
    if re.fullmatch(r"-?\d+", s):
        return int(s)
    if re.fullmatch(r"-?\d+\.\d+", s):
        return float(s)
    return s


RUNTIME_BASE = {
    "python3.11": "python:3.11-slim",
    "python3.12": "python:3.12-slim",
    "node18": "node:18-slim",
    "node20": "node:20-slim",
    "java17": "eclipse-temurin:17-jre-jammy",
    "java21": "eclipse-temurin:21-jre-jammy",
    "go1.22": "golang:1.22-alpine",
    "dotnet8": "mcr.microsoft.com/dotnet/aspnet:8.0",
    "generic-debian": "debian:12-slim",
}


def render_dockerfile(profile: dict[str, Any]) -> str:
    spec = profile["spec"]
    runtime = spec["runtime"]
    base = RUNTIME_BASE.get(runtime, "debian:12-slim")
    deps = spec.get("dependencies") or {}
    deb = deps.get("packages_deb") or []
    py = deps.get("python_requirements") or []
    npm = deps.get("npm_packages") or []
    expose = spec.get("expose") or []
    entrypoint = spec.get("entrypoint") or [
        "/bin/sh",
        "-c",
        "echo missing entrypoint; sleep 1; exit 1",
    ]

    lines = [
        "# syntax=docker/dockerfile:1.7",
        f"# Auto-generated from migration/samples/{profile['metadata']['name']}.yaml",
        f"FROM {base}",
        "ENV DEBIAN_FRONTEND=noninteractive \\",
        "    PYTHONDONTWRITEBYTECODE=1 \\",
        "    PYTHONUNBUFFERED=1",
        "WORKDIR /app",
    ]
    if deb:
        lines += [
            "RUN apt-get update \\",
            " && apt-get install -y --no-install-recommends " + " ".join(deb) + " \\",
            " && rm -rf /var/lib/apt/lists/*",
        ]
    if py:
        lines += [
            "RUN pip install --no-cache-dir " + " ".join(shell_quote(p) for p in py),
        ]
    if npm:
        lines += [
            "RUN npm install --omit=dev --global " + " ".join(shell_quote(p) for p in npm),
        ]
    lines += [
        "COPY . /app/",
        "RUN useradd --no-create-home --uid 10001 --shell /usr/sbin/nologin nawex",
        "USER 10001:10001",
    ]
    for exp in expose:
        lines.append(f"EXPOSE {exp['port']}")
    lines.append("ENTRYPOINT [" + ", ".join(json.dumps(x) for x in entrypoint) + "]")
    return "\n".join(lines) + "\n"


def shell_quote(s: str) -> str:
    if re.fullmatch(r"[A-Za-z0-9_.=@/:+-]+", s):
        return s
    return "'" + s.replace("'", "'\\''") + "'"


def render_k8s(profile: dict[str, Any]) -> str:
    meta = profile["metadata"]
    spec = profile["spec"]
    target = spec["target"]
    name = meta["name"]
    namespace = target.get("namespace", "nawex-migrated")
    replicas = target.get("replicas", 2)
    expose = spec.get("expose") or [{"port": 8080, "protocol": "TCP"}]
    primary_port = expose[0]["port"]
    resources = spec.get("resources") or {}
    cpu_m = resources.get("cpu_millicores", 250)
    mem_mib = resources.get("memory_mib", 256)
    env = spec.get("env") or []
    health = spec.get("health") or {}

    env_yaml: list[str] = []
    for e in env:
        env_yaml.append(f"            - name: {e['name']}")
        if "value" in e:
            env_yaml.append(f"              value: {json.dumps(str(e['value']))}")
        elif "valueFrom" in e:
            kind, _, ref = e["valueFrom"].partition(":")
            if kind == "secret":
                sec_name, _, sec_key = ref.partition("/")
                env_yaml += [
                    "              valueFrom:",
                    "                secretKeyRef:",
                    f"                  name: {sec_name}",
                    f"                  key: {sec_key or e['name']}",
                ]
            elif kind == "configmap":
                cm_name, _, cm_key = ref.partition("/")
                env_yaml += [
                    "              valueFrom:",
                    "                configMapKeyRef:",
                    f"                  name: {cm_name}",
                    f"                  key: {cm_key or e['name']}",
                ]

    probes: list[str] = []
    if health.get("liveness"):
        probes += [
            "          livenessProbe:",
            "            httpGet:",
            f"              path: {health['liveness']}",
            f"              port: {primary_port}",
            "            initialDelaySeconds: 10",
            "            periodSeconds: 10",
        ]
    if health.get("readiness"):
        probes += [
            "          readinessProbe:",
            "            httpGet:",
            f"              path: {health['readiness']}",
            f"              port: {primary_port}",
            "            initialDelaySeconds: 5",
            "            periodSeconds: 5",
        ]

    labels = (
        f"    app.kubernetes.io/name: {name}\n"
        f"    app.kubernetes.io/part-of: nawex-migrated\n"
        f"    nawex.io/source-hypervisor: {meta.get('source', {}).get('hypervisor', 'unknown')}\n"
        f"    nawex.io/target-cluster: {target['cluster']}"
    )

    ports_yaml = "\n".join(
        f"            - name: http-{p['port']}\n              containerPort: {p['port']}"
        for p in expose
    )
    svc_ports_yaml = "\n".join(
        (
            f"    - name: http-{p['port']}\n"
            f"      port: {p['port']}\n"
            f"      targetPort: {p['port']}\n"
            f"      protocol: {p.get('protocol', 'TCP')}"
        )
        for p in expose
    )

    route_block = _render_route_block(name, namespace, primary_port, target)

    return f"""---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {name}
  namespace: {namespace}
  labels:
{labels}
spec:
  replicas: {replicas}
  selector:
    matchLabels:
      app.kubernetes.io/name: {name}
  template:
    metadata:
      labels:
        app.kubernetes.io/name: {name}
        app.kubernetes.io/part-of: nawex-migrated
    spec:
      automountServiceAccountToken: false
      securityContext:
        runAsNonRoot: true
        runAsUser: 10001
        runAsGroup: 10001
        fsGroup: 10001
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: {name}
          image: REPLACE_ME/{name}:1.0
          imagePullPolicy: IfNotPresent
          ports:
{ports_yaml}
          env:
{chr(10).join(env_yaml) if env_yaml else "            []"}
          resources:
            requests:
              cpu: "{cpu_m}m"
              memory: "{mem_mib}Mi"
            limits:
              cpu: "{cpu_m * 2}m"
              memory: "{mem_mib * 2}Mi"
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
            readOnlyRootFilesystem: true
{chr(10).join(probes)}
---
apiVersion: v1
kind: Service
metadata:
  name: {name}
  namespace: {namespace}
spec:
  selector:
    app.kubernetes.io/name: {name}
  ports:
{svc_ports_yaml}
{route_block}"""


def _render_route_block(
    name: str, namespace: str, primary_port: int, target: dict[str, Any]
) -> str:
    """Emit an OpenShift Route when the target is openshift and exposure is requested.

    Returns an empty string for non-openshift targets or when expose_externally is
    false — keeps the Service cluster-internal (the default, safer posture).
    """
    if target.get("cluster") != "openshift" or not target.get("expose_externally", False):
        return ""
    termination = target.get("tls_termination", "edge")
    return f"""---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: {name}
  namespace: {namespace}
spec:
  to:
    kind: Service
    name: {name}
    weight: 100
  port:
    targetPort: http-{primary_port}
  tls:
    termination: {termination}
    insecureEdgeTerminationPolicy: Redirect
  wildcardPolicy: None
"""


def render_kustomization(profile: dict[str, Any]) -> str:
    return (
        "apiVersion: kustomize.config.k8s.io/v1beta1\n"
        "kind: Kustomization\n"
        f"namespace: {profile['spec']['target'].get('namespace', 'nawex-migrated')}\n"
        "resources:\n  - deployment.yaml\n"
        "commonLabels:\n"
        f"  nawex.io/target-cluster: {profile['spec']['target']['cluster']}\n"
    )


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--profile", type=Path, required=True)
    p.add_argument("--out", type=Path, required=True)
    return p.parse_args()


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    args = parse_args()
    profile = parse_yaml(args.profile.read_text(encoding="utf-8"))
    name = profile["metadata"]["name"]
    out = args.out / name
    out.mkdir(parents=True, exist_ok=True)
    (out / "Dockerfile").write_text(render_dockerfile(profile), encoding="utf-8")
    (out / "deployment.yaml").write_text(render_k8s(profile), encoding="utf-8")
    (out / "kustomization.yaml").write_text(render_kustomization(profile), encoding="utf-8")
    logger.info("wrote Dockerfile + manifests to %s", out)
    logger.info("next: docker build -t <registry>/%s:1.0 %s && docker push ...", name, out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
