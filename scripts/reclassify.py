#!/usr/bin/env python3
"""Re-classify all completed summaries with strict rules.

PASS:  any finding has real profit (ETH gain + token value > seed cost)
BLOCKED: PoC ran but no real profit (sentinel, seed conversion, dust)
FAIL: nothing worked at all

Case-level rule: PASS if any finding is PASS, else BLOCKED if any PoC ran, else FAIL.
"""
import json
from pathlib import Path
from collections import defaultdict

SENTINEL_ETH = 100_000  # 100k ETH → sentinel
SEED_ETH = 10  # 10 ETH seed
DUST_ETH = 0.001  # 0.001 ETH → dust

OUTPUT = Path("/root/audithound_new/output")

def classify_finding(r):
    """Returns (status, reason, profit_eth) for a single finding."""
    pw = r.get("profit_wei", 0) or 0
    pa = r.get("profit_any", 0) or 0
    passed = r.get("forge_test_passed", False)
    poc = r.get("poc_generated", False)
    pf_token = r.get("profit_token", "") or ""

    # Best attempt score
    best_attempt = 0
    attempt_token = ""
    for sa in r.get("successful_attempts", []):
        score = sa.get("profit_score", 0) or 0
        if score > best_attempt:
            best_attempt = score
            attempt_token = sa.get("profit_token", "") or ""

    best = max(pw, pa, best_attempt)
    best_eth = best / 1e18

    # --- Sentinel ---
    if best_eth > SENTINEL_ETH:
        return "BLOCKED", f"哨兵值 {best_eth:,.0f} ETH", best_eth

    # --- Nothing worked ---
    if not passed and not poc:
        return "FAIL", "forge 测试未通过，无 PoC", 0

    # --- PoC didn't generate, even if test "passed" ---
    if not poc:
        return "BLOCKED", "测试通过但 PoC 未生成", 0

    # --- PoC generated but zero/negligible profit ---
    if best_eth <= DUST_ETH:
        return "BLOCKED", f"PoC 无利润 (best={best_eth:.6f} ETH)", best_eth

    # --- Has profit: validate it's real ---
    pw_eth = pw / 1e18
    pa_eth = pa / 1e18
    ba_eth = best_attempt / 1e18

    # If native ETH profit > dust → likely real
    if pw_eth > DUST_ETH:
        return "PASS", f"原生 ETH 利润 {pw_eth:.4f} ETH", pw_eth

    # Token-only profit: check for seed conversion
    # Seed conversion pattern: no native ETH, token profit ≈ 10 ETH
    if pw_eth <= DUST_ETH and pa_eth > DUST_ETH:
        # Within 15% of seed → suspicious
        if abs(pa_eth - SEED_ETH) / SEED_ETH < 0.15:
            return "BLOCKED", f"疑似种子套利: 代币利润 {pa_eth:.4f} ETH ≈ 种子 {SEED_ETH} ETH，无原生 ETH 收益", pa_eth
        # Significantly exceeds seed → likely real
        if pa_eth > SEED_ETH * 1.5:
            return "PASS", f"代币利润 {pa_eth:.2f} ETH 远超种子 {SEED_ETH} ETH", pa_eth
        # Below seed → BLOCKED
        if pa_eth < SEED_ETH * 0.85:
            return "BLOCKED", f"代币利润 {pa_eth:.4f} ETH 低于种子 {SEED_ETH} ETH", pa_eth
        # Edge case: close to seed but not within 15%
        return "BLOCKED", f"代币利润 {pa_eth:.4f} ETH 接近种子 {SEED_ETH} ETH，需人工判断", pa_eth

    # Attempt-based profit only
    if ba_eth > DUST_ETH and pw_eth <= DUST_ETH and pa_eth <= DUST_ETH:
        token_info = f" ({attempt_token[:10]}...)" if attempt_token else ""
        if abs(ba_eth - SEED_ETH) / SEED_ETH < 0.15:
            return "BLOCKED", f"疑似种子套利: attempt 利润 {ba_eth:.4f} ETH ≈ 种子{token_info}", ba_eth
        if ba_eth > SEED_ETH * 1.5:
            return "PASS", f"attempt 利润 {ba_eth:.2f} ETH 远超种子{token_info}", ba_eth
        return "BLOCKED", f"attempt 利润 {ba_eth:.4f} ETH 未超种子{token_info}", ba_eth

    return "BLOCKED", f"利润 {best_eth:.6f} ETH 不满足 PASS 条件", best_eth


def classify_case(results):
    """Case-level classification."""
    findings_status = []
    for r in results:
        status, reason, profit = classify_finding(r)
        findings_status.append((status, reason, profit))

    statuses = [s for s, _, _ in findings_status]

    if "PASS" in statuses:
        case_status = "PASS"
    elif "BLOCKED" in statuses:
        case_status = "BLOCKED"
    else:
        case_status = "FAIL"

    return case_status, findings_status


def main():
    summary_files = sorted(OUTPUT.glob("*_regression/foundry_validation/summary.json"))

    pass_list = []
    blocked_list = []
    fail_list = []

    for sf in summary_files:
        case = sf.parent.parent.name.replace("_regression", "")
        try:
            d = json.loads(sf.read_text())
        except Exception:
            continue

        results = d.get("results", [])
        if not results:
            fail_list.append((case, "无 results"))
            continue

        case_status, findings = classify_case(results)

        if case_status == "PASS":
            pass_list.append((case, findings))
        elif case_status == "BLOCKED":
            blocked_list.append((case, findings))
        else:
            fail_list.append((case, findings))

    # --- Print report ---
    print(f"{'='*70}")
    print(f"  严格分类结果：{len(summary_files)} 个 case")
    print(f"{'='*70}")
    print(f"  ✅ PASS:    {len(pass_list)}")
    print(f"  ⚠️  BLOCKED: {len(blocked_list)}")
    print(f"  ❌ FAIL:    {len(fail_list)}")
    print()

    print("=" * 70)
    print("  ✅ PASS")
    print("=" * 70)
    for case, findings in pass_list:
        print(f"\n  [{case}]")
        for status, reason, profit in findings:
            flag = "✅" if status == "PASS" else "⚠️" if status == "BLOCKED" else "❌"
            print(f"    {flag} [{status}] {reason}")

    print()
    print("=" * 70)
    print("  ⚠️  BLOCKED")
    print("=" * 70)
    for case, findings in blocked_list:
        print(f"\n  [{case}]")
        for status, reason, profit in findings:
            flag = "✅" if status == "PASS" else "⚠️" if status == "BLOCKED" else "❌"
            print(f"    {flag} [{status}] {reason}")

    print()
    print("=" * 70)
    print("  ❌ FAIL")
    print("=" * 70)
    for case, findings in fail_list:
        print(f"\n  [{case}]")
        if isinstance(findings, str):
            print(f"    ❌ {findings}")
        else:
            for status, reason, profit in findings:
                flag = "✅" if status == "PASS" else "⚠️" if status == "BLOCKED" else "❌"
                print(f"    {flag} [{status}] {reason}")


if __name__ == "__main__":
    main()
