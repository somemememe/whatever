#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path


def load_findings(path: Path) -> list[dict]:
    if not path.exists() or not path.read_text(encoding="utf-8").strip():
        return []
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, list):
        raise SystemExit(f"findings file must be a JSON array: {path}")
    return data


def format_known_findings(findings: list[dict]) -> str:
    if not findings:
        return "None yet."
    lines = []
    for item in findings:
        lines.append(
            f"- {item.get('id', '?')}: {item.get('title', '?')} "
            f"({item.get('severity', '?')}, {item.get('confidence', '?')})"
        )
    return "\n".join(lines)


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


def build_prompt(
    target: str,
    code_map: str,
    findings: list[dict],
    round_summary_path: str | None,
    global_summary_path: str | None,
    excludes: list[str],
    includes: list[str],
) -> str:
    summary_note = ""
    if round_summary_path:
        summary_note = f"""
## Optional Prior Round Summary

An optional prior round summary is available at:
- `{round_summary_path}`

Read it only if useful, and think it before you use it.It may not be very concise.
"""
    global_note = ""
    if global_summary_path:
        global_note = f"""
## Optional Global Audit Memory

An optional global audit memory is available at:
- `{global_summary_path}`

Read it only if useful. It is historical context, not a coverage guarantee,
not proof that any area is safe, and not a priority list.
"""
    exclude_note = ""
    if excludes:
        exclude_lines = "\n".join(f"- `{item}`" for item in excludes)
        exclude_note = f"""
## Excluded From Direct Audit Scope

Do not report findings whose root cause exists solely in files matching:
{exclude_lines}

You may still read those files when they define interfaces, structs, errors, or external integration context used by in-scope implementation files.
"""
    include_note = ""
    if includes:
        include_lines = "\n".join(f"- `{item}`" for item in includes)
        include_note = f"""
## Included Direct Audit Scope

Only keep findings whose root cause location is inside files matching:
{include_lines}

You may still read other files in the target directory for context, but do not report them as root cause locations.
"""
    return f"""You are auditing the smart contracts in {target}.

## Contracts in Scope

{code_map}
{include_note}
{exclude_note}

## Known Findings (do not duplicate)

{format_known_findings(findings)}
{summary_note}
{global_note}

## Task

Find security vulnerabilities in the contracts listed above as more as you can.And there are lots of high severity vulns.

You should look for:
- vulnerabilities
- reportable issues

Known findings are not proof that a file, function, or theme is fully audited.
Do not repeat the same root cause, but keep investigating nearby code and related mechanisms.
Report a new finding when it has a distinct root cause, exploit path, impact, or materially stronger version of an existing issue.

Audit only Solidity source files under the target directory above.
Do not inspect or rely on files outside that directory, including README, docs, audit reports, discord exports, scripts, broadcasts, or other repository context, unless they are explicitly included in the target directory.

If you identify a problem that is not fully proven, still report it as a low-confidence finding.
Be skeptical of documented behavior and pure owner-only configuration issues, but you may still report them when they create realistic protocol-level harm such as fund loss, theft, insolvency, permanent lockup, economic manipulation, or permissionless denial of service.

## Output Format

Return ONLY a JSON array.

Each element must have:
- `id`: local finding id such as `F-001`
- `severity`: `Critical` / `High` / `Medium` / `Low` / `Informational`
- `confidence`: `high` / `medium` / `low`
- `title`: one-line summary
- `locations`: array of `file:line`
- `claim`: core mechanism statement
- `impact`: why it matters
- `paths`: array of trigger/exploit paths, may be empty

If there are no findings, return `[]`.
"""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--map", required=True)
    parser.add_argument("--findings", required=True)
    parser.add_argument("--target", required=True)
    parser.add_argument("--round-summary")
    parser.add_argument("--global-summary")
    parser.add_argument("--exclude", action="append", default=[])
    parser.add_argument("--include", action="append", default=[])
    parser.add_argument("--output", default="-")
    args = parser.parse_args()

    code_map = Path(args.map).read_text(encoding="utf-8")
    findings = load_findings(Path(args.findings))
    excludes = load_excludes(args.exclude)
    includes = load_includes(args.include)
    round_summary_path = None
    if args.round_summary:
        summary_path = Path(args.round_summary)
        if summary_path.exists():
            round_summary_path = str(summary_path.resolve())
    global_summary_path = None
    if args.global_summary:
        global_path = Path(args.global_summary)
        if global_path.exists():
            global_summary_path = str(global_path.resolve())
    prompt = build_prompt(args.target, code_map, findings, round_summary_path, global_summary_path, excludes, includes)

    if args.output == "-":
        print(prompt)
    else:
        Path(args.output).write_text(prompt, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
