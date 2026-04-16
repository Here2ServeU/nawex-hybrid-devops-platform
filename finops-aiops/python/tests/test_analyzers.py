from __future__ import annotations

import anomaly_detector
import budget_burn_predictor
import rightsizing_engine
import slo_risk_checker
from _common import risk_from_burn_rate


def test_risk_from_burn_rate_boundaries() -> None:
    assert risk_from_burn_rate(0.5) == "low"
    assert risk_from_burn_rate(1.0) == "medium"
    assert risk_from_burn_rate(2.0) == "high"
    assert risk_from_burn_rate(4.1) == "critical"


def test_analyzers_return_required_shape() -> None:
    for analyze in (
        anomaly_detector.analyze,
        budget_burn_predictor.analyze,
        rightsizing_engine.analyze,
        slo_risk_checker.analyze,
    ):
        report = analyze()
        assert "analyzer" in report
        assert "severity" in report
        assert "action" in report
        assert "runbook" in report


def test_budget_drift_is_positive_when_over_budget() -> None:
    report = budget_burn_predictor.analyze()
    assert report["drift_percent"] > 0


def test_slo_risk_projects_breach_window() -> None:
    report = slo_risk_checker.analyze()
    assert report["hours_to_breach_if_sustained"] is not None
    assert report["risk"] in {"low", "medium", "high", "critical"}
