#!/usr/bin/env python3
"""Save validation results to CSV."""
import json, csv, sys, os
from pathlib import Path
from datetime import datetime

output_dir = Path(sys.argv[1])
results_dir = Path(sys.argv[2])
csv_path = results_dir / "attempts.csv"

case_name = output_dir.name
rows = []

for summary_path in output_dir.glob("foundry_validation/summary.json"):
    d = json.loads(summary_path.read_text())
    for r in d.get("results", []):
        fid = r["id"]
        title = r.get("title", "")[:80]
        sev = r.get("severity", "")

        for sa in r.get("successful_attempts", []):
            rows.append({
                "case": case_name,
                "finding_id": fid,
                "severity": sev,
                "title": title,
                "attempt": sa.get("attempt", "?"),
                "status": "PASS",
                "profit_wei": sa.get("profit_score", 0) or sa.get("profit_any", 0) or 0,
                "profit_token": sa.get("profit_token", ""),
                "timestamp": datetime.now().isoformat()
            })

        if not r.get("successful_attempts") and r.get("forge_test_passed") is not None:
            rows.append({
                "case": case_name,
                "finding_id": fid,
                "severity": sev,
                "title": title,
                "attempt": r.get("attempts_used", 0),
                "status": "PASS" if r.get("forge_test_passed") else "FAIL",
                "profit_wei": r.get("profit_any", 0) or 0,
                "profit_token": r.get("successful_attempts", [{}])[0].get("profit_token", "") if r.get("successful_attempts") else "",
                "timestamp": datetime.now().isoformat()
            })

if rows:
    file_exists = csv_path.exists()
    with open(csv_path, "a" if file_exists else "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=rows[0].keys())
        if not file_exists:
            writer.writeheader()
        writer.writerows(rows)
    print(f"Saved {len(rows)} records for {case_name}")
