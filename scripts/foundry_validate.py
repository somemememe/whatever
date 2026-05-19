#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import socket
import subprocess
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from decimal import Decimal, getcontext
from pathlib import Path


SEVERITY_ORDER = {
    "critical": 4,
    "high": 3,
    "medium": 2,
    "low": 1,
    "informational": 0,
}

CONFIDENCE_ORDER = {
    "high": 2,
    "medium": 1,
    "low": 0,
}


@dataclass
class Finding:
    fid: str
    severity: str
    confidence: str
    title: str
    claim: str
    impact: str
    paths: list[str]
    locations: list[str]


def load_json(path: Path) -> object:
    return json.loads(path.read_text(encoding="utf-8"))


def pick_findings(raw: list[dict], top_k: int) -> list[Finding]:
    findings: list[Finding] = []
    for item in raw:
        if not isinstance(item, dict):
            continue
        fid = str(item.get("id") or "").strip()
        title = str(item.get("title") or "").strip()
        if not fid or not title:
            continue
        paths = item.get("paths", [])
        if isinstance(paths, str):
            paths = [paths]
        if not isinstance(paths, list):
            paths = []
        locations = item.get("locations", [])
        if isinstance(locations, str):
            locations = [locations]
        if not isinstance(locations, list):
            locations = []

        findings.append(
            Finding(
                fid=fid,
                severity=str(item.get("severity") or "Low"),
                confidence=str(item.get("confidence") or "low"),
                title=title,
                claim=str(item.get("claim") or ""),
                impact=str(item.get("impact") or ""),
                paths=[str(p) for p in paths if isinstance(p, str) and p.strip()],
                locations=[str(p) for p in locations if isinstance(p, str) and p.strip()],
            )
        )

    findings.sort(
        key=lambda f: (
            -SEVERITY_ORDER.get(f.severity.lower(), -1),
            -CONFIDENCE_ORDER.get(f.confidence.lower(), -1),
            f.fid,
        )
    )
    return findings[:top_k]


def resolve_codex_cli() -> str:
    found = shutil.which("codex")
    if found:
        return found
    candidates = [
        str(Path.home() / ".npm-global/bin/codex"),
        str(Path.home() / ".local/bin/codex"),
        "/opt/homebrew/bin/codex",
        "/usr/local/bin/codex",
    ]
    for candidate in candidates:
        path = Path(candidate)
        if path.exists() and os.access(path, os.X_OK):
            return str(path)
    raise FileNotFoundError("codex CLI not found in PATH or known install locations")


def extract_solidity(text: str) -> str:
    text = text.strip()
    if not text:
        return ""
    fenced = re.findall(r"```(?:solidity)?\\n(.*?)```", text, flags=re.DOTALL | re.IGNORECASE)
    if fenced:
        return fenced[0].strip() + "\n"
    return text + ("\n" if not text.endswith("\n") else "")


def log(msg: str) -> None:
    print(f"[foundry-validate] {msg}", flush=True)


def summarize_error(stderr: str, stdout: str) -> str:
    text = (stderr or "").strip()
    if not text:
        text = (stdout or "").strip()
    if not text:
        return "(no output)"
    line = text.splitlines()[-1].strip()
    return line[:240]


def parse_logged_uint(text: str, key: str) -> int | None:
    patterns = [
        rf"{re.escape(key)}\s*[:=]\s*([0-9]+)",
        rf"{re.escape(key)}[^0-9]+([0-9]+)",
    ]
    for pat in patterns:
        m = re.search(pat, text)
        if m:
            try:
                return int(m.group(1))
            except ValueError:
                continue
    return None


def parse_logged_address(text: str, key: str) -> str | None:
    patterns = [
        rf"{re.escape(key)}\s*[:=]\s*(0x[a-fA-F0-9]{{40}})",
        rf"{re.escape(key)}[^0-9a-fA-Fx]+(0x[a-fA-F0-9]{{40}})",
    ]
    for pat in patterns:
        m = re.search(pat, text)
        if m:
            return m.group(1)
    return None


def parse_profit_score(text: str) -> int:
    """Return a comparable profit score for maximize-mode selection."""
    effective = parse_logged_uint(text, "AUDITHOUND_EFFECTIVE_PROFIT_WEI")
    if isinstance(effective, int):
        return effective
    profit_any = parse_logged_uint(text, "AUDITHOUND_PROFIT_ANY")
    if isinstance(profit_any, int):
        return profit_any
    profit_wei = parse_logged_uint(text, "AUDITHOUND_PROFIT_WEI")
    if isinstance(profit_wei, int):
        return profit_wei
    return 0


def save_successful_poc(case_dir: Path, attempt: int, score: int, code: str, forge_stdout: str, forge_stderr: str) -> None:
    success_dir = case_dir / "successful_pocs"
    success_dir.mkdir(parents=True, exist_ok=True)
    stem = f"attempt_{attempt:02d}_score_{score}"
    (success_dir / f"{stem}.sol").write_text(code, encoding="utf-8")
    (success_dir / f"{stem}_forge_stdout.log").write_text(forge_stdout, encoding="utf-8")
    (success_dir / f"{stem}_forge_stderr.log").write_text(forge_stderr, encoding="utf-8")


def _rpc_eth_call(rpc_url: str, to: str, data: str) -> str | None:
    payload = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "eth_call",
        "params": [
            {
                "to": to,
                "data": data,
            },
            "latest",
        ],
    }
    req = urllib.request.Request(
        rpc_url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"content-type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=2.0) as resp:
            body = resp.read().decode("utf-8", errors="ignore")
        parsed = json.loads(body)
        result = parsed.get("result")
        if isinstance(result, str) and result.startswith("0x"):
            return result
    except (urllib.error.URLError, TimeoutError, ValueError, json.JSONDecodeError):
        return None
    return None


def _decode_abi_string(hex_data: str) -> str | None:
    # Handles both ABI-encoded string and bytes32 fallback.
    if not hex_data or not hex_data.startswith("0x"):
        return None
    raw = hex_data[2:]
    if len(raw) == 64:
        # bytes32
        try:
            b = bytes.fromhex(raw)
            s = b.rstrip(b"\x00").decode("utf-8", errors="ignore").strip()
            return s or None
        except ValueError:
            return None
    if len(raw) < 128:
        return None
    try:
        offset = int(raw[:64], 16) * 2
        if offset + 64 > len(raw):
            return None
        strlen = int(raw[offset:offset + 64], 16) * 2
        start = offset + 64
        end = start + strlen
        if end > len(raw):
            return None
        b = bytes.fromhex(raw[start:end])
        s = b.decode("utf-8", errors="ignore").strip()
        return s or None
    except ValueError:
        return None


def token_meta_from_rpc(rpc_url: str, token: str) -> tuple[str | None, int | None]:
    # symbol(): 0x95d89b41, decimals(): 0x313ce567
    symbol_hex = _rpc_eth_call(rpc_url, token, "0x95d89b41")
    decimals_hex = _rpc_eth_call(rpc_url, token, "0x313ce567")
    symbol = _decode_abi_string(symbol_hex) if symbol_hex else None
    decimals = None
    if isinstance(decimals_hex, str) and decimals_hex.startswith("0x"):
        try:
            decimals = int(decimals_hex, 16)
        except ValueError:
            decimals = None
    return symbol, decimals


def format_token_amount(amount: int, decimals: int) -> str:
    getcontext().prec = 80
    scaled = Decimal(amount) / (Decimal(10) ** Decimal(decimals))
    text = format(scaled, "f")
    if "." in text:
        int_part, frac = text.split(".", 1)
        int_fmt = f"{int(int_part):,}"
        frac = frac.rstrip("0")
        return f"{int_fmt}.{frac}" if frac else int_fmt
    return f"{int(text):,}"


def detect_contract_and_entry(solidity_code: str) -> tuple[str, str] | None:
    contract_iter = re.finditer(r"\bcontract\s+([A-Za-z_][A-Za-z0-9_]*)\b", solidity_code)
    discovered: list[tuple[str, list[str]]] = []

    for contract_match in contract_iter:
        contract_name = contract_match.group(1)
        open_brace = solidity_code.find("{", contract_match.end())
        if open_brace == -1:
            continue
        depth = 0
        close_brace = -1
        for idx in range(open_brace, len(solidity_code)):
            ch = solidity_code[idx]
            if ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    close_brace = idx
                    break
        if close_brace == -1:
            continue
        contract_body = solidity_code[open_brace:close_brace + 1]

        fn_matches = re.findall(
            r"function\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)\s*([^{;]*)([{;])",
            contract_body,
            flags=re.MULTILINE,
        )
        candidates: list[str] = []
        for fn_name, params, suffix, terminator in fn_matches:
            if terminator != "{":
                continue
            if params.strip():
                continue
            suffix_norm = f" {suffix} "
            if " internal " in suffix_norm or " private " in suffix_norm:
                continue
            if " public " not in suffix_norm and " external " not in suffix_norm:
                continue
            candidates.append(fn_name)
        if candidates:
            discovered.append((contract_name, candidates))

    if not discovered:
        return None

    fn_priority = [
        "executeOnOpportunity",
        "run",
        "attack",
        "exploit",
        "poc",
        "execute",
    ]
    contract_priority = ["FlawVerifier", "FlawVerifierHarness"]

    def pick_fn(candidates: list[str]) -> str:
        lowered = {c.lower(): c for c in candidates}
        for p in fn_priority:
            if p.lower() in lowered:
                return lowered[p.lower()]
        return candidates[0]

    discovered_map = {name: fns for name, fns in discovered}
    for cname in contract_priority:
        if cname in discovered_map:
            return cname, pick_fn(discovered_map[cname])

    for name, fns in discovered:
        if name.lower().startswith("flawverifier"):
            return name, pick_fn(fns)

    name, fns = discovered[-1]
    return name, pick_fn(fns)


def has_fixed_entry(solidity_code: str, entry_fn: str = "executeOnOpportunity") -> bool:
    pattern = rf"function\s+{re.escape(entry_fn)}\s*\(\s*\)\s*([^{{;]*?)\{{"
    for m in re.finditer(pattern, solidity_code, flags=re.MULTILINE):
        sig = f" {m.group(1)} ".lower()
        if " internal " in sig or " private " in sig:
            continue
        if " public " in sig or " external " in sig:
            return True
    return False


def _has_any(text: str, terms: list[str]) -> bool:
    lowered = text.lower()
    return any(t in lowered for t in terms)


def _extract_path_anchors(path_text: str) -> list[str]:
    anchors: list[str] = []
    backticks = re.findall(r"`([^`]+)`", path_text)
    for token in backticks:
        t = token.strip().lower()
        if t:
            anchors.append(t)
    action_terms = [
        "borrow",
        "cook",
        "accrue",
        "remove_collateral",
        "add_collateral",
        "withdraw",
        "liquidate",
        "oracle.get",
        "exchangeRate",
    ]
    path_lower = path_text.lower()
    for term in action_terms:
        if term.lower() in path_lower and term.lower() not in anchors:
            anchors.append(term.lower())
    deduped: list[str] = []
    seen: set[str] = set()
    for a in anchors:
        if a not in seen:
            seen.add(a)
            deduped.append(a)
    return deduped


def _infer_allowed_primitives(paths: list[str]) -> set[str]:
    text = " ".join(paths).lower()
    primitive_terms: dict[str, list[str]] = {
        "flash_loan": ["flashloan", "flash loan", "flash-loan"],
        "swap_route": ["swap", "router", "exactinput", "exactoutput", "amm", "uniswap", "curve", "balancer", "sushi"],
        "borrow_lend": ["borrow", "lending", "repay", "debt", "loan", "collateral"],
        "liquidation": ["liquidate", "liquidation"],
        "mint_burn": ["mint", "burn"],
        "bridge_crosschain": ["bridge", "cross-chain", "cross chain", "layerzero", "wormhole"],
        "oracle_update": ["oracle", "price update", "exchange rate", "updat exchangerate", "updateexchangerate"],
    }
    allowed: set[str] = set()
    for primitive, terms in primitive_terms.items():
        if any(t in text for t in terms):
            allowed.add(primitive)
    return allowed


def _code_uses_primitive(code: str, primitive: str) -> bool:
    checks: dict[str, list[str]] = {
        "flash_loan": ["flashloan", "flash loan", "flash-loan"],
        "swap_route": [" swap", "router", "exactinput", "exactoutput", "uniswap", "curve", "balancer", "sushi"],
        "borrow_lend": ["borrow", "repay", "collateral", "debt"],
        "liquidation": ["liquidate", "liquidation"],
        "mint_burn": ["mint(", " burn(", ".mint(", ".burn("],
        "bridge_crosschain": ["bridge", "layerzero", "wormhole", "lz"],
        "oracle_update": ["oracle", "exchangeRate", "updateExchangeRate", "price"],
    }
    terms = checks.get(primitive, [])
    lowered = code.lower()
    return any(t.lower() in lowered for t in terms)


def path_alignment_violations(solidity_code: str, finding: Finding) -> list[str]:
    if not finding.paths:
        return []
    code = solidity_code.lower()
    violations: list[str] = []
    per_path_anchors = [_extract_path_anchors(p) for p in finding.paths]
    all_anchors: list[str] = []
    for anchors in per_path_anchors:
        all_anchors.extend(anchors)
    all_anchors = list(dict.fromkeys(all_anchors))
    missing_anchors = [a for a in all_anchors if a not in code]
    if all_anchors and len(missing_anchors) == len(all_anchors):
        violations.append("generated code does not contain any key anchors from paths")
    elif all_anchors and missing_anchors and len(missing_anchors) > max(2, len(all_anchors) // 2):
        violations.append(f"generated code misses too many path anchors: {', '.join(missing_anchors[:8])}")

    uncovered_paths: list[int] = []
    for idx, anchors in enumerate(per_path_anchors):
        if not anchors:
            continue
        if not any(a in code for a in anchors):
            uncovered_paths.append(idx)
    if uncovered_paths:
        indexes = ", ".join(str(i) for i in uncovered_paths[:6])
        violations.append(f"generated code does not cover paths indexes: {indexes}")

    all_paths_text = " ".join(finding.paths).lower()
    if "borrow" in all_paths_text and "borrow" not in code:
        violations.append("paths require borrow step but generated code does not include borrow-like calls")
    if "cook" in all_paths_text and "cook(" not in code:
        violations.append("paths require cook() step but generated code does not include cook() call")
    if "remove_collateral" in all_paths_text and "removecollateral" not in code and "remove_collateral" not in code:
        violations.append("paths require collateral removal step but generated code does not include it")

    # Hard anti-cheat rule: prohibit synthetic profit via newly deployed token contracts.
    if re.search(r"\bnew\s+[A-Za-z_][A-Za-z0-9_]*Token\s*\(", solidity_code):
        violations.append("generated code deploys custom token contracts; synthetic profit tokens are forbidden")

    return violations



def path_alignment_warnings(solidity_code: str, finding: Finding) -> list[str]:
    if not solidity_code.strip() or not finding.paths:
        return []
    allowed_primitives = _infer_allowed_primitives(finding.paths)
    primitive_order = [
        "flash_loan",
        "swap_route",
        "borrow_lend",
        "liquidation",
        "mint_burn",
        "bridge_crosschain",
        "oracle_update",
    ]
    extras = [p for p in primitive_order if p not in allowed_primitives and _code_uses_primitive(solidity_code, p)]
    if not extras:
        return []
    return [f"generated code introduces extra economic stages beyond paths: {', '.join(extras)}"]


def chain_id_from_manifest(chain: str) -> int | None:
    c = (chain or "").strip().lower()
    mapping = {
        "mainnet": 1,
        "ethereum": 1,
        "bsc": 56,
        "arbitrum": 42161,
        "optimism": 10,
        "base": 8453,
    }
    return mapping.get(c)


ATTEMPT_STRATEGY_VARIANTS: list[tuple[str, str]] = [
    (
        "direct_or_existing_balance_first",
        "Prefer direct execution using verifier-held assets first. Only use temporary external funding if direct path is infeasible.",
    ),
    (
        "v2_flashswap_funding",
        "Prefer UniswapV2/Sushi-like flashswap funding with deterministic repayment and minimal route complexity.",
    ),
    (
        "alternate_public_liquidity_route",
        "Prefer an alternate public-liquidity venue/route while preserving the same exploit root cause and exploit-path causality.",
    ),
]


def build_generation_prompt(
    target_root: Path,
    contract_address: str,
    finding: Finding,
    chain: str,
    chain_id: int | None,
    fork_block: int,
    rpc_url: str,
    hypothesis_ref: str,
    strategy_label: str,
    strategy_instructions: str,
) -> str:
    paths = "\n".join(f"- {p}" for p in finding.paths) if finding.paths else "- (none provided)"
    locs = "\n".join(f"- {p}" for p in finding.locations) if finding.locations else "- (none provided)"
    chain_display = chain or "unknown"
    chain_id_display = str(chain_id) if isinstance(chain_id, int) else "unknown"
    return f"""You are operating inside a Foundry workspace to build a real exploit PoC.

Allowed inputs only:
- Hypothesis file: {hypothesis_ref}
- RPC: {rpc_url}
- Chain: {chain_display} mainnet
- Chain ID: {chain_id_display}
- Fork block: {fork_block}
- Target contract: {contract_address}
- Target source root: {target_root}

Finding:
- id: {finding.fid}
- severity: {finding.severity}
- confidence: {finding.confidence}
- title: {finding.title}
- claim: {finding.claim}
- impact: {finding.impact}

Exploit paths:
{paths}

Relevant locations:
{locs}

Hard constraints:
- Do NOT use external answers/PoCs/articles/repos (including DeFiHackLabs).
- Do NOT cheat: no vm.deal, vm.store, vm.etch, vm.mockCall, vm.prank, vm.startPrank, arbitrary balance injection, or arbitrary storage writes.
- Allowed: flashloans and realistic public on-chain actions.
- Work only from finding context (claim/paths/locations) + on-chain state at or before the fork block.
- Hard anti-cheat: profitToken MUST NOT be a token deployed during this PoC/test. Profit token must already exist on-chain at the fork block.
- Hard anti-cheat: do not deploy custom ERC20/token contracts to manufacture profit accounting.
- You MUST implement the exploit aligned with the full `Exploit paths` list.
- Do not ignore any path stage unless it is provably infeasible at this fork state.
- Keep the generated PoC mechanically aligned with `Exploit paths` (same core actions, same causality).
- Path-Strict requirements (all cases):
  - Treat `Exploit paths` as the allowed attack plan.
  - Implement a one-to-one mapping from PoC on-chain actions to path stages.
  - Additional realistic public on-chain economic steps are allowed when required for execution (including flashloans/swaps/mint/burn), but they must preserve the same exploit causality.
  - If an additional step is strictly required for execution, keep it minimal and explain in code comments why it does not change the exploit hypothesis.
- If any path stage is infeasible at this fork state, return concrete infeasibility reasons instead of pivoting to an unrelated route.

Task:
1) Convert the hypothesis into concrete exploit preconditions and a profit path.
2) Build and iterate a Foundry exploit PoC implementation in `src/FlawVerifier.sol`.
3) Ensure the PoC can be validated by a Foundry test harness at `test/ExploitPOC.t.sol`.
4) Iterate until either:
   - positive net attacker profit is achieved after repaying temporary capital, or
   - failure is proven with a clear mechanical/economic reason.

Final response must contain only:
- whether profit was achieved
- profit token and amount
- exploit path used
- whether the original hypothesis was validated or refuted

Harness note:
- This validator performs iterative attempts up to a configured max-attempts.
- The test file is auto-generated by the harness.
- If exploitability is not feasible at this fork state, return best-effort executable logic that fails only for concrete on-chain preconditions.
- If any `Exploit paths` stage is infeasible, state the concrete on-chain reason in code comments and avoid silently changing to an unrelated route.
- Because the harness owns the test execution loop, do not output prose summaries; return Solidity only.

Attempt strategy (must follow for this attempt):
- strategy_label: {strategy_label}
- strategy_instructions: {strategy_instructions}
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Output format required by this harness:
- Return ONLY COMPLETE Solidity source code for `src/FlawVerifier.sol` (no markdown, no prose).
- Include at least one deployable contract with a zero-argument constructor.
- Define `function executeOnOpportunity() external` or `public` as the fixed exploit entry.
- Expose non-ETH profit metadata via getters:
  - `profitToken() external view returns (address)` (address(0) means native ETH)
  - `profitAmount() external view returns (uint256)` (net realized profit amount in `profitToken` units)
"""


def build_repair_prompt(
    finding: Finding,
    prev_code: str,
    forge_stdout: str,
    forge_stderr: str,
    strategy_label: str,
    strategy_instructions: str,
) -> str:
    out_tail = forge_stdout[-6000:] if len(forge_stdout) > 6000 else forge_stdout
    err_tail = forge_stderr[-6000:] if len(forge_stderr) > 6000 else forge_stderr
    return f"""You are fixing a failing Foundry PoC for finding {finding.fid}.

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
- strategy_label: {strategy_label}
- strategy_instructions: {strategy_instructions}
- Keep exploit root cause and `Exploit paths` unchanged; only vary funding/execution implementation details.

Finding:
- title: {finding.title}
- claim: {finding.claim}
- impact: {finding.impact}
- exploit_paths: {json.dumps(finding.paths, ensure_ascii=True)}

Current FlawVerifier.sol:
```solidity
{prev_code}
```

forge stdout (tail):
```
{out_tail}
```

forge stderr (tail):
```
{err_tail}
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
"""


def fallback_contract(contract_address: str, finding: Finding) -> str:
    comment = finding.title.replace("*/", "* /")
    return f"""// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract FlawVerifier {{
    address public constant TARGET = {contract_address};

    // {comment}
    function executeOnOpportunity() external {{
        revert("POC generation failed for {finding.fid}");
    }}

    receive() external payable {{}}
}}
"""


def write_foundry_files(work_dir: Path) -> None:
    (work_dir / "src").mkdir(parents=True, exist_ok=True)
    (work_dir / "test").mkdir(parents=True, exist_ok=True)
    for stale in (work_dir / "test").glob("*.sol"):
        stale.unlink()
    foundry_toml = """[profile.default]
src = "src"
test = "test"
out = "out"
libs = ["lib"]
optimizer = true
optimizer_runs = 200
via_ir = true
"""
    (work_dir / "foundry.toml").write_text(foundry_toml, encoding="utf-8")


def write_test_file(work_dir: Path, block_number: int, contract_name: str, min_profit_wei: int, prefund_wei: int) -> None:
    test_template = f"""// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../src/FlawVerifier.sol";

interface Vm {{
    function createSelectFork(string calldata urlOrAlias, uint256 blockNumber) external returns (uint256);
    function envString(string calldata name) external returns (string memory);
    function deal(address who, uint256 newBalance) external;
}}

interface IAuditTokenLike {{
    function balanceOf(address account) external view returns (uint256);
}}

address constant HEVM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));

contract FlawVerifierTest {{
    Vm constant vm = Vm(HEVM_ADDRESS);
    {contract_name} verifier;

    event log_named_uint(string key, uint256 val);
    event log_named_address(string key, address val);

    function _readAddressGetter(bytes4 selector) internal view returns (bool, address) {{
        (bool ok, bytes memory ret) = address(verifier).staticcall(abi.encodeWithSelector(selector));
        if (!ok || ret.length < 32) return (false, address(0));
        return (true, abi.decode(ret, (address)));
    }}

    function _readUintGetter(bytes4 selector) internal view returns (bool, uint256) {{
        (bool ok, bytes memory ret) = address(verifier).staticcall(abi.encodeWithSelector(selector));
        if (!ok || ret.length < 32) return (false, 0);
        return (true, abi.decode(ret, (uint256)));
    }}

    function _readProfitToken() internal view returns (bool, address) {{
        (bool ok, address token) = _readAddressGetter(bytes4(keccak256("profitToken()")));
        if (ok) return (true, token);
        (ok, token) = _readAddressGetter(bytes4(keccak256("lastProfitToken()")));
        if (ok) return (true, token);
        (ok, token) = _readAddressGetter(bytes4(keccak256("previewProfitToken()")));
        if (ok) return (true, token);
        return (false, address(0));
    }}

    function _readProfitAmount() internal view returns (bool, uint256) {{
        (bool ok, uint256 amount) = _readUintGetter(bytes4(keccak256("profitAmount()")));
        if (ok) return (true, amount);
        (ok, amount) = _readUintGetter(bytes4(keccak256("lastProfitAmount()")));
        if (ok) return (true, amount);
        (ok, amount) = _readUintGetter(bytes4(keccak256("previewProfitAmount()")));
        if (ok) return (true, amount);
        return (false, 0);
    }}

    function _tokenBalance(address token, address account) internal view returns (uint256) {{
        if (token == address(0)) return 0;
        (bool ok, bytes memory ret) = token.staticcall(abi.encodeWithSelector(IAuditTokenLike.balanceOf.selector, account));
        if (!ok || ret.length < 32) return 0;
        return abi.decode(ret, (uint256));
    }}

    function setUp() public {{
        vm.createSelectFork(vm.envString("AUDITHOUND_RPC_URL"), {block_number});
        verifier = new {contract_name}();
        if ({prefund_wei} > 0) {{
            vm.deal(address(verifier), {prefund_wei});
        }}
    }}

    function testExploit() public {{
        uint256 beforeBal = address(verifier).balance;
        (bool tokenBeforeOk, address tokenBefore) = _readProfitToken();
        uint256 beforeTokenBal = tokenBeforeOk && tokenBefore != address(0)
            ? _tokenBalance(tokenBefore, address(verifier))
            : 0;
        (bool ok, bytes memory ret) = address(verifier).call(abi.encodeWithSignature("executeOnOpportunity()"));
        require(ok, "exploit call reverted");
        uint256 afterBal = address(verifier).balance;
        uint256 nativeProfit = afterBal >= beforeBal ? (afterBal - beforeBal) : 0;
        uint256 reportedProfit = 0;
        address reportedToken = address(0);
        (bool tokenAfterOk, address tokenAfter) = _readProfitToken();
        (bool amountAfterOk, uint256 amountAfter) = _readProfitAmount();
        if (tokenAfterOk && tokenAfter != address(0)) {{
            uint256 afterTokenBal = _tokenBalance(tokenAfter, address(verifier));
            if (tokenBeforeOk && tokenBefore == tokenAfter) {{
                reportedProfit = afterTokenBal >= beforeTokenBal ? (afterTokenBal - beforeTokenBal) : 0;
            }} else if (amountAfterOk) {{
                // Support PoCs that publish profit token/amount only after execution.
                reportedProfit = amountAfter;
            }} else if (!tokenBeforeOk || tokenBefore == address(0)) {{
                // Fresh verifier usually starts with zero balance for a newly selected profit token.
                reportedProfit = afterTokenBal;
            }}
            reportedToken = tokenAfter;
        }}

        // Hard rule: only count realized, transferable-balance deltas.
        // For native token, only balance delta is valid.
        // For ERC20, only verifier's token balance delta is valid.
        if (reportedToken == address(0)) {{
            reportedProfit = 0;
        }}

        // Misclassification guard: converting initial funded principal into a token is not exploit profit.
        if (nativeProfit == 0 && reportedToken != address(0) && reportedProfit == beforeBal) {{
            reportedProfit = 0;
        }}
        uint256 effectiveProfit = nativeProfit > 0 ? nativeProfit : reportedProfit;

        emit log_named_uint("AUDITHOUND_BALANCE_BEFORE_WEI", beforeBal);
        emit log_named_uint("AUDITHOUND_BALANCE_AFTER_WEI", afterBal);
        emit log_named_uint("AUDITHOUND_PROFIT_WEI", nativeProfit);
        emit log_named_uint("AUDITHOUND_PROFIT_ANY", reportedProfit);
        emit log_named_uint("AUDITHOUND_EFFECTIVE_PROFIT_WEI", effectiveProfit);
        emit log_named_uint("AUDITHOUND_MIN_PROFIT_WEI", {min_profit_wei});
        emit log_named_address("AUDITHOUND_PROFIT_TOKEN", reportedToken);
        emit log_named_address("AUDITHOUND_PROFIT_MODE", nativeProfit > 0 ? address(0) : address(1));

        // Anti-cheat: when non-native profit token is reported, it must already exist at fork block.
        if (reportedToken != address(0)) {{
            vm.createSelectFork(vm.envString("AUDITHOUND_RPC_URL"), {block_number});
            uint256 forkCodeSize;
            assembly {{
                forkCodeSize := extcodesize(reportedToken)
            }}
            emit log_named_uint("AUDITHOUND_PROFIT_TOKEN_CODE_SIZE_ON_FORK", forkCodeSize);
            require(forkCodeSize > 0, "profit token not present at fork block");
        }}
        require(effectiveProfit >= {min_profit_wei}, "profit below threshold");
    }}
}}
"""
    (work_dir / "test" / "ExploitPOC.t.sol").write_text(test_template, encoding="utf-8")


def run_cmd(cmd: list[str], cwd: Path, env: dict[str, str] | None = None, input_text: str | None = None) -> tuple[int, str, str]:
    proc = subprocess.run(
        cmd,
        cwd=str(cwd),
        env=env,
        input=input_text,
        text=True,
        capture_output=True,
        check=False,
    )
    return proc.returncode, proc.stdout, proc.stderr


def run_codex_generate(codex_bin: str, target_root: Path, cwd: Path, model: str, reasoning_effort: str, prompt: str) -> tuple[int, str, str]:
    gen_cmd = [
        codex_bin,
        "-a",
        "never",
        "exec",
        "--cd",
        str(target_root),
        "--sandbox",
        "workspace-write",
        "--skip-git-repo-check",
        "-m",
        model,
        "-c",
        f'model_reasoning_effort="{reasoning_effort}"',
        "-",
    ]
    gen_env = os.environ.copy()
    gen_env["CODEX_MODEL"] = model
    return run_cmd(gen_cmd, cwd=cwd, env=gen_env, input_text=prompt)


def _port_is_open(port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(0.25)
        return sock.connect_ex(("127.0.0.1", port)) == 0


def _find_free_port(start: int = 18545, end: int = 18650) -> int:
    for port in range(start, end + 1):
        if not _port_is_open(port):
            return port
    raise RuntimeError(f"no free port found in range {start}-{end}")


def _rpc_block_number(rpc_url: str) -> int | None:
    payload = json.dumps({"jsonrpc": "2.0", "id": 1, "method": "eth_blockNumber", "params": []}).encode("utf-8")
    req = urllib.request.Request(
        rpc_url,
        data=payload,
        headers={"content-type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=2.0) as resp:
            body = resp.read().decode("utf-8", errors="ignore")
        data = json.loads(body)
        result = data.get("result")
        if isinstance(result, str) and result.startswith("0x"):
            return int(result, 16)
        return None
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, ValueError):
        return None


def start_reusable_anvil(
    upstream_rpc_url: str,
    fork_block: int,
    preferred_port: int | None = None,
    port_start: int = 18545,
    port_end: int = 18650,
    ready_timeout: float = 20.0,
) -> tuple[subprocess.Popen[str], str, int]:
    anvil_bin = shutil.which("anvil")
    if not anvil_bin:
        raise FileNotFoundError("anvil not found in PATH")

    if preferred_port is not None:
        if _port_is_open(preferred_port):
            raise RuntimeError(f"requested anvil port is already in use: {preferred_port}")
        port = preferred_port
    else:
        port = _find_free_port(start=port_start, end=port_end)

    cmd = [
        anvil_bin,
        "--silent",
        "--host",
        "127.0.0.1",
        "--port",
        str(port),
        "--fork-url",
        upstream_rpc_url,
        "--fork-block-number",
        str(fork_block),
    ]
    proc: subprocess.Popen[str] = subprocess.Popen(
        cmd,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        text=True,
    )

    local_rpc = f"http://127.0.0.1:{port}"
    deadline = time.time() + ready_timeout
    while time.time() < deadline:
        if proc.poll() is not None:
            raise RuntimeError("anvil exited before becoming ready")
        block = _rpc_block_number(local_rpc)
        if block is not None:
            return proc, local_rpc, port
        time.sleep(0.25)

    proc.terminate()
    try:
        proc.wait(timeout=2)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=2)
    raise RuntimeError(f"anvil did not become ready within {ready_timeout:.1f}s")


def run_forge(case_dir: Path, rpc_url: str) -> tuple[int, str, str]:
    forge_env = os.environ.copy()
    forge_env["AUDITHOUND_RPC_URL"] = rpc_url
    forge_env["FOUNDRY_OFFLINE"] = "true"
    forge_env.setdefault("NO_PROXY", "*")
    return run_cmd(["forge", "test", "-vvv", "--match-test", "testExploit"], cwd=case_dir, env=forge_env)


def sanitize_name(s: str) -> str:
    return re.sub(r"[^a-zA-Z0-9_.-]+", "_", s).strip("_") or "finding"


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate and run Foundry validation from findings.")
    parser.add_argument("--manifest", required=True, help="Path to case manifest.json with address and block number.")
    parser.add_argument("--findings", required=True, help="Path to findings_acc.json.")
    parser.add_argument("--output-dir", required=True, help="Run output dir to place validation artifacts.")
    parser.add_argument("--rpc-url", help="Optional explicit RPC URL. Otherwise read from env by chain.")
    parser.add_argument("--top-k", type=int, default=3, help="Top findings to validate.")
    parser.add_argument(
        "--objective",
        choices=("threshold", "maximize"),
        default="maximize",
        help="Validation objective: threshold=stop on first passing PoC, maximize=search best profit.",
    )
    parser.add_argument("--min-profit", type=float, default=0.001, help="Profit threshold in native token.")
    parser.add_argument(
        "--prefund-wei",
        type=int,
        default=0,
        help="Optional initial ETH funding for verifier in tests. Default 0 to avoid principal-as-profit misclassification.",
    )
    parser.add_argument("--model", default=os.environ.get("CODEX_MODEL", "gpt-5.4"), help="Model used for PoC generation.")
    parser.add_argument(
        "--reasoning-effort",
        choices=("minimal", "low", "medium", "high", "xhigh"),
        default=os.environ.get("CODEX_REASONING_EFFORT", "medium"),
    )
    parser.add_argument("--max-attempts", type=int, default=3, help="Maximum PoC generation/validation attempts per finding.")
    parser.add_argument(
        "--maximize-plateau",
        type=int,
        default=2,
        help="Stop after this many consecutive successful attempts without profit-score improvement.",
    )
    parser.add_argument(
        "--anvil-port",
        type=int,
        default=int(os.environ["ANVIL_PORT"]) if os.environ.get("ANVIL_PORT") else None,
        help="Fixed local anvil port for this validation process.",
    )
    parser.add_argument(
        "--anvil-port-start",
        type=int,
        default=int(os.environ.get("ANVIL_PORT_START", "18545")),
        help="Start of port range used when auto-selecting an anvil port.",
    )
    parser.add_argument(
        "--anvil-port-end",
        type=int,
        default=int(os.environ.get("ANVIL_PORT_END", "18650")),
        help="End of port range used when auto-selecting an anvil port.",
    )
    parser.add_argument(
        "--anvil-ready-timeout",
        type=float,
        default=float(os.environ.get("ANVIL_READY_TIMEOUT", "20")),
        help="Seconds to wait for local anvil to become RPC-ready.",
    )
    args = parser.parse_args()

    manifest_path = Path(args.manifest).expanduser().resolve()
    findings_path = Path(args.findings).expanduser().resolve()
    run_output_dir = Path(args.output_dir).expanduser().resolve()
    validation_root = run_output_dir / "foundry_validation"
    validation_root.mkdir(parents=True, exist_ok=True)

    manifest = load_json(manifest_path)
    if not isinstance(manifest, dict):
        raise SystemExit(f"manifest must be JSON object: {manifest_path}")

    raw_findings = load_json(findings_path)
    if not isinstance(raw_findings, list):
        raise SystemExit(f"findings must be JSON array: {findings_path}")

    chain = str(manifest.get("chain", "")).lower()
    env_by_chain = {
        "mainnet": "ETH_RPC_URL",
        "ethereum": "ETH_RPC_URL",
        "bsc": "BSC_RPC_URL",
        "base": "BASE_RPC_URL",
        "arbitrum": "ARBITRUM_RPC_URL",
        "optimism": "OPTIMISM_RPC_URL",
    }
    rpc_url = args.rpc_url or os.environ.get(env_by_chain.get(chain, ""), "")
    if not rpc_url:
        raise SystemExit(
            f"missing rpc url: pass --rpc-url or set {env_by_chain.get(chain, 'CHAIN_RPC_URL')} for chain={chain or 'unknown'}"
        )

    block_number = int(manifest.get("fork_block_number"))
    contract_address = str(manifest.get("target_contract_address"))
    target_root = Path(str(manifest.get("target_root"))).expanduser().resolve()
    chain_id = chain_id_from_manifest(chain)
    hypothesis_ref = str(
        manifest.get("hypothesis_file")
        or manifest.get("hypothesis_path")
        or f"finding:{manifest.get('audit_id', 'unknown')}"
    )

    selected = pick_findings(raw_findings, args.top_k)
    if not selected:
        raise SystemExit("no findings available for validation")

    codex_bin = resolve_codex_cli()
    results: list[dict] = []

    max_attempts = max(1, int(args.max_attempts))
    maximize_plateau = max(1, int(args.maximize_plateau))
    objective = str(args.objective)
    log(
        f"start validate: findings={len(selected)} top_k={args.top_k} "
        f"max_attempts={max_attempts} objective={objective} plateau={maximize_plateau} "
        f"anvil_port={args.anvil_port} range={args.anvil_port_start}-{args.anvil_port_end} "
        f"ready_timeout={args.anvil_ready_timeout}"
    )

    anvil_proc: subprocess.Popen[str] | None = None
    forge_rpc_url = rpc_url
    try:
        if args.anvil_port_start > args.anvil_port_end:
            raise SystemExit("--anvil-port-start must be <= --anvil-port-end")
        anvil_proc, forge_rpc_url, anvil_port = start_reusable_anvil(
            rpc_url,
            block_number,
            preferred_port=args.anvil_port,
            port_start=args.anvil_port_start,
            port_end=args.anvil_port_end,
            ready_timeout=float(args.anvil_ready_timeout),
        )
        log(f"local anvil started: rpc={forge_rpc_url} port={anvil_port} fork_block={block_number}")

        for idx, finding in enumerate(selected, start=1):
            log(f"[{idx}/{len(selected)}] finding={finding.fid} severity={finding.severity} title={finding.title}")
            case_dir = validation_root / sanitize_name(f"{finding.fid}_{finding.title[:40]}")
            write_foundry_files(case_dir)
    
            generated_ok = False
            attempt_used = 0
            test_rc, test_out, test_err = 1, "", ""
            current_code = ""
            current_detected: tuple[str, str] | None = None
            warning_notes: list[str] = []
            successful_attempts: list[dict] = []
            best_success: dict | None = None
            no_improve_successes = 0
            attempts_run = 0
            strategy_idx = 0
    
            for attempt in range(max_attempts):
                attempt_used = attempt
                strategy_label, strategy_instructions = ATTEMPT_STRATEGY_VARIANTS[
                    strategy_idx % len(ATTEMPT_STRATEGY_VARIANTS)
                ]
                log(f"[{finding.fid}] attempt={attempt} strategy={strategy_label}")
                if attempt == 0:
                    attempt_prompt = build_generation_prompt(
                        target_root=target_root,
                        contract_address=contract_address,
                        finding=finding,
                        chain=chain,
                        chain_id=chain_id,
                        fork_block=block_number,
                        rpc_url=rpc_url,
                        hypothesis_ref=hypothesis_ref,
                        strategy_label=strategy_label,
                        strategy_instructions=strategy_instructions,
                    )
                    (case_dir / "poc_prompt_initial.md").write_text(attempt_prompt, encoding="utf-8")
                else:
                    attempt_prompt = build_repair_prompt(
                        finding=finding,
                        prev_code=current_code,
                        forge_stdout=test_out,
                        forge_stderr=test_err,
                        strategy_label=strategy_label,
                        strategy_instructions=strategy_instructions,
                    )
                    (case_dir / f"poc_prompt_repair_{attempt}.md").write_text(attempt_prompt, encoding="utf-8")
    
                log(f"[{finding.fid}] codex attempt={attempt} generating poc")
                rc, out, err = run_codex_generate(
                    codex_bin=codex_bin,
                    target_root=target_root,
                    cwd=case_dir,
                    model=args.model,
                    reasoning_effort=args.reasoning_effort,
                    prompt=attempt_prompt,
                )
                log(f"[{finding.fid}] codex attempt={attempt} rc={rc} stdout_len={len(out)} stderr_len={len(err)}")
                (case_dir / f"codex_stdout_attempt{attempt}.log").write_text(out, encoding="utf-8")
                (case_dir / f"codex_stderr_attempt{attempt}.log").write_text(err, encoding="utf-8")
    
                parsed = extract_solidity(out)
                detected = detect_contract_and_entry(parsed) if rc == 0 else None
                path_violations = path_alignment_violations(parsed, finding) if rc == 0 else ["codex generation failed"]
                if rc == 0 and not has_fixed_entry(parsed, "executeOnOpportunity"):
                    path_violations.append("generated code must define fixed entry function executeOnOpportunity()")
                path_warnings = path_alignment_warnings(parsed, finding) if rc == 0 else []
                if path_warnings:
                    warning_text = "PATH_ALIGNMENT_WARNING: " + "; ".join(path_warnings)
                    warning_notes.extend(path_warnings)
                    (case_dir / f"path_alignment_warning_attempt{attempt}.log").write_text(warning_text + "\n", encoding="utf-8")
                    log(f"[{finding.fid}] attempt={attempt} {warning_text}")
                if detected is not None and not path_violations:
                    generated_ok = True
                    current_code = parsed
                    current_detected = detected
                    log(f"[{finding.fid}] poc accepted attempt={attempt} contract={detected[0]} entry={detected[1]}")
                elif current_detected is None:
                    if path_violations:
                        reason = "; ".join(path_violations)
                    elif detected is None:
                        reason = "generated code missing a detectable verifier contract/entry (expected FlawVerifier + no-arg public/external entry)"
                    else:
                        reason = summarize_error(err, out)
                    log(f"[{finding.fid}] poc invalid attempt={attempt}; using fallback; reason={reason}")
                    current_code = fallback_contract(contract_address, finding)
                    current_detected = ("FlawVerifier", "executeOnOpportunity")
                else:
                    reason = "; ".join(path_violations) if path_violations else summarize_error(err, out)
                    log(f"[{finding.fid}] poc invalid attempt={attempt}; reusing previous valid code; reason={reason}")
    
                if path_violations:
                    violation_text = "PATH_ALIGNMENT_ERROR: " + "; ".join(path_violations)
                    (case_dir / f"path_alignment_attempt{attempt}.log").write_text(violation_text + "\n", encoding="utf-8")
                    if parsed.strip():
                        current_code = parsed
                        if detected is not None:
                            current_detected = detected
                    test_rc, test_out, test_err = 1, "", violation_text
                    if attempt < max_attempts - 1:
                        log(f"[{finding.fid}] attempt={attempt} rejected by path-alignment check; skipping forge and regenerating")
                        continue
    
                (case_dir / "src" / "FlawVerifier.sol").write_text(current_code, encoding="utf-8")
                contract_name, entry_fn = current_detected
                min_profit_wei = max(0, int(float(args.min_profit) * 1e18))
                prefund_wei = max(0, int(args.prefund_wei))
                write_test_file(case_dir, block_number, contract_name, min_profit_wei, prefund_wei)
    
                log(f"[{finding.fid}] forge attempt={attempt} running")
                test_rc, test_out, test_err = run_forge(case_dir, forge_rpc_url)
                log(f"[{finding.fid}] forge attempt={attempt} rc={test_rc} summary={summarize_error(test_err, test_out)}")
                (case_dir / f"forge_stdout_attempt{attempt}.log").write_text(test_out, encoding="utf-8")
                (case_dir / f"forge_stderr_attempt{attempt}.log").write_text(test_err, encoding="utf-8")
                attempts_run = attempt + 1
                attempt_combined = f"{test_out}\n{test_err}"
                attempt_profit_score = parse_profit_score(attempt_combined)
                profit_only_failure = (
                    test_rc != 0
                    and "profit below threshold" in attempt_combined.lower()
                    and attempt_profit_score <= 0
                )
                if test_rc == 0:
                    attempt_profit_wei = parse_logged_uint(attempt_combined, "AUDITHOUND_PROFIT_WEI")
                    attempt_profit_any = parse_logged_uint(attempt_combined, "AUDITHOUND_PROFIT_ANY")
                    attempt_profit_token = parse_logged_address(attempt_combined, "AUDITHOUND_PROFIT_TOKEN")
                    save_successful_poc(case_dir, attempt, attempt_profit_score, current_code, test_out, test_err)
                    successful_attempts.append(
                        {
                            "attempt": attempt,
                            "profit_score": attempt_profit_score,
                            "profit_wei": attempt_profit_wei,
                            "profit_any": attempt_profit_any,
                            "profit_token": attempt_profit_token,
                        }
                    )
                    if best_success is None or attempt_profit_score > int(best_success.get("profit_score", -1)):
                        best_success = {
                            "attempt": attempt,
                            "profit_score": attempt_profit_score,
                            "code": current_code,
                            "test_out": test_out,
                            "test_err": test_err,
                        }
                        no_improve_successes = 0
                        log(f"[{finding.fid}] new best profit score={attempt_profit_score} at attempt={attempt}")
                    else:
                        no_improve_successes += 1
                        log(
                            f"[{finding.fid}] attempt={attempt} pass but no improvement "
                            f"(score={attempt_profit_score}, streak={no_improve_successes})"
                        )
                    if objective == "threshold":
                        log(f"[{finding.fid}] threshold objective satisfied at attempt={attempt}; stopping further attempts")
                        break
                    if no_improve_successes >= maximize_plateau and attempt < max_attempts - 1:
                        log(
                            f"[{finding.fid}] maximize plateau reached ({no_improve_successes}); "
                            "stopping further attempts"
                        )
                        break
                # Strategy switching trigger:
                # - switch only for economic non-positive outcomes
                #   (including explicit profit-below-threshold failures with non-positive score);
                # - keep same strategy for non-economic runtime/compile failures.
                if attempt < max_attempts - 1 and (
                    (test_rc == 0 and attempt_profit_score <= 0) or profit_only_failure
                ):
                    strategy_idx += 1
                    log(
                        f"[{finding.fid}] switching strategy for next attempt "
                        f"(profit_score={attempt_profit_score}, rc={test_rc})"
                    )

            if best_success is not None:
                # Use the highest-profit successful PoC as final outcome.
                attempt_used = int(best_success["attempt"])
                current_code = str(best_success["code"])
                test_out = str(best_success["test_out"])
                test_err = str(best_success["test_err"])
                test_rc = 0
                (case_dir / "src" / "FlawVerifier.sol").write_text(current_code, encoding="utf-8")
                (case_dir / "best_poc.sol").write_text(current_code, encoding="utf-8")
            elif attempts_run > 0:
                attempt_used = attempts_run - 1

            combined = f"{test_out}\n{test_err}"
            bal_before = parse_logged_uint(combined, "AUDITHOUND_BALANCE_BEFORE_WEI")
            bal_after = parse_logged_uint(combined, "AUDITHOUND_BALANCE_AFTER_WEI")
            profit_wei = parse_logged_uint(combined, "AUDITHOUND_PROFIT_WEI")
            profit_any = parse_logged_uint(combined, "AUDITHOUND_PROFIT_ANY")
            profit_token = parse_logged_address(combined, "AUDITHOUND_PROFIT_TOKEN")

            if profit_wei is None and bal_before is not None and bal_after is not None:
                profit_wei = bal_after - bal_before

            log(f"[{finding.fid}] final result pass={test_rc == 0} attempts_used={attempt_used}")
            pretty_profit = None
            if isinstance(profit_any, int) and profit_any > 0 and profit_token and profit_token.lower() != "0x0000000000000000000000000000000000000000":
                symbol, decimals = token_meta_from_rpc(forge_rpc_url, profit_token)
                symbol = symbol or profit_token
                decimals = decimals if isinstance(decimals, int) and 0 <= decimals <= 36 else 18
                pretty_profit = f"{format_token_amount(profit_any, decimals)} {symbol}"
            log(
                f"[{finding.fid}] profit summary: "
                f"profit_wei={profit_wei if profit_wei is not None else 'n/a'} "
                f"profit_any={profit_any if profit_any is not None else 'n/a'} "
                f"profit_eth={(profit_wei / 1e18) if isinstance(profit_wei, int) else 'n/a'}"
                + (f" profit_any_human={pretty_profit}" if pretty_profit else "")
            )

            results.append(
                {
                    "id": finding.fid,
                    "title": finding.title,
                    "severity": finding.severity,
                    "confidence": finding.confidence,
                    "workspace": str(case_dir),
                    "poc_generated": generated_ok,
                    "forge_test_passed": test_rc == 0,
                    "attempts_used": attempt_used,
                    "auto_repair_enabled": max_attempts > 1,
                    "balance_before_wei": bal_before,
                    "balance_after_wei": bal_after,
                    "profit_wei": profit_wei,
                    "profit_any": profit_any,
                    "profit_eth": (profit_wei / 1e18) if isinstance(profit_wei, int) else None,
                    "best_profit_score": int(best_success.get("profit_score", 0)) if best_success is not None else 0,
                    "best_attempt": int(best_success["attempt"]) if best_success is not None else None,
                    "successful_attempts": successful_attempts,
                    "path_alignment_warnings": list(dict.fromkeys(warning_notes)),
                    "last_error_excerpt": (test_err or test_out)[-500:] if test_rc != 0 else "",
                }
            )

    finally:
        if anvil_proc is not None:
            anvil_proc.terminate()
            try:
                anvil_proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                anvil_proc.kill()
                anvil_proc.wait(timeout=3)
            log("local anvil stopped")

    summary = {
        "manifest": str(manifest_path),
        "findings": str(findings_path),
        "target_root": str(target_root),
        "block_number": block_number,
        "target_contract_address": contract_address,
        "rpc_url_upstream": rpc_url,
        "rpc_url_forge": forge_rpc_url,
        "validated_count": len(results),
        "passed_count": sum(1 for r in results if r.get("forge_test_passed")),
        "auto_repair_enabled": max_attempts > 1,
        "max_retries": max_attempts - 1,
        "results": results,
    }
    summary_path = validation_root / "summary.json"
    summary_path.write_text(json.dumps(summary, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
    log(f"completed validate: passed={summary['passed_count']}/{summary['validated_count']} summary={summary_path}")
    print(json.dumps({"summary": str(summary_path), "validated": len(results)}, ensure_ascii=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
