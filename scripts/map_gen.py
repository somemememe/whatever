#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import sys
from fnmatch import fnmatchcase
from pathlib import Path


def load_excludes(cli_excludes: list[str]) -> list[str]:
    if cli_excludes:
        return cli_excludes

    raw = os.environ.get("AUDITHOUND_EXCLUDE_GLOBS", "").strip()
    if not raw:
        return []

    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"AUDITHOUND_EXCLUDE_GLOBS must be a JSON array: {exc}") from exc

    if not isinstance(data, list) or not all(isinstance(item, str) for item in data):
        raise SystemExit("AUDITHOUND_EXCLUDE_GLOBS must be a JSON array of strings")

    return data


def load_includes(cli_includes: list[str]) -> list[str]:
    if cli_includes:
        return cli_includes

    raw = os.environ.get("AUDITHOUND_INCLUDE_GLOBS", "").strip()
    if not raw:
        return []

    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"AUDITHOUND_INCLUDE_GLOBS must be a JSON array: {exc}") from exc

    if not isinstance(data, list) or not all(isinstance(item, str) for item in data):
        raise SystemExit("AUDITHOUND_INCLUDE_GLOBS must be a JSON array of strings")

    return data


def matches_pattern(rel_path: str, pattern: str) -> bool:
    normalized = pattern.strip().strip("/")
    if not normalized:
        return False
    if rel_path == normalized or rel_path.startswith(normalized + "/"):
        return True
    return fnmatchcase(rel_path, normalized)


def is_excluded(rel_path: str, excludes: list[str]) -> bool:
    return any(matches_pattern(rel_path, pattern) for pattern in excludes)


def is_included(rel_path: str, includes: list[str]) -> bool:
    if not includes:
        return True
    return any(matches_pattern(rel_path, pattern) for pattern in includes)


def scan(sol_dir: Path, excludes: list[str], includes: list[str]) -> list[str]:
    lines: list[str] = []
    for path in sorted(sol_dir.rglob("*.sol")):
        # Some workspaces contain directories ending with .sol; skip non-files.
        if not path.is_file():
            continue
        rel = path.relative_to(sol_dir).as_posix()
        if not is_included(rel, includes):
            continue
        if is_excluded(rel, excludes):
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        loc = len(text.splitlines())
        lines.append(f"- {rel} ({loc} LOC) — TODO")
    return lines


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("sol_dir")
    parser.add_argument(
        "--exclude",
        action="append",
        default=[],
        help="Glob-like relative path to exclude from direct audit scope, e.g. interfaces/**",
    )
    parser.add_argument(
        "--include",
        action="append",
        default=[],
        help="Glob-like relative path to include in direct audit scope, e.g. LayerZero/**",
    )
    args = parser.parse_args()

    sol_dir = Path(args.sol_dir).resolve()
    if not sol_dir.is_dir():
        print(f"Target directory not found: {sol_dir}", file=sys.stderr)
        return 1

    excludes = load_excludes(args.exclude)
    includes = load_includes(args.include)

    print("# Scope\n")
    for line in scan(sol_dir, excludes, includes):
        print(line)
    print("\n# Notes\n")
    print("- Auto-generated file-level map.")
    print("- Descriptions are placeholders and can be edited later.")
    if includes:
        print(f"- Included in direct audit scope: {', '.join(includes)}")
    if excludes:
        print(f"- Excluded from direct audit scope: {', '.join(excludes)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
