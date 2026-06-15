#!/usr/bin/env python3
"""Compute optimal parameters for exchange rate manipulation exploit."""

# Current state
total_supply = 246421761575241
total_borrows = 1649830039724127194796
total_cash = 111641618554918888806782
total_reserves = 50130048441903129096319
exchange_rate = 256314214089629211269724685

# For exchange rate manipulation via direct transfer (F-002):
# Attacker mints, then donates, then redeems
# If attacker is 100% of supply, they break even
# If attacker is X% of supply, they lose (1-X)% of their donation

# For _addReserves locking (F-001/F-004):
# Attacker calls _addReserves(amount), funds go to reserves
# Only admin can withdraw via _reduceReserves

# Optimal direct transfer amount to manipulate exchange rate:
# To double exchange rate: need to add (totalCash + totalBorrows - totalReserves) more TUSD
current_numerator = total_cash + total_borrows - total_reserves
print(f"To double exchange rate: add {current_numerator / 1e18:.2f} TUSD directly")

# For F-005: underflow threshold  
print(f"\nUnderflow threshold:")
print(f"Reserves need to exceed: {total_cash + total_borrows} = {(total_cash + total_borrows) / 1e18:.2f} TUSD")
print(f"Current reserves: {total_reserves / 1e18:.2f} TUSD")
print(f"Additional reserves needed for underflow: {(total_cash + total_borrows - total_reserves) / 1e18:.2f} TUSD")
print(f"This can only happen via protocol seizes (2.8% per liquidation)")
print(f"Total liquidation volume needed: {(total_cash + total_borrows - total_reserves) / 0.028 / 1e18:.2f} TUSD")
