#!/usr/bin/env python3
"""Detailed analysis of 5 new cases — unified ETH value comparison."""
import json, urllib.request, time, re
from pathlib import Path

OUTPUT = Path("/root/audithound_new/output")
WETH = "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2"
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
    except:
        pass
    return None

def token_profit_in_eth(addr, raw_amount):
    if not addr or addr == "0x0000000000000000000000000000000000000000":
        return None
    if addr.lower() == WETH:
        return raw_amount / 1e18
    p = token_eth_price(addr)
    return (raw_amount / 1e18) * p if p else None

def get_symbol(addr):
    try:
        from web3 import Web3
        w3 = Web3(Web3.HTTPProvider("https://mainnet.infura.io/v3/e256143b4bb44b44a98e9b22b0290400"))
        abi = [{"constant":True,"inputs":[],"name":"symbol","outputs":[{"name":"","type":"string"}],"type":"function"}]
        contract = w3.eth.contract(address=Web3.to_checksum_address(addr), abi=abi)
        return contract.functions.symbol().call()
    except:
        return "?"

for case in ["conic", "pickle", "dfx", "blueberryprotocol", "mimspell"]:
    print("#" * 70)
    print("#  %s" % case)
    print("#" * 70)

    base = OUTPUT / (case + "_regression")
    ff = base / "findings_acc.json"
    findings = json.loads(ff.read_text()) if ff.exists() else []
    sf = base / "foundry_validation" / "summary.json"
    sd = json.loads(sf.read_text()) if sf.exists() else {"results": []}

    has_case_pass = False
    has_case_blocked = False

    for i, r in enumerate(sd.get("results", [])):
        fid = r.get("id", "?")
        title = ""
        for f in findings:
            if f.get("id") == fid:
                title = f.get("title", "")
                break

        pw = r.get("profit_wei", 0) or 0
        pa = r.get("profit_any", 0) or 0
        pt = (r.get("profit_token", "") or "").strip().lower()
        passed = r.get("forge_test_passed", False)
        poc = r.get("poc_generated", False)
        bb = r.get("balance_before_wei")
        ba = r.get("balance_after_wei")
        err = r.get("last_error_excerpt", "")

        # Get actual token (summary first, then attempt)
        actual_token = pt
        attempt_tokens = []
        for sa in r.get("successful_attempts", []):
            at = (sa.get("profit_token", "") or "").strip().lower()
            if at:
                attempt_tokens.append(at)
        if (not actual_token or actual_token == "0x0000000000000000000000000000000000000000") and attempt_tokens:
            actual_token = attempt_tokens[0]

        print()
        print("  [%s] %s" % (fid, title[:90]))
        print("  " + "-" * 60)

        if not poc:
            print("  PoC: NOT GENERATED -> FAIL")
            if err:
                print("  Error: %s" % err[:200].replace("\n", " "))
            continue

        print("  PoC: generated  |  Forge: %s" % ("PASSED" if passed else "FAILED"))

        # ---- Unified ETH value calculation ----
        profit_eth = pw / 1e18  # native ETH

        token_eth = None
        token_symbol = ""
        if pa > 1e15 and actual_token and actual_token != "0x0000000000000000000000000000000000000000":
            token_eth = token_profit_in_eth(actual_token, pa)
            token_symbol = get_symbol(actual_token) if actual_token != WETH else "WETH"

        total_eth = profit_eth + (token_eth if token_eth is not None else 0)

        spent_eth = None
        if bb is not None and ba is not None and ba < bb:
            spent_eth = (bb - ba) / 1e18

        # ---- Display ----
        if bb is not None and ba is not None:
            delta = (ba - bb) / 1e18
            print("  ETH balance: %.4f -> %.4f (%+.4f)" % (bb / 1e18, ba / 1e18, delta))
        else:
            print("  ETH balance: (not recorded)")

        print("  Native ETH profit: %.6f ETH" % profit_eth)

        if pa > 1e15:
            print("  Token profit: %.6f raw units" % (pa / 1e18))
            if actual_token and actual_token != "0x0000000000000000000000000000000000000000":
                print("  Token address: %s... (%s)" % (actual_token[:16], token_symbol))
            if token_eth is not None:
                print("  Token value: %.6f ETH" % token_eth)
            else:
                print("  Token value: UNAVAILABLE (no price data)")

        if spent_eth is not None:
            print("  Seed spent: %.4f ETH" % spent_eth)

        print("  Total profit (ETH): %.6f" % total_eth)

        # ---- Verdict ----
        SENTINEL = 100_000
        if total_eth > SENTINEL:
            verdict = "BLOCKED (sentinel)"
        elif total_eth <= 0.001:
            if token_eth is None and pa > 1e15:
                verdict = "BLOCKED (unknown token, no price, no native ETH)"
            else:
                verdict = "BLOCKED (total %.6f ETH <= 0.001)" % total_eth
        elif profit_eth > 0.001:
            verdict = "PASS (native ETH %.4f)" % profit_eth
        elif token_eth is not None:
            if spent_eth is not None:
                if token_eth > spent_eth:
                    verdict = "PASS (token %.4f ETH > spent %.4f ETH)" % (token_eth, spent_eth)
                else:
                    verdict = "BLOCKED (token %.4f ETH <= spent %.4f ETH)" % (token_eth, spent_eth)
            else:
                if 0.1 <= token_eth <= 10.5:
                    verdict = "BLOCKED (token %.4f ETH, no balance, seed-range)" % token_eth
                else:
                    verdict = "PASS (token %.4f ETH, no balance)" % token_eth
        else:
            verdict = "BLOCKED (no price for token %.4f units)" % (pa / 1e18)

        print("  >>> %s" % verdict)

        if "PASS" in verdict:
            has_case_pass = True
        elif "BLOCKED" in verdict:
            has_case_blocked = True

    print()
    if has_case_pass:
        print("  CASE: PASS")
    elif has_case_blocked:
        print("  CASE: BLOCKED")
    else:
        print("  CASE: FAIL")
    print()
