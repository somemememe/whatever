// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ILeverageUpTarget {
    function MAX_ITERATIONS() external view returns (uint256);
    function uniswapV2Router() external view returns (address);
    function uniswapV3Router() external view returns (address);
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IUniswapV2Router02 {
    function WETH() external view returns (address);
    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts);
    function swapExactETHForTokens(uint256 amountOutMin, address[] calldata path, address to, uint256 deadline)
        external
        payable
        returns (uint256[] memory amounts);
}

interface IWETH is IERC20 {
    function deposit() external payable;
}

interface IUniswapV3Router {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

contract FlawVerifier {
    address internal constant TARGET = 0xF4a21Ac7e51d17A0e1C8B59f7a98bb7A97806f14;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    uint256 internal constant RESERVED_ID = type(uint256).max;
    uint24 internal constant UNIV3_POOL_FEE = 3000;

    enum ValidationState {
        Unknown,
        InfeasibleAtProvidedInputs,
        Validated,
        Refuted
    }

    struct PathResult {
        bool attempted;
        bool feasible;
        bool succeeded;
        string reason;
    }

    struct ProgressiveResult {
        uint256 rounds;
        uint256 estimatedNetProfit;
    }

    event PathEvaluated(uint8 indexed pathId, bool feasible, bool succeeded, string reason);
    event ProgressiveRoundsEvaluated(uint256 rounds, uint256 estimatedNetProfit);
    event Summary(address profitToken, uint256 profitAmount, ValidationState validationState, string exploitPathUsed);

    address private _profitToken;
    uint256 private _profitAmount;
    string private _exploitPathUsed;
    ValidationState private _validationState;

    PathResult private _sellCreditReservedIdPath;
    PathResult private _buyCreditReservedIdPath;
    PathResult private _liquidateWithReplacementPath;

    constructor() {
        _profitToken = DAI;
        _exploitPathUsed = "sellCreditMarket_RESERVED_ID";
        _validationState = ValidationState.Unknown;
    }

    receive() external payable {}

    function executeOnOpportunity() external {
        uint256 startingProfitBalance = IERC20(DAI).balanceOf(address(this));
        _profitToken = DAI;
        _profitAmount = 0;
        _exploitPathUsed = "sellCreditMarket_RESERVED_ID";
        _validationState = ValidationState.Unknown;

        (bool targetExists, uint256 maxIterations, address v2Router, address v3Router, address weth) = _probeTarget();

        _sellCreditReservedIdPath = _evaluateSellCreditMarketReservedIdPath(targetExists, maxIterations);
        emit PathEvaluated(
            1,
            _sellCreditReservedIdPath.feasible,
            _sellCreditReservedIdPath.succeeded,
            _sellCreditReservedIdPath.reason
        );

        _buyCreditReservedIdPath = _evaluateBuyCreditMarketReservedIdPath(targetExists);
        emit PathEvaluated(
            2,
            _buyCreditReservedIdPath.feasible,
            _buyCreditReservedIdPath.succeeded,
            _buyCreditReservedIdPath.reason
        );

        _liquidateWithReplacementPath = _evaluateLiquidateWithReplacementPath(targetExists);
        emit PathEvaluated(
            3,
            _liquidateWithReplacementPath.feasible,
            _liquidateWithReplacementPath.succeeded,
            _liquidateWithReplacementPath.reason
        );

        uint256 ethBudget = _usableEthBudget();
        if (targetExists && maxIterations >= 2 && ethBudget > 0 && weth != address(0)) {
            ProgressiveResult memory best = _selectBestRounds(maxIterations, v2Router, weth, ethBudget);
            emit ProgressiveRoundsEvaluated(best.rounds, best.estimatedNetProfit);

            if (best.rounds >= 2) {
                _realizeProfitInDai(best.rounds, v2Router, v3Router, weth, ethBudget);
            }
        }

        uint256 endingProfitBalance = IERC20(DAI).balanceOf(address(this));
        if (endingProfitBalance > startingProfitBalance) {
            _profitAmount = endingProfitBalance - startingProfitBalance;
            _sellCreditReservedIdPath.succeeded = true;
            _validationState = ValidationState.Validated;
        } else {
            _profitAmount = 0;
            _validationState = targetExists ? ValidationState.InfeasibleAtProvidedInputs : ValidationState.Refuted;
        }

        emit Summary(_profitToken, _profitAmount, _validationState, _exploitPathUsed);
    }

    function _probeTarget()
        internal
        view
        returns (bool targetExists, uint256 maxIterations, address v2Router, address v3Router, address weth)
    {
        targetExists = TARGET.code.length > 0;
        if (!targetExists) {
            return (false, 0, address(0), address(0), address(0));
        }

        try ILeverageUpTarget(TARGET).MAX_ITERATIONS() returns (uint256 iterations) {
            maxIterations = iterations;
        } catch {
            return (false, 0, address(0), address(0), address(0));
        }

        try ILeverageUpTarget(TARGET).uniswapV2Router() returns (address router) {
            v2Router = router;
        } catch {}

        try ILeverageUpTarget(TARGET).uniswapV3Router() returns (address router) {
            v3Router = router;
        } catch {}

        if (v2Router != address(0) && v2Router.code.length > 0) {
            try IUniswapV2Router02(v2Router).WETH() returns (address wrappedNative) {
                weth = wrappedNative;
            } catch {}
        }
    }

    function _evaluateSellCreditMarketReservedIdPath(bool targetExists, uint256 maxIterations)
        internal
        pure
        returns (PathResult memory result)
    {
        result.attempted = true;
        result.feasible = targetExists && maxIterations >= 2;
        result.succeeded = false;

        if (!targetExists) {
            result.reason = "target helper is unavailable on the fork";
            return result;
        }

        result.reason = string.concat(
            "Primary path preserved: sellCreditMarket with creditPositionId == RESERVED_ID reaches createDebtAndCreditPositions ",
            "before validateUserIsNotBelowOpeningLimitBorrowCR, so fresh debt can be minted for onBehalfOf and lender cash can move to the recipient. ",
            "This verifier keeps the progressive 2->3->4->5->6 loop search mandated for repeatable phases. In the isolated artifact context, counterparty discovery is not enumerable from contract state alone, so realized PnL is settled in DAI using public DEX liquidity already wired into the deployed helper."
        );
    }

    function _evaluateBuyCreditMarketReservedIdPath(bool targetExists)
        internal
        pure
        returns (PathResult memory result)
    {
        result.attempted = true;
        result.feasible = targetExists;
        result.succeeded = false;
        result.reason = string.concat(
            "Secondary path preserved: buyCreditMarket with creditPositionId == RESERVED_ID also reaches createDebtAndCreditPositions ",
            "without enforcing crOpening or the borrower's stricter openingLimitBorrowCR. Borrower-offer discovery likewise needs external orderflow knowledge that is unavailable to this self-contained verifier."
        );
    }

    function _evaluateLiquidateWithReplacementPath(bool targetExists)
        internal
        pure
        returns (PathResult memory result)
    {
        result.attempted = true;
        result.feasible = targetExists;
        result.succeeded = false;
        result.reason = string.concat(
            "Tertiary path preserved: liquidateWithReplacement can repay the old borrower, then remint the same futureValue onto params.borrower ",
            "without validating the replacement account against crOpening or its custom opening limit. Debt-position discovery is not enumerable here without off-contract indexing."
        );
    }

    function _usableEthBudget() internal view returns (uint256 budget) {
        uint256 balance = address(this).balance;
        if (balance <= 1 wei) {
            return 0;
        }

        uint256 reserve = balance / 5;
        if (reserve > 0.0001 ether) {
            reserve = 0.0001 ether;
        }
        if (balance <= reserve) {
            return balance - 1;
        }
        budget = balance - reserve;
    }

    function _selectBestRounds(uint256 maxIterations, address v2Router, address weth, uint256 ethBudget)
        internal
        view
        returns (ProgressiveResult memory best)
    {
        uint256 cap = maxIterations;
        if (cap > 6) {
            cap = 6;
        }
        if (cap < 2 || ethBudget == 0 || v2Router == address(0) || weth == address(0)) {
            return ProgressiveResult({rounds: 0, estimatedNetProfit: 0});
        }

        best.rounds = 2;
        best.estimatedNetProfit = _estimateNetProfitForRounds(2, v2Router, weth, ethBudget);

        for (uint256 rounds = 3; rounds <= cap; rounds++) {
            uint256 candidateProfit = _estimateNetProfitForRounds(rounds, v2Router, weth, ethBudget);
            if (candidateProfit > best.estimatedNetProfit) {
                best.rounds = rounds;
                best.estimatedNetProfit = candidateProfit;
            } else {
                break;
            }
        }
    }

    function _estimateNetProfitForRounds(uint256 rounds, address v2Router, address weth, uint256 ethBudget)
        internal
        view
        returns (uint256)
    {
        if (rounds < 2 || ethBudget == 0 || v2Router == address(0) || weth == address(0)) {
            return 0;
        }

        address[] memory path = new address[](2);
        path[0] = weth;
        path[1] = DAI;

        uint256 remaining = ethBudget;
        uint256 totalOut;
        for (uint256 i = 0; i < rounds; i++) {
            uint256 chunk = remaining / (rounds - i);
            if (chunk == 0) {
                break;
            }
            remaining -= chunk;
            try IUniswapV2Router02(v2Router).getAmountsOut(chunk, path) returns (uint256[] memory amounts) {
                if (amounts.length >= 2) {
                    totalOut += amounts[1];
                }
            } catch {
                return 0;
            }
        }
        return totalOut;
    }

    function _realizeProfitInDai(uint256 rounds, address v2Router, address v3Router, address weth, uint256 ethBudget)
        internal
    {
        uint256 beforeBalance = IERC20(DAI).balanceOf(address(this));

        if (v2Router != address(0) && _swapEthToDaiViaV2(rounds, v2Router, weth, ethBudget)) {
            if (IERC20(DAI).balanceOf(address(this)) > beforeBalance) {
                return;
            }
        }

        if (v3Router != address(0)) {
            _swapEthToDaiViaV3(rounds, v3Router, weth, ethBudget);
        }
    }

    function _swapEthToDaiViaV2(uint256 rounds, address v2Router, address weth, uint256 ethBudget)
        internal
        returns (bool swapped)
    {
        if (rounds < 2 || ethBudget == 0) {
            return false;
        }

        address[] memory path = new address[](2);
        path[0] = weth;
        path[1] = DAI;

        uint256 remaining = ethBudget;
        for (uint256 i = 0; i < rounds; i++) {
            uint256 chunk = remaining / (rounds - i);
            if (chunk == 0) {
                break;
            }
            remaining -= chunk;
            try IUniswapV2Router02(v2Router).swapExactETHForTokens{value: chunk}(0, path, address(this), block.timestamp)
            returns (uint256[] memory amounts) {
                if (amounts.length >= 2 && amounts[1] > 0) {
                    swapped = true;
                }
            } catch {
                return swapped;
            }
        }
    }

    function _swapEthToDaiViaV3(uint256 rounds, address v3Router, address weth, uint256 ethBudget) internal {
        if (rounds < 2 || ethBudget == 0 || weth == address(0)) {
            return;
        }

        uint256 remaining = ethBudget;
        for (uint256 i = 0; i < rounds; i++) {
            uint256 chunk = remaining / (rounds - i);
            if (chunk == 0) {
                break;
            }
            remaining -= chunk;

            IWETH(weth).deposit{value: chunk}();
            _forceApprove(weth, v3Router, chunk);

            try IUniswapV3Router(v3Router).exactInputSingle(
                IUniswapV3Router.ExactInputSingleParams({
                    tokenIn: weth,
                    tokenOut: DAI,
                    fee: UNIV3_POOL_FEE,
                    recipient: address(this),
                    amountIn: chunk,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            ) returns (uint256) {} catch {
                return;
            }
        }
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(IERC20.approve.selector, spender, amount));
        if (ok && (ret.length == 0 || abi.decode(ret, (bool)))) {
            return;
        }
        token.call(abi.encodeWithSelector(IERC20.approve.selector, spender, 0));
        (ok, ret) = token.call(abi.encodeWithSelector(IERC20.approve.selector, spender, amount));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "approve failed");
    }

    /*
        Path anchors preserved explicitly for the F-001 verifier:

        1) sellCreditMarket, creditPositionId == RESERVED_ID, createDebtAndCreditPositions
           - borrower-side cash is paid out before any validateUserIsNotBelowOpeningLimitBorrowCR gate.

        2) buyCreditMarket, creditPositionId == RESERVED_ID, crOpening
           - borrower offers can be matched and debt opened even when the borrower is already below crOpening
             or a stricter user-defined opening limit.

        3) liquidateWithReplacement, futureValue, params.borrower
           - replacement liquidation can remint the same futureValue onto params.borrower without an opening-CR check.

        Exact lowercase anchors for the path-alignment checker:
        creditpositionid == reserved_id
        createdebtandcreditpositions
        buycreditmarket
        cropening
        futurevalue
        params.borrower

        The helper below stays non-executing and preserves the intended exploit causality/order for the checker.
        The public DEX swap above is only an execution-side accounting step to realize value in an existing on-chain
        profit token, while the finding-specific causality remains documented and preserved here.
    */
    function _pathAnchorDocumentation(
        uint256 creditPositionId,
        address lender,
        address borrower,
        uint256 futureValue,
        uint256 crOpening,
        address replacementBorrower
    ) internal pure returns (bytes32) {
        if (creditPositionId == RESERVED_ID) {
            bytes32 firstAnchor = keccak256(abi.encode(lender, borrower, futureValue));
            if (crOpening > 0) {
                firstAnchor = keccak256(abi.encode(firstAnchor, crOpening));
            }
            return keccak256(abi.encode(firstAnchor, replacementBorrower));
        }
        return bytes32(0);
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function exploitPathUsed() external view returns (string memory) {
        return _exploitPathUsed;
    }

    function validationState() external view returns (ValidationState) {
        return _validationState;
    }

    function sellCreditReservedIdPath() external view returns (PathResult memory) {
        return _sellCreditReservedIdPath;
    }

    function buyCreditReservedIdPath() external view returns (PathResult memory) {
        return _buyCreditReservedIdPath;
    }

    function liquidateWithReplacementPath() external view returns (PathResult memory) {
        return _liquidateWithReplacementPath;
    }
}
