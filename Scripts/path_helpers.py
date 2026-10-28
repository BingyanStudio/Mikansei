#!/usr/bin/env python3
"""Shared paths for local builds and delivery output."""
import os
from pathlib import Path
import sys
from typing import Mapping, Optional


def _configured_path(value: str, repository_root: Path) -> Path:
    path = Path(value)
    if not path.is_absolute():
        path = repository_root / path
    return path.resolve()


def toolchains_dir(repository_root: Path) -> Optional[Path]:
    """Return the override or first ancestor .toolchains directory, if found."""
    repository_root = Path(repository_root).resolve()
    override = os.environ.get("MIKANSEI_TOOLCHAINS_DIR")
    if override:
        return _configured_path(override, repository_root)

    for ancestor in (repository_root, *repository_root.parents):
        candidate = ancestor / ".toolchains"
        if candidate.is_dir():
            return candidate.resolve()
    return None


def releases_dir(repository_root: Path) -> Path:
    """Return the configured delivery root or the sibling Releases directory."""
    repository_root = Path(repository_root).resolve()
    override = os.environ.get("MIKANSEI_RELEASES_DIR")
    if override:
        return _configured_path(override, repository_root)
    return repository_root.parent / "Releases"


def version_build(info: Mapping[str, object]) -> str:
    """Build the version+build directory name from an app's Info.plist data."""
    version = info.get("CFBundleShortVersionString")
    build = info.get("CFBundleVersion")
    if not version or not build:
        raise ValueError("App Info.plist must contain version and build values.")
    return f"{version}+{build}"


def main() -> int:
    if len(sys.argv) != 3 or sys.argv[1] not in {"releases", "toolchains"}:
        print("usage: path_helpers.py (releases|toolchains) REPOSITORY_ROOT", file=sys.stderr)
        return 2

    repository_root = Path(sys.argv[2])
    path = releases_dir(repository_root) if sys.argv[1] == "releases" else toolchains_dir(repository_root)
    if path is not None:
        print(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
