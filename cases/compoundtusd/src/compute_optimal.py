#!/usr/bin/env python3
"""Compute optimal exploit parameters for cTUSD findings."""

# From on-chain data:
total_supply = 246421761575241  # cToken (8 decimals)
total_borrows = 1649830039724127194796  # TUSD (18 decimals)
total_cash = 111641618554918888806782  # TUSD (18 decimals)
# totalReserves from storage slot 12 = 0xa9d8e2cd187f848f07f
total_reserves_hex = "0xa9d8e2cd187f848f07f"
total_reserves = int(total_reserves_hex, 16)

exchange_rate_stored = 256314214089629211269724685  # scaled by 1e18

print("=== Current State ===")
print(f"totalSupply (cToken): {total_supply} ({total_supply / 1e8:.2f} cTUSD)")
print(f"totalBorrows (TUSD): {total_borrows} ({total_borrows / 1e18:.2f} TUSD)")
print(f"totalCash (TUSD): {total_cash} ({total_cash / 1e18:.2f} TUSD)")
print(f"totalReserves (TUSD): {total_reserves} ({total_reserves / 1e18:.2f} TUSD)")
print(f"exchangeRate: {exchange_rate_stored} ({exchange_rate_stored / 1e18:.6f} TUSD/cTUSD)")

# Exchange rate formula:
# exchangeRate = (totalCash + totalBorrows - totalReserves) * 1e18 / totalSupply
cash_plus_borrows_minus_reserves = total_cash + total_borrows - total_reserves
print(f"\ncash + borrows - reserves: {cash_plus_borrows_minus_reserves} ({cash_plus_borrows_minus_reserves / 1e18:.2f} TUSD)")

# How much _addReserves would it take to make totalReserves > totalCash + totalBorrows?
# Currently: totalCash + totalBorrows = {total_cash + total_borrows}
current_sum = total_cash + total_borrows
print(f"\n=== Underflow Analysis ===")
print(f"totalCash + totalBorrows = {current_sum} ({current_sum / 1e18:.2f} TUSD)")
print(f"totalReserves = {total_reserves} ({total_reserves / 1e18:.2f} TUSD)")
print(f"Difference: {(current_sum - total_reserves) / 1e18:.2f} TUSD")

# To cause underflow: totalReserves > totalCash + totalBorrows
# Currently difference is positive, so no underflow risk
# But _addReserves increases both totalCash and totalReserves equally, so it can't cause underflow
# Protocol seizes increase totalReserves without increasing totalCash or totalBorrows
# Each seize: protocolSeizeAmount = seizeTokens * exchangeRate * 0.028

print("\n=== For _addReserves to lock funds ===")
print("_addReserves has no access control - anyone can call it")
print("Funds added via _addReserves can only be withdrawn by admin via _reduceReserves")
print("This is a known finding (F-001, F-004)")

print("\n=== Direct transfer exchange rate manipulation ===")
print("Anyone can send TUSD directly to cToken to increase exchange rate")
print("This benefits all cToken holders proportionally")
print("Known finding (F-002)")

print("\n=== TUSD destroyBlackFunds risk ===")
print(f"cToken holds {total_cash / 1e18:.2f} TUSD")
print("TUSD owner can blacklist cToken and call destroyBlackFunds to zero out balance")
print("This would destroy all deposits")
