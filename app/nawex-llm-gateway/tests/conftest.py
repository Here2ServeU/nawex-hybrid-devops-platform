"""Preload app.py under the name `app`, bypassing the repo-root `app/` namespace package."""

import importlib.util
import sys
from pathlib import Path

_APP_PY = Path(__file__).resolve().parents[1] / "app.py"
_spec = importlib.util.spec_from_file_location("app", _APP_PY)
assert _spec is not None and _spec.loader is not None
_module = importlib.util.module_from_spec(_spec)
sys.modules["app"] = _module
_spec.loader.exec_module(_module)
