#!/usr/bin/env python3
"""Extract findings JSON from a single agent stdout (no merge needed)."""
import json, sys, re
from pathlib import Path

def extract(text: str) -> list[dict]:
    text = text.strip()
    if not text:
        return []
    # Try direct JSON
    for pattern in [
        lambda t: json.loads(t),
        lambda t: json.loads(t[t.find("["):t.rfind("]")+1]),
        lambda t: json.loads(t[t.find("{"):t.rfind("}")+1]).get("findings", []),
        lambda t: json.loads("[" + t + "]") if not t.strip().startswith("[") else [],
    ]:
        try:
            result = pattern(text)
            if isinstance(result, list) and all(isinstance(x, dict) for x in result):
                return result
            if isinstance(result, dict) and "findings" in result:
                return result["findings"]
        except:
            continue

    # Try extracting JSON array with regex
    m = re.search(r"\[.*\]", text, re.DOTALL)
    if m:
        try:
            return json.loads(m.group())
        except:
            pass
    return []

def main():
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--agent-dir", required=True, help="agent output directory")
    parser.add_argument("--out", required=True, help="output findings_acc.json")
    parser.add_argument("--accumulated", default=None, help="existing findings to merge with")
    args = parser.parse_args()

    agent_dir = Path(args.agent_dir)
    stdout = agent_dir / "stdout.log"
    if not stdout.exists():
        print(f"No stdout.log in {agent_dir}", file=sys.stderr)
        sys.exit(1)

    text = stdout.read_text()
    findings = extract(text)

    if not findings:
        print("Failed to extract findings from agent output", file=sys.stderr)
        sys.exit(1)

    # Assign IDs and basic metadata
    for i, f in enumerate(findings):
        if "id" not in f or not f["id"]:
            f["id"] = f"F-{i+1:03d}"
        if "round" not in f:
            f["round"] = 1
        if "source_agents" not in f:
            f["source_agents"] = ["deepseek"]

    # Merge with accumulated if provided
    if args.accumulated:
        acc_path = Path(args.accumulated)
        if acc_path.exists():
            existing = json.loads(acc_path.read_text())
            existing_ids = {f["id"] for f in existing if isinstance(f, dict)}
            for f in findings:
                if f["id"] in existing_ids:
                    f["id"] = f"F-{len(existing)+1:03d}"
            findings = existing + findings

    Path(args.out).write_text(json.dumps(findings, indent=2, ensure_ascii=False))
    print(f"Extracted {len(findings)} findings")

if __name__ == "__main__":
    main()
