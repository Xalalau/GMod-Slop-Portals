#!/usr/bin/env python3
"""Run source-level checks and explicit test doubles; NOT a native Garry's Mod test."""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
from pathlib import Path
import platform
import subprocess
import sys


def validate(root: Path, destination: Path) -> int:
    root = root.resolve()
    destination = destination.resolve()
    required = [
        "lua/seamless_portals/core.lua", "tools/check_source.py",
        "validation/regression_tests.py", "validation/integration_tests.py", "validation/custom_feature_tests.py", "validation/field_fix_tests.py",
    ]
    missing = [name for name in required if not (root / name).is_file()]
    if missing:
        raise ValueError("Incomplete source package: " + ", ".join(missing))
    if destination == root or any(destination.is_relative_to(root / folder)
                                  for folder in ("lua", "materials", "tools")):
        raise ValueError("Results must not be written into runtime or tooling directories")
    destination.mkdir(parents=True, exist_ok=True)
    environment = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
    runs = []
    commands = [
        ("textual-gates", [str(root / "tools/check_source.py"), str(root)]),
        ("regression", [str(root / "validation/regression_tests.py"), str(root),
                        "--output", str(destination / "regression-results.json")]),
        ("integration", [str(root / "validation/integration_tests.py"), str(root),
                         "--output", str(destination / "integration-results.json")]),
        ("custom", [str(root / "validation/custom_feature_tests.py"), str(root),
                    "--output", str(destination / "custom-results.json")]),
        ("field", [str(root / "validation/field_fix_tests.py"), str(root),
                   "--output", str(destination / "field-results.json")]),
    ]
    # Avoid mistaking a previous successful result for evidence from a failed run.
    for filename in ("regression-results.json", "integration-results.json", "custom-results.json", "field-results.json"):
        (destination / filename).unlink(missing_ok=True)
    for name, arguments in commands:
        command = [sys.executable, *arguments]
        try:
            completed = subprocess.run(command, cwd=root, env=environment,
                                       capture_output=True, text=True, timeout=120)
            code = completed.returncode
            output = completed.stdout + completed.stderr
        except (OSError, subprocess.TimeoutExpired) as exc:
            code, output = 1, str(exc)
        (destination / (name + ".log")).write_text(output, encoding="utf-8")
        runs.append({"name": name, "command": command, "returncode": code,
                     "status": "PASS" if code == 0 else "FAIL"})
        print(f"{runs[-1]['status']}: {name}")
        if code:
            print(output, file=sys.stderr)
    python_syntax = []
    for path in sorted(root.rglob("*.py")):
        if "__pycache__" in path.parts or ".git" in path.parts:
            continue
        try:
            # Compile without executing or writing bytecode into the source tree.
            compile(path.read_bytes(), str(path), "exec")
            status, error = "PASS", None
        except (OSError, SyntaxError, ValueError) as exc:
            status, error = "FAIL", str(exc)
        python_syntax.append({"file": path.relative_to(root).as_posix(),
                              "status": status, "error": error})
    reports = {}
    for name in ("regression", "integration", "custom", "field"):
        try:
            reports[name] = json.loads((destination / (name + "-results.json")).read_text())
        except (OSError, ValueError):
            reports[name] = {"tests": [], "passed": 0, "failed": 1, "missing_results": True}
    syntax = reports["regression"].get("normalized_syntax", [])
    passed = sum(report["passed"] for report in reports.values())
    failed = sum(report["failed"] for report in reports.values())
    success = (not failed and all(run["returncode"] == 0 for run in runs)
               and all(item["status"] == "PASS" for item in python_syntax)
               and bool(syntax) and all(item["status"] == "PASS" for item in syntax))
    summary = {
        "status": "PASS" if success else "FAIL",
        "recorded_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "native_gmod_tested": False,
        "python_version": platform.python_version(),
        "platform": platform.platform(),
        "commands": runs,
        "unit_checks_passed": passed,
        "unit_checks_failed": failed,
        "regression_checks_passed": reports["regression"]["passed"],
        "integration_checks_passed": reports["integration"]["passed"],
        "custom_checks_passed": reports["custom"]["passed"],
        "field_checks_passed": reports["field"]["passed"],
        "normalized_lua_syntax_passed": sum(item["status"] == "PASS" for item in syntax),
        "normalized_lua_syntax_total": len(syntax),
        "python_syntax": python_syntax,
        "limits": ("Source excerpts execute under Lua 5.4 with explicit engine doubles. "
                   "Whole-file GLua syntax is normalized and is not native compilation. "
                   "No native rendering, physics, prediction, networking, performance or gameplay validation."),
    }
    (destination / "validation-summary.json").write_text(
        json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(f"{summary['status']}: {passed} unit checks passed; {failed} failed; "
          f"{summary['normalized_lua_syntax_passed']}/{len(syntax)} normalized Lua syntax checks; "
          f"{len(python_syntax)} Python syntax checks. NOT native GMod.")
    return 0 if success else 1


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, nargs="?", default=Path(__file__).resolve().parents[1])
    parser.add_argument("--results", type=Path,
                        help="Result directory (default: a sibling of the addon source)")
    args = parser.parse_args()
    try:
        output = args.results or args.source.resolve().parent / "seamless-validation"
        raise SystemExit(validate(args.source, output))
    except (OSError, ValueError) as exc:
        parser.exit(1, f"Validation setup failed: {exc}\n")
