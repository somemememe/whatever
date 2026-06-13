#!/usr/bin/env python3
"""Strict classification using forge logs for seed conversion detection."""
import json, re, sys
from pathlib import Path

WETH = "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2"
SENTINEL = 100_000 * 10**18
OUTPUT = Path("/root/audithound_new/output")

def parse_uint(text, key):
    m = re.search(rf"{key}:\s*(\d+)", text)
    return int(m.group(1)) if m else None

def classify_case(fv_dir):
    sf = fv_dir / "summary.json"
    if not sf.exists():
        return "NO_SUMMARY", []
    try:
        sd = json.loads(sf.read_text())
    except:
        return "ERROR", []

    has_pass = False
    has_blocked = False
    lines = []

    for r in sd.get("results", []):
        fid = r.get("id", "?")
        pw = r.get("profit_wei", 0) or 0
        pa = r.get("profit_any", 0) or 0
        pt = (r.get("profit_token", "") or "").strip().lower()
        passed = r.get("forge_test_passed", False)
        poc = r.get("poc_generated", False)
        bal_before = r.get("balance_before_wei")
        bal_after = r.get("balance_after_wei")

        # --- FAIL: PoC not generated ---
        if not poc:
            lines.append("  %s: FAIL (no PoC)" % fid)
            continue

        best = max(pw, pa)
        for sa in r.get("successful_attempts", []):
            best = max(best, sa.get("profit_score", 0) or 0)

        # --- Sentinel ---
        if best > SENTINEL:
            lines.append("  %s: BLOCKED sentinel %.0f ETH" % (fid, best/1e18))
            has_blocked = True
            continue

        # --- No profit ---
        if best <= 1e15:
            lines.append("  %s: BLOCKED no profit (best=%.6f ETH)" % (fid, best/1e18))
            has_blocked = True
            continue

        # --- Seed conversion: balance dropped, no native profit ---
        if pw == 0:
            if bal_before is not None and bal_after is not None and bal_after < bal_before:
                spent = bal_before - bal_after
                if spent > bal_before * 0.001:
                    if pa <= spent:
                        lines.append("  %s: BLOCKED seed-conv: spent %.4f ETH, got %.4f token" % (fid, spent/1e18, pa/1e18))
                        has_blocked = True
                        continue
                    lines.append("  %s: PASS token %.4f > spent %.4f ETH" % (fid, pa/1e18, spent/1e18))
                    has_pass = True
                    continue
            # Balance info missing + token profit in seed range → suspicious
            if bal_before is None or bal_after is None:
                if 0.1 * 10**18 <= pa <= 10.5 * 10**18:
                    lines.append("  %s: BLOCKED no-balance seed-range %.4f ETH" % (fid, pa/1e18))
                    has_blocked = True
                    continue

        # --- Non-WETH token: can't verify value ---
        if pt and pt != WETH and pt != "0x0000000000000000000000000000000000000000":
            lines.append("  %s: BLOCKED non-WETH %s... profit=%.4f raw" % (fid, pt[:10], pa/1e18))
            has_blocked = True
            continue

        # --- Real profit ---
        if pw > 1e15:
            lines.append("  %s: PASS native ETH %.4f" % (fid, pw/1e18))
        else:
            lines.append("  %s: PASS token profit %.4f ETH" % (fid, pa/1e18))
        has_pass = True

    if has_pass:
        return "PASS", lines
    if has_blocked:
        return "BLOCKED", lines
    return "FAIL", lines


if __name__ == "__main__":
    pass_cases = []
    blocked_cases = []
    fail_cases = []
    no_summary = []

    for d in sorted(OUTPUT.iterdir()):
        if not d.name.endswith("_regression"):
            continue
        fv = d / "foundry_validation"
        sf = fv / "summary.json"
        if not sf.exists():
            ff = d / "findings_acc.json"
            if ff.exists():
                try:
                    cnt = len(json.loads(ff.read_text()))
                    if cnt > 0:
                        no_summary.append(d.name.replace("_regression", ""))
                except:
                    pass
            continue

        case = d.name.replace("_regression", "")
        status, lines = classify_case(fv)
        if status == "PASS":
            pass_cases.append((case, lines))
        elif status == "BLOCKED":
            blocked_cases.append((case, lines))
        else:
            fail_cases.append((case, lines))

    total = len(pass_cases) + len(blocked_cases) + len(fail_cases)
    print("===== %d 个 case | PASS: %d | BLOCKED: %d | FAIL: %d | 未完成: %d =====" % (
        total, len(pass_cases), len(blocked_cases), len(fail_cases), len(no_summary)))
    print()

    print("=" * 60)
    print("  PASS (%d)" % len(pass_cases))
    print("=" * 60)
    for case, lines in pass_cases:
        print("[%s]" % case)
        for l in lines:
            print(l)

    print()
    print("=" * 60)
    print("  BLOCKED (%d)" % len(blocked_cases))
    print("=" * 60)
    for case, lines in blocked_cases:
        print("[%s]" % case)
        for l in lines:
            print(l)

    if fail_cases:
        print()
        print("=" * 60)
        print("  FAIL (%d)" % len(fail_cases))
        print("=" * 60)
        for case, lines in fail_cases:
            print("[%s]" % case)
            for l in lines:
                print(l)

    if no_summary:
        print()
        print("未完成 (%d): %s" % (len(no_summary), ", ".join(no_summary)))
