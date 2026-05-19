# Round 1 Summary

## Agent: codex_1
- files touched: `contracts/DInterest.sol`, `contracts/DInterestWithDepositFee.sol`, `contracts/NFT.sol`, `contracts/rewards/MPHMinter.sol`, `contracts/fractionals/ZeroCouponBond.sol`, and retained-finding-linked reward issuance paths including `contracts/models/issuance/MPHIssuanceModel01.sol`
- files revisited / highest-attention files: `contracts/DInterest.sol` was the main focus, with repeated attention on withdrawal, funding, surplus, and ownership-check paths; `contracts/MPHMinter.sol`, `contracts/NFT.sol`, and `contracts/fractionals/ZeroCouponBond.sol` were also directly revisited for exploit validation
- main issue directions investigated: NFT clone initialization/ownership takeover; withdrawal dependence on NFT ownership; vested MPH clawback on withdrawal; stale deficit handling in `fundMultiple()`; undercollateralized zero-coupon bond redemption behavior
- promising but not retained directions: none clearly visible from this agent’s logs beyond the four retained findings

## Agent: opencode_1
- files touched: `contracts/DInterest.sol`, `contracts/DInterestWithDepositFee.sol`, `contracts/rewards/MPHMinter.sol`, `contracts/rewards/MPHToken.sol`, `contracts/rewards/Rewards.sol`, `contracts/rewards/Vesting.sol`, `contracts/fractionals/FractionalDeposit.sol`, `contracts/fractionals/ZeroCouponBond.sol`, `contracts/models/issuance/MPHIssuanceModel01.sol`, `contracts/zaps/ZapCurve.sol`, `contracts/moneymarkets/yvault/YVaultMarket.sol`
- files revisited / highest-attention files: strongest attention stayed on `DInterest.sol`, `DInterestWithDepositFee.sol`, `MPHMinter.sol`, and `ZeroCouponBond.sol`, with additional passes across rewards, zap, and yVault market code
- main issue directions investigated: admin/control risks in rewards/token ownership; same-block or flash-loan withdrawal behavior; approvals and factory trust in fractionals; yVault withdrawal accounting; mutable core dependency setters; deposit-fee accounting; vesting access control; absence of emergency pause
- promising but not retained directions: `MPHMinter.setMPHTokenOwner`, same-block early-withdraw checks, `ZeroCouponBond` factory approvals, `YVaultMarket.withdraw`, owner-settable model/minter addresses, `ZapCurve` hardcoded zapper, `DInterestWithDepositFee` fee-flow accounting, `Vesting.vest`, `Rewards` emergency controls, and `NFTFactory`/NFT mint-control assumptions

## Cross-Agent Status
- main overlap in file/area attention: both agents concentrated on `DInterest.sol`, `DInterestWithDepositFee.sol`, `MPHMinter.sol`, `ZeroCouponBond.sol`, and adjacent reward/fractionalization flows
- notable differences in attention: `codex_1` narrowed into exploit-chain validation around deposits, funding deficits, NFT ownership, and redemption fairness; `opencode_1` spread attention more broadly across rewards admin surfaces, zap integrations, yVault market logic, and operational/control-plane risks
- underexplored but suspicious files/functions if clearly supported by the logs: `contracts/moneymarkets/yvault/YVaultMarket.sol`, `contracts/zaps/ZapCurve.sol`, `contracts/rewards/Rewards.sol`, `contracts/rewards/Vesting.sol`, and `contracts/fractionals/FractionalDeposit.sol` were examined by `opencode_1` but did not produce retained findings this round

## Retained Findings
- retained set centers on four issues from `codex_1`: NFT reinitialization leading to deposit/funding NFT takeover, MPH vesting clawback blocking withdrawals, stale inactive-deposit deficits being charged to later funders, and first-come-first-served ZCB redemption when collateral is short
