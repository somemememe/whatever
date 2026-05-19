#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path

SEVERITIES = ["Critical", "High", "Medium", "Low", "Informational"]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--findings", required=True)
    parser.add_argument("--output", default="-")
    args = parser.parse_args()

    findings = json.loads(Path(args.findings).read_text(encoding="utf-8"))
    if not isinstance(findings, list):
        raise SystemExit("findings file must be a JSON array")

    parts = [f"# Audit Report\n\n**Total findings:** {len(findings)}\n"]
    for sev in SEVERITIES:
        items = [item for item in findings if item.get("severity") == sev]
        if not items:
            continue
        parts.append(f"## {sev} ({len(items)})\n")
        for item in items:
            parts.append(f"### {item.get('id', '?')}: {item.get('title', '')}\n")
            locations = item.get("locations", [])
            if isinstance(locations, list):
                location_text = ", ".join(locations)
            else:
                location_text = str(locations)
            parts.append(
                f"**Confidence:** {item.get('confidence', '?')} | "
                f"**Locations:** `{location_text}`\n"
            )
            if item.get("claim"):
                parts.append(f"{item['claim']}\n")
            if item.get("impact"):
                parts.append(f"**Impact:** {item['impact']}\n")
            paths = item.get("paths", item.get("checks", []))
            if isinstance(paths, list) and paths:
                parts.append("**Paths:**\n")
                for path in paths:
                    parts.append(f"- {path}\n")
            sources = ", ".join(item.get("source_agents", []))
            parts.append(f"*Round {item.get('round', '?')} | Agents: {sources}*\n")
            parts.append("---\n")

    content = "\n".join(parts).strip() + "\n"
    if args.output == "-":
        print(content, end="")
    else:
        Path(args.output).write_text(content, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
