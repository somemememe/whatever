#!/usr/bin/env python3
"""Complete classification of all 60 cases with token price lookup."""
import json, urllib.request, time
from pathlib import Path

OUTPUT = Path("/root/audithound_new/output")
WETH = "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2"
SENTINEL = 100_000 * 10**18
_PRICE_CACHE = {}

def token_eth_price(addr):
    addr = addr.lower()
    now = time.time()
    if addr in _PRICE_CACHE:
        price, ts = _PRICE_CACHE[addr]
        if now - ts < 3600:
            return price
    try:
        url = "https://api.coingecko.com/api/v3/simple/token_price/ethereum?contract_addresses=%s&vs_currencies=eth" % addr
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        resp = json.loads(urllib.request.urlopen(req, timeout=10).read())
        price = resp.get(addr, {}).get("eth")
        if price is not None:
            _PRICE_CACHE[addr] = (float(price), now)
            return float(price)
    except Exception:
        pass
    return None

def token_profit_in_eth(addr, raw_amount):
    if not addr or addr == "0x0000000000000000000000000000000000000000":
        return None
    if addr.lower() == WETH:
        return raw_amount / 1e18
    price = token_eth_price(addr)
    if price is None:
        return None
    return (raw_amount / 1e18) * price

# Original audit ground truth
ORIG_PASS = {"game","apemaga","gradient_maker_pool","hegic_options","aave_boost",
             "floordao","uni","sushi_router","nowswap","doughfina","upswing","akutarnft","nimbus"}
ORIG_FAIL = {"audius","compoundtusd","compounduni","earningfram","rubic","seneca","uniclynft"}

# Get ALL summaries sorted by timestamp
all_summaries = []
for d in OUTPUT.iterdir():
    if not d.name.endswith("_regression"):
        continue
    sf = d / "foundry_validation" / "summary.json"
    if sf.exists():
        all_summaries.append((sf.stat().st_mtime, d.name.replace("_regression","")))
all_summaries.sort()

orig_36 = [c for _, c in all_summaries[:36]]
new_summary_cases = [c for _, c in all_summaries[36:]]
orig_blocked_list = [c for c in orig_36 if c not in ORIG_PASS and c not in ORIG_FAIL]
ORIG_BLOCKED = set(orig_blocked_list)

# No-summary backfill results (verified from forge logs)
no_summary_results = {
    "bzx": "FAIL",
    "cover": "BLOCKED",
    "indexedfinance": "BLOCKED",
    "ktaf": "BLOCKED",
    "mono": "FAIL",
    "paraspace": "FAIL",
    "bmizapper": "FAIL",
    "shoco": "FAIL",
    "teamfinance": "FAIL",
    "usual_money": "FAIL",
    "uwerx": "FAIL",
    "xavefinance": "FAIL",
    "xbridge": "FAIL",
    "yearnfinance": "FAIL",
}

# Strict classify function
def strict_classify(case):
    sf = OUTPUT / (case + "_regression") / "foundry_validation" / "summary.json"
    sd = json.loads(sf.read_text())
    has_pass = False
    has_blocked = False
    for r in sd.get("results", []):
        pw = r.get("profit_wei", 0) or 0
        pa = r.get("profit_any", 0) or 0
        pt = (r.get("profit_token", "") or "").strip().lower()
        poc = r.get("poc_generated", False)
        bb = r.get("balance_before_wei")
        ba = r.get("balance_after_wei")

        if not poc:
            continue

        best = max(pw, pa)
        for sa in r.get("successful_attempts", []):
            best = max(best, sa.get("profit_score", 0) or 0)

        # Sentinel
        if best > SENTINEL:
            has_blocked = True
            continue

        # No profit
        if best <= 1e15:
            has_blocked = True
            continue

        # Seed conversion / token value check
        if pw == 0:
            if bb is not None and ba is not None and ba < bb:
                spent = bb - ba
                if spent > bb * 0.001:
                    if pa <= spent:
                        # Check if token value changes picture
                        if pt and pt != WETH and pt != "0x0000000000000000000000000000000000000000":
                            eth_val = token_profit_in_eth(pt, pa)
                            if eth_val is not None and eth_val > spent / 1e18:
                                has_pass = True
                                continue
                        has_blocked = True
                        continue
                    has_pass = True
                    continue
            elif bb is None or ba is None:
                if pt and pt != WETH and pt != "0x0000000000000000000000000000000000000000":
                    eth_val = token_profit_in_eth(pt, pa)
                    if eth_val is not None:
                        if eth_val <= 0.001:
                            has_blocked = True
                        else:
                            has_pass = True
                    else:
                        has_blocked = True
                    continue
                if 0.1 * 10**18 <= pa <= 10.5 * 10**18:
                    has_blocked = True
                    continue

        # Non-WETH token value check
        if pt and pt != WETH and pt != "0x0000000000000000000000000000000000000000":
            eth_val = token_profit_in_eth(pt, pa)
            if eth_val is None:
                has_blocked = True
                continue
            if eth_val <= 0.001:
                has_blocked = True
                continue
            has_pass = True
            continue

        has_pass = True

    if has_pass:
        return "PASS"
    if has_blocked:
        return "BLOCKED"
    return "FAIL"


# Classify new summary cases
new_results = {}
for case in new_summary_cases:
    new_results[case] = strict_classify(case)

# Also classify mimspell (it's in orig_36 but let's check with price)
mimspell_result = strict_classify("mimspell") if "mimspell" not in orig_36 else None

# Count running and 0-findings
all_classified = set(ORIG_PASS) | ORIG_FAIL | ORIG_BLOCKED | set(new_summary_cases) | set(no_summary_results.keys())
running = []
zero = []
for d in sorted(OUTPUT.iterdir()):
    if not d.name.endswith("_regression"):
        continue
    case = d.name.replace("_regression", "")
    if case in all_classified:
        continue
    sf = d / "foundry_validation" / "summary.json"
    if sf.exists():
        continue
    ff = d / "findings_acc.json"
    if ff.exists():
        try:
            cnt = len(json.loads(ff.read_text()))
        except Exception:
            cnt = 0
        if cnt == 0:
            zero.append(case)
        else:
            running.append(case)
    else:
        running.append(case)

# Print
n_pass = len(ORIG_PASS) + sum(1 for v in new_results.values() if v == "PASS")
n_blocked = len(ORIG_BLOCKED) + sum(1 for v in new_results.values() if v == "BLOCKED")
n_fail = len(ORIG_FAIL) + sum(1 for v in new_results.values() if v == "FAIL")

print("=" * 60)
print("  PASS:    %d  (original %d + new %d)" % (n_pass, len(ORIG_PASS), sum(1 for v in new_results.values() if v == "PASS")))
print("  Original:", ", ".join(sorted(ORIG_PASS)))
for c, v in sorted(new_results.items()):
    if v == "PASS":
        print("  New: %s" % c)

print()
print("  BLOCKED: %d  (original %d + new %d)" % (n_blocked, len(ORIG_BLOCKED), sum(1 for v in new_results.values() if v == "BLOCKED")))
print("  Original:", ", ".join(sorted(ORIG_BLOCKED)))
for c, v in sorted(new_results.items()):
    if v == "BLOCKED":
        print("  New: %s" % c)

print()
print("  FAIL:    %d  (original %d + new %d)" % (n_fail, len(ORIG_FAIL), sum(1 for v in new_results.values() if v == "FAIL")))
print("  Original:", ", ".join(sorted(ORIG_FAIL)))
for c, v in sorted(new_results.items()):
    if v == "FAIL":
        print("  New: %s" % c)

print()
print("  [No-summary backfill results]")
for c, r in sorted(no_summary_results.items()):
    print("    %s: %s" % (c, r))

print()
print("  Running: %d" % len(running))
if running:
    print("  ", ", ".join(running))
print()
print("  0 findings: %d" % len(zero))
if zero:
    print("  ", ", ".join(zero))

print()
total = n_pass + n_blocked + n_fail + len(running) + len(zero)
print("  Total: %d" % total)
