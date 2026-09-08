#!/usr/bin/env python3
"""Build a deterministic runtime ZIP; exclude .git, review proposals and tooling."""
from pathlib import Path
import argparse
import zipfile
import os
import tempfile


def build(root: Path, output: Path) -> int:
    root, output = root.resolve(), output.resolve()
    if output == root or output.is_relative_to(root):
        raise ValueError("Output must be outside the entire addon source directory")
    allowed_files = {"README.md", "HAMMER.md", "LICENSE", "seamless_portals.fgd",
                     "RELEASE_NOTES.md", "CONFIGURATION.md", "CHANGELOG.md", "NOTICE.md", "addon.json"}
    entries = []
    for path in root.rglob("*"):
        if not path.is_file() or path.is_symlink():
            continue
        relative = path.relative_to(root)
        if relative.as_posix() not in allowed_files and relative.parts[0] not in {"lua", "materials"}:
            continue
        if "tests" in relative.parts or not path.resolve().is_relative_to(root):
            continue
        entries.append((relative.as_posix(), path))
    if not (root / "lua/entities/seamless_portal/sh_init.lua").is_file():
        raise ValueError("Source root is not the Seamless Portals addon")
    output.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=".seamless-", suffix=".zip", dir=output.parent)
    os.close(descriptor)
    temporary = Path(temporary_name)
    try:
        with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            for relative, path in sorted(entries):
                info = zipfile.ZipInfo("seamless/" + relative, date_time=(1980, 1, 1, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = 0o100644 << 16
                archive.writestr(info, path.read_bytes())
        os.replace(temporary, output)
    finally:
        temporary.unlink(missing_ok=True)
    return len(entries)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        print(f"Packaged {build(args.source, args.output)} allowlisted files")
    except (OSError, ValueError, zipfile.BadZipFile) as exc:
        parser.exit(1, f"Release build failed: {exc}\n")
