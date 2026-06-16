#!/usr/bin/env python3
"""Batch regression: audit + PoC for N cases with M parallel workers.
Usage: python3 batch_regression.py <workers> [case_limit]
Example: python3 batch_regression.py 4 64"""
import json, os, sys, time, random, subprocess
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime

CASES_DIR = Path("/root/audithound_new/cases")
OUTPUT_DIR = Path("/root/audithound_new/output")
RESULTS_DIR = Path("/root/audithound_new/results")
ARCHIVE_RPCS = [
    "https://mainnet.infura.io/v3/e256143b4bb44b44a98e9b22b0290400",
    "https://mainnet.infura.io/v3/a5fc4fc5ece34a6eb6e8dfe627dce240",
    "https://ethereum.blockpi.network/v1/rpc/9864568b5fe8b75df7f3a38dc5b8742f5b6efaba",
    "https://eth-mainnet.g.alchemy.com/v2/YB8p9sQb6OE4_ZXJP1I5W",
    "https://eth-mainnet.g.alchemy.com/v2/p6UDlMQUt1PeyOcmJpF6Y",
]
def _pick_rpc(name):
    return ARCHIVE_RPCS[hash(name) % len(ARCHIVE_RPCS)]
WORKERS = int(sys.argv[1]) if len(sys.argv) > 1 else 4
CASE_LIMIT = int(sys.argv[2]) if len(sys.argv) > 2 else None
API_KEY = os.environ.get("DEEPSEEK_API_KEY", "sk-2afbc20ad8544e66a6194363f917d8a7")
ETHERSCAN_KEY = os.environ.get("ETHERSCAN_API_KEY", "ZFNNGRNEUNGRH3XHGE5A61Q3MVGIEVF31K")

os.environ["DEEPSEEK_API_KEY"] = API_KEY
os.environ["ETHERSCAN_API_KEY"] = ETHERSCAN_KEY
os.environ["PATH"] = os.environ.get("PATH", "") + ":/root/.foundry/bin"
RESULTS_DIR.mkdir(parents=True, exist_ok=True)
(RESULTS_DIR / "audit").mkdir(exist_ok=True)
(RESULTS_DIR / "poc").mkdir(exist_ok=True)

def log(msg):
    ts = datetime.now().strftime("%H:%M:%S")
    print(f"[{ts}] {msg}", flush=True)

def collect_cases():
    cases = []
    for mf in sorted(CASES_DIR.glob("*/manifest.json")):
        try:
            d = json.loads(mf.read_text())
        except:
            continue
        block = d.get("fork_block_number", 0)
        target = d.get("target_contract_address", "")
        if not block or block == 0 or not target:
            continue
        name = mf.parent.name
        case_dir = str(mf.parent)
        has_src = (mf.parent / "src" / "onchain_auto").is_dir()
        cases.append((name, case_dir, block, target, has_src))
    random.shuffle(cases)
    if CASE_LIMIT:
        cases = cases[:CASE_LIMIT]
    return cases

def run_audit(name, case_dir, block, target, has_src):
    out_dir = OUTPUT_DIR / f"{name}_regression"
    out_dir.mkdir(parents=True, exist_ok=True)
    findings_file = out_dir / "findings_acc.json"

    if findings_file.exists():
        try:
            cnt = len(json.loads(findings_file.read_text()))
            if cnt > 0:
                log(f"[{name}] Audit: skip ({cnt} findings exist)")
                return cnt
        except:
            pass

    target_path = str(Path(case_dir) / "src" / "onchain_auto") if has_src else str(Path(case_dir) / "manifest.json")
    src_label = "local" if has_src else "auto-fetch"
    log(f"[{name}] Audit: running ({src_label})...")

    result = subprocess.run([
        "python3", "scripts/audithound.py", "run", target_path,
        "--agent", "deepseek", "--workers", "1", "--max-rounds", "1",
        "--output-dir", str(out_dir),
    ], cwd="/root/audithound_new", capture_output=True, text=True, timeout=600)

    if result.returncode != 0:
        log(f"[{name}] Audit: FAILED - {result.stderr[-200:]}")
        return 0

    try:
        cnt = len(json.loads(findings_file.read_text()))
    except:
        cnt = 0
    log(f"[{name}] Audit: {cnt} findings")
    return cnt

def run_poc(name, case_dir, block, target):
    out_dir = OUTPUT_DIR / f"{name}_regression"
    findings_file = out_dir / "findings_acc.json"

    try:
        findings = json.loads(findings_file.read_text())
    except:
        return False
    if not findings:
        return False

    summary_file = out_dir / "foundry_validation" / "summary.json"
    if summary_file.exists():
        log(f"[{name}] PoC: skip (already done)")
        return True

    mf = {"audit_id": name, "chain": "mainnet", "fork_block_number": block,
          "target_contract_address": target, "evm_version": "shanghai",
          "target_root": str(Path(case_dir) / "src")}
    mf_path = Path(f"/tmp/mf_batch_{name}.json")
    mf_path.write_text(json.dumps(mf))

    log(f"[{name}] PoC: {len(findings)} findings...")

    result = subprocess.run([
        "python3", "scripts/audithound.py", "validate",
        "--manifest", str(mf_path), "--output-dir", str(out_dir),
        "--tool-provider", "deepseek", "--tool-model", "deepseek-v4-pro",
        "--max-attempts", "1", "--top-k", "99", "--min-profit", "0.001",
        "--rpc-url", RPC,
    ], cwd="/root/audithound_new", capture_output=True, text=True, timeout=1800)

    subprocess.run(["python3", "scripts/save_results.py", str(out_dir), str(RESULTS_DIR)],
                   cwd="/root/audithound_new", capture_output=True)

    passed = summary_file.exists()
    log(f"[{name}] PoC: {'PASS' if passed else 'FAIL'}")
    return passed

def process_case(case):
    name, case_dir, block, target, has_src = case
    try:
        cnt = run_audit(name, case_dir, block, target, has_src)
        if cnt > 0:
            run_poc(name, case_dir, block, target)
    except Exception as e:
        log(f"[{name}] ERROR: {e}")

def export_csv():
    rows = []
    for s in sorted(OUTPUT_DIR.glob("*_regression/foundry_validation/summary.json")):
        d = json.loads(s.read_text())
        case = s.parent.parent.name
        for r in d.get("results", []):
            for sa in r.get("successful_attempts", []):
                rows.append({"case": case, "finding_id": r["id"], "status": "PASS",
                            "profit_wei": sa.get("profit_score", 0),
                            "timestamp": datetime.now().isoformat()})
            if not r.get("successful_attempts") and r.get("forge_test_passed") is not None:
                rows.append({"case": case, "finding_id": r["id"],
                            "status": "PASS" if r.get("forge_test_passed") else "FAIL",
                            "profit_wei": r.get("profit_any", 0) or 0,
                            "timestamp": datetime.now().isoformat()})
    if rows:
        p = RESULTS_DIR / "batch_results.csv"
        with open(p, "w", newline="") as f:
            import csv
            w = csv.DictWriter(f, fieldnames=rows[0].keys())
            w.writeheader()
            w.writerows(rows)
        print(f"Exported {len(rows)} records to {p}")

def main():
    cases = collect_cases()
    log(f"Starting {len(cases)} cases, {WORKERS} workers")

    with ThreadPoolExecutor(max_workers=WORKERS) as executor:
        futures = {executor.submit(process_case, c): c[0] for c in cases}
        done = 0
        for _ in as_completed(futures):
            done += 1
            if done % 10 == 0:
                log(f"Progress: {done}/{len(cases)}")

    export_csv()
    log("ALL DONE")

if __name__ == "__main__":
    main()
