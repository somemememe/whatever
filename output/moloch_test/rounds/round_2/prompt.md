You are auditing the smart contracts in majeur/src.

## Contracts in Scope

# Scope

- Moloch.sol:Moloch (2110 LOC) — TODO
- Moloch.sol:Shares (2110 LOC) — TODO
- Moloch.sol:Loot (2110 LOC) — TODO
- Moloch.sol:Badges (2110 LOC) — TODO
- Moloch.sol:IMajeurRenderer (2110 LOC) — TODO
- Moloch.sol:Summoner (2110 LOC) — TODO
- Renderer.sol:IMajeurRenderer (891 LOC) — TODO
- Renderer.sol:IMoloch (891 LOC) — TODO
- Renderer.sol:Renderer (891 LOC) — TODO
- Renderer.sol:for (891 LOC) — TODO
- Renderer.sol:Display (891 LOC) — TODO
- peripheral/BondingCurveSale.sol:for (379 LOC) — TODO
- peripheral/BondingCurveSale.sol:BondingCurveSale (379 LOC) — TODO
- peripheral/BondingCurveSale.sol:IMoloch (379 LOC) — TODO
- peripheral/ClassicalCurveSale.sol:as (1637 LOC) — TODO
- peripheral/ClassicalCurveSale.sol:acts (1637 LOC) — TODO
- peripheral/ClassicalCurveSale.sol:ClassicalCurveSale (1637 LOC) — TODO
- peripheral/ClassicalCurveSale.sol:URI (1637 LOC) — TODO
- peripheral/ClassicalCurveSale.sol:ERC20 (1637 LOC) — TODO
- peripheral/ClassicalCurveSale.sol:before (1637 LOC) — TODO
- peripheral/ClassicalCurveSale.sol:for (1637 LOC) — TODO
- peripheral/ClassicalCurveSale.sol:as (1637 LOC) — TODO
- peripheral/ClassicalCurveSale.sol:to (1637 LOC) — TODO
- peripheral/ClassicalCurveSale.sol:to (1637 LOC) — TODO
- peripheral/ClassicalCurveSale.sol:as (1637 LOC) — TODO
- peripheral/ClassicalCurveSale.sol:that (1637 LOC) — TODO
- peripheral/ClassicalCurveSale.sol:ETH (1637 LOC) — TODO
- peripheral/ClassicalCurveSale.sol:IZAMM (1637 LOC) — TODO
- peripheral/ClassicalCurveSale.sol:ERC20 (1637 LOC) — TODO
- peripheral/LPSeedSwapHook.sol:for (1091 LOC) — TODO
- peripheral/LPSeedSwapHook.sol:IZAMM (1091 LOC) — TODO
- peripheral/LPSeedSwapHook.sol:IMoloch (1091 LOC) — TODO
- peripheral/LPSeedSwapHook.sol:for (1091 LOC) — TODO
- peripheral/LPSeedSwapHook.sol:IShareSale (1091 LOC) — TODO
- peripheral/LPSeedSwapHook.sol:allowances (1091 LOC) — TODO
- peripheral/LPSeedSwapHook.sol:LPSeedSwapHook (1091 LOC) — TODO
- peripheral/LPSeedSwapHook.sol:if (1091 LOC) — TODO
- peripheral/MolochViewHelper.sol:ISummoner (1247 LOC) — TODO
- peripheral/MolochViewHelper.sol:IBadges (1247 LOC) — TODO
- peripheral/MolochViewHelper.sol:IShares (1247 LOC) — TODO
- peripheral/MolochViewHelper.sol:ILoot (1247 LOC) — TODO
- peripheral/MolochViewHelper.sol:IERC20 (1247 LOC) — TODO
- peripheral/MolochViewHelper.sol:IDAICO (1247 LOC) — TODO
- peripheral/MolochViewHelper.sol:IMoloch (1247 LOC) — TODO
- peripheral/MolochViewHelper.sol:MolochViewHelper (1247 LOC) — TODO
- peripheral/RollbackGuardian.sol:IMoloch (207 LOC) — TODO
- peripheral/RollbackGuardian.sol:RollbackGuardian (207 LOC) — TODO
- peripheral/RollbackGuardian.sol:uint256 (207 LOC) — TODO
- peripheral/SafeSummoner.sol:ISummoner (1128 LOC) — TODO
- peripheral/SafeSummoner.sol:IMoloch (1128 LOC) — TODO
- peripheral/SafeSummoner.sol:IShareSale (1128 LOC) — TODO
- peripheral/SafeSummoner.sol:ITapVest (1128 LOC) — TODO
- peripheral/SafeSummoner.sol:ILPSeedSwapHook (1128 LOC) — TODO
- peripheral/SafeSummoner.sol:ISharesLoot (1128 LOC) — TODO
- peripheral/SafeSummoner.sol:IShareBurner (1128 LOC) — TODO
- peripheral/SafeSummoner.sol:IRollbackGuardian (1128 LOC) — TODO
- peripheral/SafeSummoner.sol:IMolochBumpConfig (1128 LOC) — TODO
- peripheral/SafeSummoner.sol:SafeSummoner (1128 LOC) — TODO
- peripheral/SafeSummoner.sol:address (1128 LOC) — TODO
- peripheral/SafeSummoner.sol:address (1128 LOC) — TODO
- peripheral/SafeSummoner.sol:address (1128 LOC) — TODO
- peripheral/SafeSummoner.sol:address (1128 LOC) — TODO
- peripheral/SafeSummoner.sol:via (1128 LOC) — TODO
- peripheral/SafeSummoner.sol:address (1128 LOC) — TODO
- peripheral/SafeSummoner.sol:deployed (1128 LOC) — TODO
- peripheral/ShareBurner.sol:IShares (91 LOC) — TODO
- peripheral/ShareBurner.sol:IMoloch (91 LOC) — TODO
- peripheral/ShareBurner.sol:ShareBurner (91 LOC) — TODO
- peripheral/ShareBurner.sol:uint256 (91 LOC) — TODO
- peripheral/ShareBurner.sol:uint256 (91 LOC) — TODO
- peripheral/ShareSale.sol:an (226 LOC) — TODO
- peripheral/ShareSale.sol:ShareSale (226 LOC) — TODO
- peripheral/ShareSale.sol:and (226 LOC) — TODO
- peripheral/ShareSale.sol:IMoloch (226 LOC) — TODO
- peripheral/TapVest.sol:an (241 LOC) — TODO
- peripheral/TapVest.sol:TapVest (241 LOC) — TODO
- peripheral/TapVest.sol:IMoloch (241 LOC) — TODO
- peripheral/TapVest.sol:IMoloch (241 LOC) — TODO
- peripheral/Tribute.sol:Tribute (337 LOC) — TODO
- peripheral/Tribute.sol:for (337 LOC) — TODO

# Notes

- Auto-generated contract-level map.
- Descriptions are placeholders and can be edited later.


## Known Findings (do NOT repeat — find NEW issues)

- C-001: Zero-quorum auto-futarchy can be farmed to mint arbitrary shares or loot and capture governance (High, high)
- F-001: Permit receipts can replay already-executed proposal intents (High, high)
- F-002: Futarchy reward pools are only accounted for, not escrowed, so winning receipts can become unpayable (High, high)
- F-003: Zero-quorum futarchy lets the first NO voter resolve and drain rewards immediately (High, high)
- F-004: Auto-futarchy can mint unbounded shares or loot as rewards (High, high)
- F-005: BondingCurveSale exact-in buys can undercharge when the solver overshoots (Medium, high)
- F-006: ClassicalCurveSale.configure accepts externally circulating tokens that can later dump against curve ETH (Medium, high)
- F-007: Proposal-threshold checks use current votes while proposal snapshots use the previous block (Medium, high)
- F-008: Zero proposal threshold lets arbitrary outsiders pre-open and hijack deterministic proposal IDs (Low, medium)

## Task

Find security vulnerabilities in the contracts listed above.

You should look for:
- direct vulnerabilities
- low-confidence but still reportable issues
- issues that only become clear after connecting multiple observations

If you identify a problem that is not fully proven, still report it as a low-confidence finding.

## Output Format

Return ONLY a JSON array.

Each element must have:
- `id`: local finding id such as `F-001`
- `severity`: `Critical` / `High` / `Medium` / `Low` / `Informational`
- `confidence`: `high` / `medium` / `low`
- `title`: one-line summary
- `locations`: array of `file:line`
- `claim`: core mechanism statement
- `impact`: why it matters
- `paths`: array of trigger/exploit paths, may be empty

If there are no findings, return `[]`.
