#!/usr/bin/env python3
"""PoC backfill runner with BLOCKED detection for zero-profit valid exploits."""
import json, os, subprocess, threading, urllib.request, time
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor

_LOG_LOCK = threading.Lock()
_PRICE_CACHE = {}  # token_address -> (eth_price, timestamp)

ARCHIVE_RPCS = [
    "https://eth-mainnet.g.alchemy.com/v2/YB8p9sQb6OE4_ZXJP1I5W",
    "https://ethereum.blockpi.network/v1/rpc/9864568b5fe8b75df7f3a38dc5b8742f5b6efaba",
]
def get_rpc(name):
    return ARCHIVE_RPCS[hash(name) % len(ARCHIVE_RPCS)]

os.environ["PATH"] = os.environ.get("PATH","") + ":/root/.foundry/bin"

def log(msg):
    with _LOG_LOCK:
        print(msg, flush=True)

def detect_blocked(out_dir):
    """Check forge outputs for BLOCKED cases (PoC ran, no profit)."""
    blocked_findings = []
    for fd in out_dir.glob("F-*"):
        if not fd.is_dir():
            continue
        for log_file in fd.glob("forge_stdout_attempt*.log"):
            content = log_file.read_text()
            if "profit below threshold" in content:
                # Extract gas used
                for line in content.split("\n"):
                    if "testExploit() (gas:" in line:
                        try:
                            gas = int(line.split("gas:")[1].split(")")[0].strip())
                            if gas > 50000:  # Real exploit code, not a stub
                                blocked_findings.append(fd.name)
                        except:
                            pass
                        break
    return blocked_findings

WETH = "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2"
SENTINEL_THRESHOLD = 100_000 * 10**18  # 100k ETH


def token_eth_price(token_addr):
    """Get token price in ETH from CoinGecko. Returns float or None."""
    addr = token_addr.lower()
    now = time.time()
    if addr in _PRICE_CACHE:
        price, ts = _PRICE_CACHE[addr]
        if now - ts < 3600:  # cache 1 hour
            return price
    try:
        url = f"https://api.coingecko.com/api/v3/simple/token_price/ethereum?contract_addresses={addr}&vs_currencies=eth"
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        resp = json.loads(urllib.request.urlopen(req, timeout=10).read())
        price = resp.get(addr, {}).get("eth")
        if price is not None:
            _PRICE_CACHE[addr] = (float(price), now)
            return float(price)
    except Exception:
        pass
    # Fallback: try to get decimals and treat stablecoins as ~1/ETH_price
    return None


def token_profit_in_eth(token_addr, raw_amount):
    """Convert raw token profit amount to ETH value. Returns float ETH or None."""
    if not token_addr or token_addr == "0x0000000000000000000000000000000000000000":
        return None
    if token_addr.lower() == WETH:
        return raw_amount / 1e18  # WETH 1:1 with ETH
    price = token_eth_price(token_addr)
    if price is None:
        return None
    return (raw_amount / 1e18) * price  # assume 18 decimals for simplicity


def parse_log_uint(text, key):
    """Parse a logged uint from forge output: 'key: value'"""
    import re
    m = re.search(rf"{key}:\s*(\d+)", text)
    return int(m.group(1)) if m else None


def classify_case_strict(fv_dir):
    """Strict case classification using forge logs.

    PASS: any finding has real profit (not seed conversion, not sentinel)
    BLOCKED: PoC ran but no real profit
    FAIL: nothing worked
    """
    summary_file = fv_dir / "summary.json"
    if not summary_file.exists():
        blocked = detect_blocked(fv_dir)
        if blocked:
            return f"BLOCKED ({len(blocked)} findings ran but no profit)"
        return "FAIL"

    try:
        sd = json.loads(summary_file.read_text())
    except Exception:
        return "FAIL"

    has_pass = False
    has_blocked = False
    details = []

    for r in sd.get("results", []):
        fid = r.get("id", "?")
        pw = r.get("profit_wei", 0) or 0
        pa = r.get("profit_any", 0) or 0
        pt = (r.get("profit_token", "") or "").strip().lower()
        passed = r.get("forge_test_passed", False)
        poc = r.get("poc_generated", False)
        bal_before = r.get("balance_before_wei")
        bal_after = r.get("balance_after_wei")

        # --- FAIL: PoC not generated, nothing executed ---
        if not poc:
            details.append(f"  {fid}: FAIL (no PoC generated)")
            continue

        # --- Sentinel check ---
        best = max(pw, pa)
        for sa in r.get("successful_attempts", []):
            best = max(best, sa.get("profit_score", 0) or 0)
        if best > SENTINEL_THRESHOLD:
            details.append(f"  {fid}: BLOCKED (sentinel: {best/1e18:,.0f} ETH)")
            has_blocked = True
            continue

        # --- Unify everything to ETH value ---
        # Native ETH profit
        profit_eth = pw / 1e18

        # Token profit → ETH value
        token_eth = None
        if pa > 1e15:
            # Get actual token from summary, fallback to attempt
            actual_token = pt
            if (not actual_token or actual_token == "0x0000000000000000000000000000000000000000"):
                for sa in r.get("successful_attempts", []):
                    at = (sa.get("profit_token", "") or "").strip().lower()
                    if at and at != "0x0000000000000000000000000000000000000000":
                        actual_token = at
                        break
            if actual_token and actual_token != "0x0000000000000000000000000000000000000000":
                token_eth = token_profit_in_eth(actual_token, pa)

        # Total profit in ETH
        total_eth = profit_eth + (token_eth if token_eth is not None else 0)

        # Seed spent in ETH
        spent_eth = None
        if bal_before is not None and bal_after is not None and bal_after < bal_before:
            spent_eth = (bal_before - bal_after) / 1e18

        # --- Dust check ---
        if total_eth <= 0.001 and profit_eth <= 0.001:
            if token_eth is None and pa > 1e15:
                details.append(f"  {fid}: BLOCKED (unknown token {pa/1e18:.4f} units, no price, no native ETH)")
            else:
                details.append(f"  {fid}: BLOCKED (total profit {total_eth:.6f} ETH <= 0.001)")
            has_blocked = True
            continue

        # --- Real profit check ---
        if profit_eth > 0.001:
            # Native ETH profit
            if spent_eth is not None and spent_eth > 0.01:
                details.append(f"  {fid}: PASS (native ETH {profit_eth:.4f}, spent {spent_eth:.4f} ETH)")
            else:
                details.append(f"  {fid}: PASS (native ETH {profit_eth:.4f})")
            has_pass = True
            continue

        # Token-only profit
        if token_eth is not None:
            if spent_eth is not None:
                if token_eth > spent_eth:
                    details.append(f"  {fid}: PASS (token value {token_eth:.4f} ETH > spent {spent_eth:.4f} ETH)")
                    has_pass = True
                else:
                    details.append(f"  {fid}: BLOCKED (token value {token_eth:.4f} ETH <= spent {spent_eth:.4f} ETH)")
                    has_blocked = True
            elif 7.0 <= token_eth <= 10.5:
                # Token value suspiciously close to 10 ETH seed, no balance to verify
                details.append(f"  {fid}: BLOCKED (token value {token_eth:.4f} ETH, no balance, near seed)")
                has_blocked = True
            elif token_eth > 10.5:
                # Clearly exceeds seed capital
                details.append(f"  {fid}: PASS (token value {token_eth:.4f} ETH, no balance, exceeds seed)")
                has_pass = True
            elif token_eth > 0.001:
                details.append(f"  {fid}: PASS (token value {token_eth:.4f} ETH, no balance)")
                has_pass = True
            else:
                details.append(f"  {fid}: BLOCKED (token value {token_eth:.6f} ETH, dust)")
                has_blocked = True
        else:
            # No price available for token
            if spent_eth is not None and pa / 1e18 <= spent_eth:
                details.append(f"  {fid}: BLOCKED (token {pa/1e18:.4f} units, no price, <= spent {spent_eth:.4f} ETH)")
                has_blocked = True
            elif bal_before is None and 0.1 <= pa / 1e18 <= 10.5:
                details.append(f"  {fid}: BLOCKED (token {pa/1e18:.4f} units, no price, no balance, seed-range)")
                has_blocked = True
            else:
                details.append(f"  {fid}: BLOCKED (token {pa/1e18:.4f} units, no price)")
                has_blocked = True

    # --- Case-level verdict ---
    if has_pass:
        for d in details:
            log(d)
        return "PASS"
    elif has_blocked:
        for d in details:
            log(d)
        return "BLOCKED"
    else:
        for d in details:
            log(d)
        return "FAIL"


def run_poc_for(name):
    out_dir = Path("/root/audithound_new/output") / name
    ff = out_dir / "findings_acc.json"
    if not ff.exists():
        return
    try:
        findings = json.loads(ff.read_text())
    except:
        return
    if not findings:
        return

    summary_file = out_dir / "foundry_validation" / "summary.json"
    if summary_file.exists():
        return  # already done

    base = name.replace("_regression", "")
    case_dir = Path("/root/audithound_new/cases") / base
    mf = case_dir / "manifest.json"
    if not mf.exists():
        for cd in Path("/root/audithound_new/cases").iterdir():
            if cd.name == base:
                case_dir = cd
                mf = cd / "manifest.json"
                break
    if not mf.exists():
        log(f"[{name}] SKIP: no manifest")
        return

    dd = json.loads(mf.read_text())
    block = dd.get("fork_block_number", 0)
    target = dd.get("target_contract_address", "")
    if not block or not target:
        log(f"[{name}] SKIP: no block/target")
        return

    mf2 = {"audit_id": name, "chain": "mainnet", "fork_block_number": block,
           "target_contract_address": target, "evm_version": "shanghai",
           "target_root": str(case_dir / "src")}
    mf_path = Path(f"/tmp/mf_poc_{base}.json")
    mf_path.write_text(json.dumps(mf2))

    log(f"[{name}] PoC: {len(findings)} findings...")
    rpc = get_rpc(name)
    subprocess.run([
        "python3", "scripts/audithound.py", "validate",
        "--manifest", str(mf_path), "--output-dir", str(out_dir),
        "--tool-provider", "deepseek", "--tool-model", "deepseek-v4-pro",
        "--max-attempts", "1", "--top-k", "99", "--min-profit", "0.001",
        "--rpc-url", rpc
    ], cwd="/root/audithound_new", stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=7200)

    subprocess.run([
        "python3", "scripts/save_results.py", str(out_dir), "/root/audithound_new/results"
    ], cwd="/root/audithound_new", stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    # Determine status with strict rules
    status = classify_case_strict(out_dir / "foundry_validation")
    log(f"[{name}] {status}")

if __name__ == "__main__":
    import sys

    if "--help" in sys.argv or "-h" in sys.argv:
        print("Usage: python3 poc_backfill_v3.py [case1 case2 ... | all] [--force] [--workers=N]")
        print()
        print("  case1 case2 ...   Run specific cases (without _regression suffix)")
        print("  all               Run all cases without summary (default)")
        print("  --force           Re-run even if summary.json already exists")
        print("  --workers=N       Parallel workers (default 4)")
        print()
        print("Examples:")
        print("  python3 poc_backfill_v3.py mimspell")
        print("  python3 poc_backfill_v3.py pickle conic dfx --force")
        print("  python3 poc_backfill_v3.py all --workers=2")
        sys.exit(0)

    # Parse args: case names (without _regression suffix) or "all" for full regression
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    force = "--force" in sys.argv  # re-run even if summary exists
    workers = 4
    for a in sys.argv[1:]:
        if a.startswith("--workers="):
            workers = int(a.split("=")[1])

    if args and args[0] != "all":
        # Run specific cases
        cases = []
        for name in args:
            case_name = name if name.endswith("_regression") else name + "_regression"
            ff = Path("/root/audithound_new/output") / case_name / "findings_acc.json"
            if not ff.exists():
                log(f"SKIP {name}: no findings_acc.json")
                continue
            try:
                cnt = len(json.loads(ff.read_text()))
            except:
                log(f"SKIP {name}: invalid findings_acc.json")
                continue
            if cnt == 0:
                log(f"SKIP {name}: 0 findings")
                continue
            sf = Path("/root/audithound_new/output") / case_name / "foundry_validation" / "summary.json"
            if sf.exists() and not force:
                log(f"SKIP {name}: already has summary (use --force to re-run)")
                continue
            cases.append(case_name)
        if not cases:
            log("No cases to run.")
            sys.exit(0)
    else:
        # Default: all cases without summary
        cases = []
        for d in sorted(Path("/root/audithound_new/output").iterdir()):
            if not d.name.endswith("_regression"):
                continue
            ff = d / "findings_acc.json"
            if not ff.exists():
                continue
            try:
                cnt = len(json.loads(ff.read_text()))
            except:
                continue
            if cnt == 0:
                continue
            if (d / "foundry_validation" / "summary.json").exists() and not force:
                continue
            cases.append(d.name)
        if not cases:
            log("All cases already have summaries. Use --force to re-run.")
            sys.exit(0)

    log(f"Backfill: {len(cases)} cases, {workers} workers")
    with ThreadPoolExecutor(max_workers=workers) as ex:
        list(ex.map(run_poc_for, cases))
    log("ALL DONE")
