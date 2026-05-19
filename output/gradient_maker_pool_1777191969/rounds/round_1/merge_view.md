# Merge View - Round 1

## Summary
- total findings: 4
- new findings: 4
- updated existing findings: 0
- rejected candidates: 1

## Finding Actions
- exact_agent_candidate: 1
- rewritten_agent_signal: 3

## New Or Updated Findings
| id | action | severity | confidence | source | title | best match |
| --- | --- | --- | --- | --- | --- | --- |
| F-001 | rewritten_agent_signal | High | high | codex | Reward accounting mixes deposit amounts with LP shares, enabling reward theft and claim lockups | codex:0.789 Reward accounting mixes deposit amounts and LP shares, enabling fee theft or stuck rewards |
| F-002 | rewritten_agent_signal | High | high | codex | LP shares are minted from `tokenAmount + ethAmount`, so inventory shifts can overmint shares and drain the scarcer asset | codex:0.552 LP shares are priced from raw token units plus wei, so economically valuable inventory can be drained |
| F-003 | rewritten_agent_signal | High | medium | codex | Deposits use manipulable Uniswap spot reserves instead of the pool's own balances | codex:0.832 Liquidity deposits rely on manipulable Uniswap spot reserves instead of the pool’s own state |
| F-004 | exact_agent_candidate | High | high | codex | Fee-on-transfer or deflationary tokens are over-credited, creating unbacked LP balances | codex:0.866 Fee-on-transfer or deflationary tokens are over-credited, creating insolvency |

## Rejection Reasons
- other: 1

## Rejected Candidates
| category | source | title | reason |
| --- | --- | --- | --- |
| other | codex | The advertised `minTokenAmount` slippage check does not protect liquidity providers | `minTokenAmount` is largely redundant/misleading, but users still explicitly choose the exact `tokenAmount` transferred and the function separately enforces a 1% ratio bound. This is not a realistic protocol-level loss by itself. |
