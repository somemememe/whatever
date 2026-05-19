You are fixing a failing Foundry PoC for finding F-003.

Goal:
- Keep the exploit objective for this finding.
- Fix compile/runtime/test failure from logs.
- Return COMPLETE updated Solidity for `src/FlawVerifier.sol` only.
- Keep exploit logic aligned with the full `Exploit paths` list unless logs prove a stage is infeasible.

Finding:
- title: The OTC blindly binds to a hardcoded HEX address, so a wrong-chain deployment can settle against attacker-controlled token code
- claim: The constructor unconditionally sets `hexInterface = ERC20(hexAddress)` for a single hardcoded address and never verifies chain context, code presence, or code identity. Every escrow and settlement path then trusts `balanceOf`, `transferFrom`, and `transfer` results from that address. If this contract is deployed on any chain where `0x2b591e99afE9f32eAA6214f7B7629768c40Eeb39` is not the canonical HEX token, a malicious contract at that address can forge balances and successful transfers while moving no real value.
- impact: A wrong-chain or misconfigured deployment can become fully compromiseable: attackers can drain ETH-backed offers by making `buyETH()` believe HEX was paid, and can sell nonexistent or undercollateralized "HEX" offers for real ETH because offer creation, settlement, and cancellation all trust the hardcoded token contract's return values. This is deployment-context dependent, but it creates realistic total loss if the bytecode at the fixed address is not the expected HEX implementation.
- exploit_paths: ["Deploy `HEXOTC` on a network where `0x2b591e99afE9f32eAA6214f7B7629768c40Eeb39` is attacker-controlled -> fake `balanceOf` and `transferFrom` let the attacker call `buyETH(id)` and receive escrowed ETH without paying real HEX", "Same deployment context -> fake `transferFrom` during `offerHEX()` records a HEX-backed order without real token escrow -> a buyer later calls `buyHEX(id)` and pays real ETH for nonexistent HEX", "Same deployment context -> fake `transfer` responses in `buyHEX()` or `cancel()` can report success without moving tokens, breaking refunds and settlement accounting"]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IHEXOTC {
    function last_offer_id() external view returns (uint256);
    function offers(uint256 id)
        external
        view
        returns (
            uint256 payAmt,
            uint256 buyAmt,
            address owner,
            uint64 timestamp,
            bytes32 offerId,
            uint256 escrowType
        );
}

contract FlawVerifier {
    address public constant TARGET = 0x204B937FEaEc333E9e6d72D35f1D131f187ECeA1;
    address public constant HEX = 0x2b591e99afE9f32eAA6214f7B7629768c40Eeb39;
    uint256 public constant EXPECTED_CHAIN_ID = 1;

    bool public executed;
    bool public hypothesisValidated;
    bool public hypothesisRefuted;

    uint256 public observedChainId;
    uint256 public observedLastOfferId;
    bytes32 public targetCodeHash;
    bytes32 public hexCodeHash;

    uint256 public ethBackedOffersObserved;
    uint256 public hexBackedOffersObserved;

    uint256 public exploitPathMask;
    uint256 private constant PATH_DRAIN_ETH_WITH_FAKE_HEX = 1 << 0;
    uint256 private constant PATH_CREATE_FAKE_HEX_ORDER = 1 << 1;
    uint256 private constant PATH_FAKE_REFUND_OR_SETTLEMENT = 1 << 2;

    address public profitToken;
    uint256 public profitAmount;

    constructor() {}

    receive() external payable {}

    function execute() external returns (uint256) {
        return _execute();
    }

    function run() external returns (uint256) {
        return _execute();
    }

    function exploit() external returns (uint256) {
        return _execute();
    }

    function _execute() internal returns (uint256) {
        if (executed) {
            return profitAmount;
        }

        executed = true;
        observedChainId = block.chainid;
        observedLastOfferId = IHEXOTC(TARGET).last_offer_id();
        targetCodeHash = _codeHash(TARGET);
        hexCodeHash = _codeHash(HEX);

        _observeRecentOffers();

        // Exploit path 1 requires the OTC to be deployed on a chain where the
        // hardcoded HEX address is attacker-controlled. On this task's fork the
        // target is already deployed on mainnet (chain id 1), so the wrong-chain
        // precondition is not met and buyETH() cannot be tricked with fake HEX.
        if (_wrongChainHexPreconditionHolds()) {
            exploitPathMask |= PATH_DRAIN_ETH_WITH_FAKE_HEX;
        }

        // Exploit path 2 requires offerHEX() to interact with attacker-supplied
        // token code at the fixed HEX address. That same wrong-chain precondition
        // is false here, so fake HEX escrow cannot be created on this deployment.
        if (_wrongChainHexPreconditionHolds()) {
            exploitPathMask |= PATH_CREATE_FAKE_HEX_ORDER;
        }

        // Exploit path 3 depends on forged transfer()/transferFrom() success from
        // attacker-controlled code at the hardcoded address. Because this fork is
        // the mainnet deployment context, that settlement/refund forgery stage is
        // likewise unavailable.
        if (_wrongChainHexPreconditionHolds()) {
            exploitPathMask |= PATH_FAKE_REFUND_OR_SETTLEMENT;
        }

        hypothesisValidated = exploitPathMask != 0;
        hypothesisRefuted = exploitPathMask == 0;
        profitToken = address(0);
        profitAmount = 0;
        return profitAmount;
    }

    function _wrongChainHexPreconditionHolds() internal view returns (bool) {
        if (block.chainid != EXPECTED_CHAIN_ID) {
            return true;
        }
        if (HEX.code.length == 0) {
            return true;
        }
        return false;
    }

    function _observeRecentOffers() internal {
        uint256 lastId = observedLastOfferId;
        uint256 start = lastId > 24 ? lastId - 24 : 1;

        for (uint256 id = start; id <= lastId; ++id) {
            (uint256 payAmt, uint256 buyAmt, , uint64 timestamp, , uint256 escrowType) = IHEXOTC(TARGET).offers(id);
            if (timestamp == 0 || payAmt == 0 || buyAmt == 0) {
                continue;
            }
            if (escrowType == 1) {
                ++ethBackedOffersObserved;
            } else if (escrowType == 0) {
                ++hexBackedOffersObserved;
            }
        }
    }

    function _codeHash(address account) internal view returns (bytes32 hash) {
        assembly {
            hash := extcodehash(account)
        }
    }
}

```

forge stdout (tail):
```
Compiling 2 files with Solc 0.8.30
Solc 0.8.30 finished in 67.93ms

```

forge stderr (tail):
```
Error: Compiler run failed:
Error: Compiler error (/solidity/libsolidity/codegen/LValue.cpp:54): Stack too deep. Try compiling with `--via-ir` (cli) or the equivalent `viaIR: true` (standard JSON) while enabling the optimizer. Otherwise, try removing local variables.
   --> test/ExploitPOC.t.sol:101:62:
    |
101 |         emit log_named_uint("AUDITHOUND_BALANCE_BEFORE_WEI", beforeBal);
    |                                                              ^^^^^^^^^

```

Requirements:
1. pragma ^0.8.20
2. include at least one deployable contract with zero-arg constructor
3. include at least one callable no-arg external/public exploit entry function
4. no imports
5. keep exploit logic aligned to exploit_paths (same core actions and ordering intent)
6. expose `profitToken()` and `profitAmount()` getters for net realized profit
7. output ONLY Solidity code
