#!/usr/bin/env python3
"""Small textual regression gates. This is deliberately NOT a GLua compiler."""
from pathlib import Path
import argparse
import re
import sys


def check(root: Path) -> list[str]:
    files = list((root / "lua").rglob("*.lua"))
    if not files:
        return ["No Lua files found"]
    errors, registrations = [], {}
    banned = ["SWEP.SetHoldType =", "AutoSwichTo", "AutoSwichFrom", "DrawChrosshair", "constraint.RemoveAll(ent)"]
    for path in files:
        text = path.read_text(encoding="utf-8")
        for token in banned:
            if token in text:
                errors.append(f"{path}: forbidden regression token {token}")
        for name in re.findall(r'CreateClientConVar\("([^"\n]+)"', text):
            if name in registrations:
                errors.append(f"{path}: duplicate literal client convar {name}; also {registrations[name]}")
            registrations[name] = path
    required = {
        "lua/seamless_portals/core.lua": ["function SP.ValidateSides", "function SP.ComposeTraceFilter", "function SP.TransformDirection"],
        "lua/entities/seamless_portal/sh_init.lua": ["function ENT:ReconcileGeometry", "function ENT:Configure"],
        "lua/seamless_portals/traces.lua": ["SeamlessPortals.TracePortalLine = function", "SeamlessSegments"],
    }
    for relative, tokens in required.items():
        path = root / relative
        if not path.is_file():
            errors.append(f"Missing {relative}")
            continue
        for token in tokens:
            if token not in path.read_text(encoding="utf-8"):
                errors.append(f"{relative}: missing invariant entry point {token}")
    return errors


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, nargs="?", default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    failures = check(args.source)
    for failure in failures:
        print(failure, file=sys.stderr)
    print("FAIL" if failures else "PASS: textual regression gates only; native compile/smoke tests still required")
    raise SystemExit(bool(failures))
