from __future__ import annotations

from pathlib import Path

import containerize  # type: ignore[import-not-found]
import pytest

SAMPLE = Path(__file__).resolve().parents[1] / "samples" / "legacy-reporting-api.yaml"


def test_parse_sample_yaml_roundtrip() -> None:
    data = containerize.parse_yaml(SAMPLE.read_text(encoding="utf-8"))
    assert data["apiVersion"] == "nawex.io/v1"
    assert data["metadata"]["name"] == "legacy-reporting-api"
    assert data["spec"]["target"]["cluster"] == "aws-eks"


def test_render_dockerfile_contains_runtime_base() -> None:
    data = containerize.parse_yaml(SAMPLE.read_text(encoding="utf-8"))
    df = containerize.render_dockerfile(data)
    assert "FROM python:3.12-slim" in df
    assert "USER 10001:10001" in df
    assert "gunicorn" in df


def test_render_k8s_has_required_pieces() -> None:
    data = containerize.parse_yaml(SAMPLE.read_text(encoding="utf-8"))
    k8s = containerize.render_k8s(data)
    assert "kind: Deployment" in k8s
    assert "kind: Service" in k8s
    assert "namespace: nawex-migrated" in k8s
    assert "nawex.io/target-cluster: aws-eks" in k8s
    assert "readOnlyRootFilesystem: true" in k8s


def test_render_kustomization_includes_target_label() -> None:
    data = containerize.parse_yaml(SAMPLE.read_text(encoding="utf-8"))
    kust = containerize.render_kustomization(data)
    assert "nawex.io/target-cluster: aws-eks" in kust
    assert "deployment.yaml" in kust


@pytest.mark.parametrize(
    "runtime,expected",
    [
        ("python3.12", "python:3.12-slim"),
        ("node20", "node:20-slim"),
        ("java17", "eclipse-temurin:17-jre-jammy"),
        ("generic-debian", "debian:12-slim"),
    ],
)
def test_runtime_base_mapping(runtime: str, expected: str) -> None:
    assert containerize.RUNTIME_BASE[runtime] == expected
