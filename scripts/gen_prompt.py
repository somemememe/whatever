#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path


def load_findings(path: Path) -> list[dict]:
    if not path.exists() or not path.read_text(encoding="utf-8").strip():
        return []
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, list):
        raise SystemExit(f"findings file must be a JSON array: {path}")
    return data


def format_known_findings(findings: list[dict]) -> str:
    if not findings:
        return "None yet."
    lines = []
    for item in findings:
        lines.append(
            f"- {item.get('id', '?')}: {item.get('title', '?')} "
            f"({item.get('severity', '?')}, {item.get('confidence', '?')})"
        )
    return "\n".join(lines)


def load_excludes(cli_excludes: list[str]) -> list[str]:
    if cli_excludes:
        return cli_excludes

    raw = os.environ.get("AUDITHOUND_EXCLUDE_GLOBS", "").strip()
    if not raw:
        return []

    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"AUDITHOUND_EXCLUDE_GLOBS must be a JSON array: {exc}") from exc

    if not isinstance(data, list) or not all(isinstance(item, str) for item in data):
        raise SystemExit("AUDITHOUND_EXCLUDE_GLOBS must be a JSON array of strings")
    return data


def load_includes(cli_includes: list[str]) -> list[str]:
    if cli_includes:
        return cli_includes

    raw = os.environ.get("AUDITHOUND_INCLUDE_GLOBS", "").strip()
    if not raw:
        return []

    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"AUDITHOUND_INCLUDE_GLOBS must be a JSON array: {exc}") from exc

    if not isinstance(data, list) or not all(isinstance(item, str) for item in data):
        raise SystemExit("AUDITHOUND_INCLUDE_GLOBS must be a JSON array of strings")
    return data


def build_prompt(
    target: str,
    code_map: str,
    findings: list[dict],
    round_summary_path: str | None,
    global_summary_path: str | None,
    excludes: list[str],
    includes: list[str],
) -> str:
    summary_note = ""
    if round_summary_path:
        summary_note = f"""
## Optional Prior Round Summary

An optional prior round summary is available at:
- `{round_summary_path}`

Read it only if useful, and think it before you use it.It may not be very concise.
"""
    global_note = ""
    if global_summary_path:
        global_note = f"""
## Optional Global Audit Memory

An optional global audit memory is available at:
- `{global_summary_path}`

Read it only if useful. It is historical context, not a coverage guarantee,
not proof that any area is safe, and not a priority list.
"""
    exclude_note = ""
    if excludes:
        exclude_lines = "\n".join(f"- `{item}`" for item in excludes)
        exclude_note = f"""
## Excluded From Direct Audit Scope

Do not report findings whose root cause exists solely in files matching:
{exclude_lines}

You may still read those files when they define interfaces, structs, errors, or external integration context used by in-scope implementation files.
"""
    include_note = ""
    if includes:
        include_lines = "\n".join(f"- `{item}`" for item in includes)
        include_note = f"""
## Included Direct Audit Scope

Only keep findings whose root cause location is inside files matching:
{include_lines}

You may still read other files in the target directory for context, but do not report them as root cause locations.
"""
    chain_access_note = """
## Chain Access

Use these chain endpoints directly when you need live on-chain evidence:
- RPC: `https://eth-mainnet.g.alchemy.com/v2/p6UDlMQUt1PeyOcmJpF6Y`
- Etherscan API key: `ZFNNGRNEUNGRH3XHGE5A61Q3MVGIEVF31K`

Use the RPC to inspect deployed code, storage, balances, and return values with `cast`.
Use the Etherscan API key when you need to fetch verified implementation source or confirm proxy metadata.

Examples:
- `cast code <address> --rpc-url https://eth-mainnet.g.alchemy.com/v2/p6UDlMQUt1PeyOcmJpF6Y`
- `cast storage <address> <slot> --rpc-url https://eth-mainnet.g.alchemy.com/v2/p6UDlMQUt1PeyOcmJpF6Y`
- `cast call <address> "<signature>" --rpc-url https://eth-mainnet.g.alchemy.com/v2/p6UDlMQUt1PeyOcmJpF6Y`
- `curl -s "https://api.etherscan.io/v2/api?chainid=1&module=contract&action=getsourcecode&address=<address>&apikey=ZFNNGRNEUNGRH3XHGE5A61Q3MVGIEVF31K"`

When a finding depends on live-chain behavior, do not present it as a hypothesis only.
Support it with chain-derived evidence such as runtime code, storage values, selector discovery, call results, or verified source fetched from Etherscan.

### Proxy Storage Slot Collision Check

When the target is a proxy (or any contract in scope is a proxy), you MUST:
1. Check which storage slots the proxy uses for its own admin/state variables (especially non-standard slots like slot 0).
2. Read the implementation's initialization logic and check which slots it writes during `initialize()`.
3. If the proxy stores admin in a non-EIP-1967 slot that overlaps with the implementation's initialization state, this is a critical storage collision vulnerability.
4. Verify with `cast storage <proxy> 0x0 --rpc-url ...` and `cast storage <proxy> <EIP1967_IMPL_SLOT> --rpc-url ...`.
5. A storage collision means an attacker can re-initialize the implementation through the proxy and seize privileged roles (guardian, governance admin, registry controller), enabling direct treasury drain.

This is one of the highest-value proxy attack patterns — do NOT skip this check for any proxy contract.
"""
    tooling_note = """
## Phase 0: Proxy Detection (MANDATORY — Do this FIRST)

Before any analysis of business logic, determine whether the target is a proxy. Attackers can exploit proxy storage layout, upgrade mechanisms, and initialization guards even when the implementation logic is sound. **Skipping this phase will cause you to miss the highest-value vulnerabilities.**

1. **Check if the target is a proxy**:
   - Read the target contract source. Look for `delegatecall` in the fallback, or inheritance from known proxy patterns (`ERC1967Proxy`, `TransparentUpgradeableProxy`, `AdminUpgradeabilityProxy`, custom proxy with `target_`, etc.).
   - ```bash
     grep -i "delegatecall\|fallback\|implementation\|upgradeTo\|_target\|target_\|setTarget" <target>/Contract.sol
     ```

2. **Find the implementation address**:
   - Standard EIP-1967 proxy:
     ```bash
     cast storage <PROXY_ADDR> 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc --rpc-url <RPC_URL>
     ```
   - Try common getter functions:
     ```bash
     cast call <PROXY_ADDR> "implementation()(address)" --rpc-url <RPC_URL>
     ```
   - For custom proxies, read the proxy source to identify where `target_` or equivalent is stored.

3. **Check proxy storage layout for collisions**:
   - Read the proxy source to identify **which slot stores the admin/owner** — especially non-standard slots (e.g., slot 0 instead of EIP-1967 admin slot).
   - Read the implementation's `initialize()` function and identify **which slots it writes during initialization**.
   - If the proxy stores admin in a slot that overlaps with the implementation's initialization state, this is a **critical storage collision** — an attacker can call `initialize()` through the proxy and seize privileged roles (guardian, governance admin, registry controller), enabling direct treasury drain.
   - ```bash
     cast storage <PROXY_ADDR> 0x0 --rpc-url <RPC_URL>
     cast storage <PROXY_ADDR> <SLOT> --rpc-url <RPC_URL>
     ```

4. **If the implementation source is not already in the target directory**, fetch it using `fetch_source` or by querying Etherscan. Analyze the implementation for business logic vulnerabilities, but also cross-reference with the proxy's storage layout.

**⚠️ CRITICAL: Code Search & Review Best Practices**

1. **Always use case-insensitive search** when looking for functions:
   ```bash
   grep -i "swap" Contract.sol
   ```

2. **Check BOTH directions for bidirectional operations**:
   - If you find `swapAForB()`, also search for `swapBForA()`
   - If you find `deposit()`, also search for `withdraw()`
   - Function naming can vary: `swapETHForTokens` vs `swapETHforTokens` (note capitalization!)

3. **Read the COMPLETE contract file, don't rely only on grep**:
   ```bash
   cat etherscan-contracts/0x.../Contract.sol | less
   ```

4. **When you identify a POTENTIAL vulnerability**:
   - ✅ READ the complete source file to find ALL related functions
   - ✅ Check access modifiers on ALL functions (public/external/internal/private)
   - ✅ Verify your understanding by checking function signatures with `cast`
   - ❌ DON'T stop after finding one function with restrictions
   - ❌ DON'T assume "if X is restricted, Y must be too"

5. **Don't Give Up Too Early**:
   - If you identify a PRICING ERROR or LOGIC BUG but one function has access control:
     * Check ALL related functions in the contract
     * Read the entire contract file to find alternative entry points
     * The vulnerability might be accessible through a different function
"""
    return f"""You are auditing the smart contracts in {target}.

## Starting Point

The source directory below is your starting point. You may and should explore beyond it — use Etherscan to fetch additional verified contracts, and verify everything on-chain.

{code_map}
{include_note}
{exclude_note}
{chain_access_note}
{tooling_note}

## Known Findings (do not duplicate)

{format_known_findings(findings)}
{summary_note}
{global_note}

## Task

Your job is vulnerability discovery. Find vulnerabilities that can realistically be exploited for profit or cause protocol-level harm. The source directory is your starting point, not your boundary.

**Use every tool available.** You have full shell and RPC access. Verify on-chain instead of hypothesizing:
- `cast call` to test if functions are reachable and state supports exploitation
- `cast storage` to inspect proxy slots and state variables
- `curl` with the Etherscan API key to fetch verified source for any contract you need (Etherscan ONLY — do NOT use curl or any HTTP tool to access other websites)
- `grep` / `find` / `read_file` to navigate the source directory
- Python scripts to compute optimal exploit parameters

**If the source in the directory does not match on-chain behavior, the source is wrong — not your reasoning.** Verify via `cast call` whether the vulnerability exists on the fork block, regardless of what the local source files show.

**Think like an attacker, not an auditor.** Your goal is to find at least one vulnerability with a realistic profit path.

Known findings are context, not limits. Use them as leads but explore independently. Produce distinct findings with clear exploit paths.

## Hard Constraints

- **Do NOT search the web for exploit writeups, PoCs, or attack descriptions** for this project. This includes Google, GitHub, security blogs, DeFiHackLabs, Rekt, and any other external source. All findings must come from reading the contract code and verifying on-chain state.
- **Do NOT use external answers/PoCs/articles/repos** (including DeFiHackLabs). Use only on-chain verification and source code analysis.
- **Do NOT curl/wget/fetch any URL outside of Etherscan/blockchain explorers and your configured RPC endpoints.** You may use Etherscan to fetch verified contract source code only.
- **Do NOT access other runs' output directories.** Stay within the target source directory and your own workspace.
- **Do NOT use `find /`, `rg --files /`, or any other command that scans outside the target source directory.** Scope all file-search commands to the target directory (e.g., `find .`, `rg --files .`). Working directory is the target source root.

## Before You Submit: Compute Optimal Parameters

If any finding's exploit path depends on finding an optimal input value (amount, price, ratio, pool index, etc.) for a known contract function, do NOT leave the parameter to guesswork by the downstream PoC agent. Use the chain endpoints and shell access to compute it now:

1. Read the current chain state with `cast call` at the fork block.
2. Write a short Python script to search for the optimal value across a range of candidate inputs. Use `subprocess` to call `cast`, then compare the results to find the maximum profit.
3. Include the computed optimal parameter in your finding's `paths` field with exact numerical values.

If the parameter is trivial to compute (e.g., a fixed ratio or a boolean), skip this step.

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
- `paths`: array of trigger/exploit paths. Include computed optimal parameters when applicable.

If there are no findings, return `[]`.
"""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--map", required=True)
    parser.add_argument("--findings", required=True)
    parser.add_argument("--target", required=True)
    parser.add_argument("--round-summary")
    parser.add_argument("--global-summary")
    parser.add_argument("--exclude", action="append", default=[])
    parser.add_argument("--include", action="append", default=[])
    parser.add_argument("--output", default="-")
    args = parser.parse_args()

    code_map = Path(args.map).read_text(encoding="utf-8")
    findings = load_findings(Path(args.findings))
    excludes = load_excludes(args.exclude)
    includes = load_includes(args.include)
    round_summary_path = None
    if args.round_summary:
        summary_path = Path(args.round_summary)
        if summary_path.exists():
            round_summary_path = str(summary_path.resolve())
    global_summary_path = None
    if args.global_summary:
        global_path = Path(args.global_summary)
        if global_path.exists():
            global_summary_path = str(global_path.resolve())
    prompt = build_prompt(args.target, code_map, findings, round_summary_path, global_summary_path, excludes, includes)

    if args.output == "-":
        print(prompt)
    else:
        Path(args.output).write_text(prompt, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
