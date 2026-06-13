#!/usr/bin/env python3
"""
Red_V2-style unbounded agent for AuditHoundV2 validation.
Replaces tool_call_runner.py's fixed-step loop.

Key differences from tool_call_runner.py:
  - No max_steps limit (unbounded agent loop, like Red_V2)
  - task_complete auto-verifies by running forge test
  - System prompt is Red_V2-style phased workflow
  - Agent internally iterates: analyze -> code -> test -> fix -> complete

Usage:
  python3 agent_validate.py \\
    --workdir /path/to/workspace \\
    --model deepseek-v4-pro \\
    --provider deepseek \\
    --reasoning-effort medium \\
    --prompt-file /path/to/prompt.md \\
    --rpc-url http://127.0.0.1:18545 \\
    [--log-dir /path/to/logs]
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

from openai import OpenAI

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
AGENT_MAX_ITERATIONS = 500  # safety limit; increased for complex cases
AGENT_TIME_BUDGET_SECONDS = 60 * 60  # 60 minutes default
MAX_ANALYSIS_STEPS = 8  # max steps for Phase 1: Quick Analysis
LAST_FORGE_TEST_OUTPUT = None


# ---------------------------------------------------------------------------
# Path sandbox — prevent agent from reading other runs' outputs
# ---------------------------------------------------------------------------
_ALLOWED_ROOTS: list[str] = []


def _set_allowed_roots(workdir: str, target_root: str = "") -> None:
    """Set the list of roots the agent is allowed to access.

    Only these directories (and their subdirectories) are readable.
    All absolute paths outside these roots are rejected.
    """
    global _ALLOWED_ROOTS
    _ALLOWED_ROOTS = [os.path.normpath(os.path.realpath(workdir))]
    if target_root:
        _ALLOWED_ROOTS.append(os.path.normpath(os.path.realpath(target_root)))


def _is_path_allowed(path: str) -> bool:
    """Return True if the path is inside one of the allowed roots.

    Relative paths are always resolved against the first allowed root (workdir).
    """
    global _ALLOWED_ROOTS
    if not _ALLOWED_ROOTS:
        return True  # not initialised — allow for backward compat
    if not os.path.isabs(path):
        return True  # relative paths are resolved by tool_read_file
    normalized = os.path.normpath(os.path.realpath(path))
    for root in _ALLOWED_ROOTS:
        if normalized == root or normalized.startswith(root + os.sep):
            return True
    return False


def _is_shell_command_allowed(command: str) -> tuple[bool, str]:
    """Check a shell command for filesystem access violations.

    Scans for absolute paths and blocks any that fall outside allowed roots.
    Also blocks find / grep -r that start from filesystem root or
    known output directories.
    """
    global _ALLOWED_ROOTS
    if not _ALLOWED_ROOTS:
        return True, ""

    # Find all absolute paths mentioned in the command
    abs_paths = re.findall(r'(?<!\w)(/[^\s;|&<>\"\']{2,})', command)

    # Also check paths after common flags like -path, --directory, -r
    flag_paths = re.findall(
        r'(?:-path|-name|-directory|--directory|cd)\s+(/[^\s;|&<>]+)',
        command
    )
    abs_paths.extend(flag_paths)

    # Block find /, find /Users, find ~ that scan entire filesystem
    find_root_pattern = re.search(
        r'\bfind\s+(/|/Users|/home|~)', command
    )
    if find_root_pattern:
        return False, (
            "REJECTED: find command starts from filesystem root or home "
            "directory. Use find only within the workspace or target source "
            "directory. Example: find . -name '*.sol'"
        )

    for p in abs_paths:
        # Skip paths that are just flag prefixes
        if p in ("/", "/U", "/Us", "/Use", "/User", "/Users"):
            continue
        if not _is_path_allowed(p):
            return False, (
                f"REJECTED: command accesses path outside sandbox: {p}. "
                "You may only read files within the workspace or the target "
                "source directory. Use relative paths or verify with "
                "read_file first."
            )

    return True, ""


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def _log(msg: str) -> None:
    print(f"[agent] {msg}", file=sys.stderr, flush=True)


def _tool_call_summary(name: str, args: dict, max_len: int = 120) -> str:
    """Build a one-line summary of a tool call for logging."""
    if name == "run_shell_command":
        return str(args.get("command", ""))[:max_len]
    elif name == "read_file":
        return str(args.get("path", ""))
    elif name == "write_file":
        p = str(args.get("path", ""))
        c = str(args.get("content", ""))
        return f"{p} ({len(c)} bytes)"
    elif name == "task_complete":
        s = str(args.get("summary", args.get("message", "")))
        return s[:max_len]
    else:
        keys = list(args.keys())[:3]
        vals = [str(args[k])[:40] for k in keys]
        pairs = [f"{k}={v}" for k, v in zip(keys, vals)]
        return ", ".join(pairs)[:max_len]


def _rpc_url_from_env(rpc_url: str) -> str:
    """Return the effective RPC URL, falling back to env or default."""
    return (rpc_url or os.environ.get("ETH_RPC_URL") or
            os.environ.get("RPC_URL") or "http://127.0.0.1:8545")


def _resolve_api_key(provider: str) -> str:
    if provider == "deepseek":
        env_keys = ["DEEPSEEK_API_KEY", "OPENAI_API_KEY",
                     "CODEX_API_KEY", "AUDITHOUND_OPENAI_API_KEY"]
    else:
        env_keys = ["OPENAI_API_KEY", "CODEX_API_KEY",
                     "AUDITHOUND_OPENAI_API_KEY"]
    for key in env_keys:
        value = os.environ.get(key, "").strip()
        if value:
            return value
    raise SystemExit(
        "No API key found. Set OPENAI_API_KEY, CODEX_API_KEY, "
        "AUDITHOUND_OPENAI_API_KEY, or DEEPSEEK_API_KEY."
    )


def _resolve_model_name(provider: str, model: str) -> str:
    requested = str(model or "").strip()
    provider = provider.lower().strip()
    if provider != "deepseek":
        return requested
    alias = requested.lower()
    if alias in {"", "deepseek4.0", "deepseek-4.0", "deepseek-v4",
                 "deepseek-v4-flash", "deepseek4", "deepseek-v4-pro"}:
        env_model = (os.environ.get("AUDITHOUND_DEEPSEEK_MODEL", "").strip()
                     or os.environ.get("DEEPSEEK_MODEL", "").strip())
        return env_model or "deepseek-v4-pro"
    return requested


def _client_and_model(provider: str, model: str) -> tuple[OpenAI, str]:
    provider = provider.lower().strip()
    api_key = _resolve_api_key(provider)
    base_url = None
    if provider == "deepseek":
        base_url = os.environ.get("DEEPSEEK_BASE_URL",
                                  "https://api.deepseek.com/v1")
    else:
        base_url = os.environ.get("OPENAI_BASE_URL") or None
    client = OpenAI(api_key=api_key, base_url=base_url)
    return client, _resolve_model_name(provider, model)


# ---------------------------------------------------------------------------
# Tool functions — modelled on Red_V2 agent.py
# ---------------------------------------------------------------------------
def _truncate(text: str, limit: int = 12_000) -> str:
    if len(text) <= limit:
        return text
    return text[:limit] + f"\n...[truncated {len(text) - limit} chars]"


def tool_run_shell(command: str, workdir: str | Path,
                   rpc_url: str | None = None) -> str:
    """Execute a shell command in the workspace."""
    global LAST_FORGE_TEST_OUTPUT
    _log(f"shell: {command[:200]}")
    workdir = str(workdir)
    # ──── Path sandbox check ────
    allowed, reject_reason = _is_shell_command_allowed(command)
    if not allowed:
        _log(f"REJECTED shell command: {reject_reason}")
        return reject_reason

    # Reject heredocs
    if "<<" in command and ("EOF" in command or "HEREDOC" in command):
        return "ERROR: Heredoc syntax (<<) is not allowed. Use printf or echo instead."

    # Block shell access to pre-written answer files
    forbidden_shell_files = {"FlawVerifier.sol", "ExploitPOC.t.sol", "Counter.sol"}
    for fname in forbidden_shell_files:
        if fname in command:
            return f"Command blocked: access to {fname} is forbidden to prevent answer leakage."
    # Allow cd into workspace before forge — strip the cd and run directly
    if "forge" in command and re.search(r'\bcd\s+\S', command):
        m = re.search(r'\bcd\s+(\S+)\s*(?:&&|;)\s*(.+)', command)
        if m:
            target_dir = os.path.normpath(m.group(1))
            rest_cmd = m.group(2).strip()
            workspace_norm = os.path.normpath(workdir)
            if target_dir == workspace_norm or target_dir.startswith(workspace_norm + os.sep):
                # cd to workspace or subdirectory — allow it, just skip the cd
                _log(f"agent cd'ing into workspace; running: {rest_cmd[:200]}")
                return tool_run_shell(rest_cmd, workdir, rpc_url)
        _log("WARN: agent is cd'ing away for forge command; rejecting")
        return (
            "ERROR: Do not cd to another directory for forge commands. "
            "Run forge from the current directory (the workspace)."
        )
    try:
        env = os.environ.copy()
        if "forge test" in command and rpc_url:
            env["AUDITHOUND_RPC_URL"] = rpc_url
        result = subprocess.run(
            command, shell=True, executable="/bin/bash",
            capture_output=True, text=True, timeout=180,
            cwd=workdir, env=env,
        )
        output = result.stdout
        if result.stderr:
            output += f"\nSTDERR:\n{result.stderr}"
        if "forge test" in command:
            LAST_FORGE_TEST_OUTPUT = output
        if result.returncode != 0:
            output = f"Exit code: {result.returncode}\n{output}"
        return _truncate(output, 16_000)
    except subprocess.TimeoutExpired:
        return "Command timed out after 180 seconds."
    except Exception as e:
        return f"Error: {type(e).__name__}: {e}"


def tool_read_file(path: str, workdir: str | Path) -> str:
    path = str(path)
    workdir = str(workdir)
    if not os.path.isabs(path):
        path = os.path.join(workdir, path)
    # ──── Path sandbox check ────
    if not _is_path_allowed(path):
        return (
            f"ERROR: Access denied — path is outside the sandbox: {path}. "
            "You may only read files within the current workspace or the "
            "target source directory. Use relative paths."
        )
    # Block pre-written answer files
    forbidden = {"FlawVerifier.sol", "ExploitPOC.t.sol", "Counter.sol"}
    if os.path.basename(path) in forbidden:
        return (
            f"[BLOCKED] {os.path.basename(path)} is blocked to prevent answer leakage. "
            "Write your own exploit code from scratch based on the finding description."
        )
    if not os.path.exists(path):
        return f"Error: File not found: {path}"
    try:
        with open(path, "r") as f:
            return f.read()
    except Exception as e:
        return f"Error reading file: {e}"


def tool_write_file(path: str, content: str, workdir: str | Path) -> str:
    path = str(path)
    workdir = str(workdir)
    if not os.path.isabs(path):
        path = os.path.join(workdir, path)
    # Reject writes outside the workspace
    norm_path = os.path.normpath(os.path.realpath(path))
    norm_workdir = os.path.normpath(os.path.realpath(workdir))
    if not norm_path.startswith(norm_workdir + os.sep) and norm_path != norm_workdir:
        return f"ERROR: Write denied - path {path} is outside workspace {workdir}."
    # Protect test files from modification
    test_dir = os.path.join(os.path.normpath(workdir), "test")
    normalized_path = os.path.normpath(path)
    if normalized_path.startswith(test_dir + os.sep) or normalized_path == test_dir:
        return f"ERROR: Cannot write to test/ directory. Do not modify test files."
    os.makedirs(os.path.dirname(path), exist_ok=True)
    try:
        with open(path, "w") as f:
            f.write(content)
        return f"Successfully wrote {len(content.encode('utf-8'))} bytes to {path}"
    except Exception as e:
        return f"Error writing file: {e}"


def tool_run_slither(target: str, workdir: str | Path) -> str:
    workdir = str(workdir)
    slither_bin = shutil.which("slither")
    if not slither_bin:
        return "Slither not found in PATH. Install with: pip3 install slither-analyzer"
    if not os.path.isabs(target):
        target = os.path.join(workdir, target)
    try:
        result = subprocess.run(
            ["slither", target, "--print", "human-summary"],
            cwd=workdir, capture_output=True, text=True, timeout=120,
        )
        out = result.stdout
        if result.stderr:
            out += f"\nSTDERR:\n{result.stderr[:2000]}"
        return _truncate(out, 8000)
    except subprocess.TimeoutExpired:
        return "Slither timed out after 120 seconds."
    except Exception as e:
        return f"Error: {type(e).__name__}: {e}"


def tool_find_swap_path(token_in: str, token_out: str,
                        chain: str = "ethereum") -> str:
    tool = shutil.which("uniswap-smart-path")
    if not tool:
        return "uniswap-smart-path not found in PATH. Skipping."
    try:
        result = subprocess.run(
            [tool, "--token-in", token_in, "--token-out", token_out,
             "--chain", chain],
            capture_output=True, text=True, timeout=30,
        )
        out = result.stdout
        if result.stderr:
            out += f"\nSTDERR:\n{result.stderr[:1000]}"
        return out
    except subprocess.TimeoutExpired:
        return "find_swap_path timed out."
    except Exception as e:
        return f"Error: {type(e).__name__}: {e}"


def _first_addr(text: str) -> str:
    m = re.search(r"0x[a-fA-F0-9]{40}", text or "")
    return m.group(0) if m else ""


def tool_check_uniswap_v3_pools(token_a: str, token_b: str,
                                rpc_url: str) -> str:
    rpc_url = _rpc_url_from_env(rpc_url)
    factory = "0x1F98431c8aD98523631AE4a59f267346ea31F984"
    fee_tiers = [100, 500, 3000, 10000]
    lines = []
    for fee in fee_tiers:
        cmd = (
            f'cast call {factory} "getPool(address,address,uint24)(address)" '
            f'{token_a} {token_b} {fee} --rpc-url {rpc_url}'
        )
        try:
            proc = subprocess.run(
                cmd, shell=True, capture_output=True, text=True, timeout=30,
            )
            addr = _first_addr(proc.stdout.strip())
            if addr and addr.lower() != "0x0000000000000000000000000000000000000000":
                lines.append(f"V3 fee {fee} ({fee/10000}%): {addr}")
            else:
                lines.append(f"No V3 pool at fee {fee}")
        except Exception as e:
            lines.append(f"Fee {fee}: error - {e}")
    return "\n".join(lines) or "No pools found."


def tool_check_all_common_pools(token_address: str, rpc_url: str) -> str:
    rpc_url = _rpc_url_from_env(rpc_url)
    common_pairs = [
        ("WETH", "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"),
        ("USDC", "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"),
        ("USDT", "0xdAC17F958D2ee523a2206206994597C13D831ec7"),
        ("DAI", "0x6B175474E89094C44Da98b954EedeAC495271d0F"),
    ]
    v3_factory = "0x1F98431c8aD98523631AE4a59f267346ea31F984"
    v2_factory = "0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f"
    sushi_factory = "0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac"
    fee_tiers = [100, 500, 3000, 10000]

    found = []
    for pair_name, pair_addr in common_pairs:
        for fee in fee_tiers:
            try:
                cmd = (
                    f'cast call {v3_factory} '
                    f'"getPool(address,address,uint24)(address)" '
                    f'{token_address} {pair_addr} {fee} --rpc-url {rpc_url}'
                )
                proc = subprocess.run(
                    cmd, shell=True, capture_output=True, text=True, timeout=15,
                )
                addr = _first_addr(proc.stdout.strip())
                if addr and addr.lower() != "0x0000000000000000000000000000000000000000":
                    found.append(f"Uniswap V3 {pair_name} fee {fee}: {addr}")
            except Exception:
                pass
        for dex, factory_addr in [("Uniswap V2", v2_factory),
                                   ("SushiSwap", sushi_factory)]:
            try:
                cmd = (
                    f'cast call {factory_addr} '
                    f'"getPair(address,address)(address)" '
                    f'{token_address} {pair_addr} --rpc-url {rpc_url}'
                )
                proc = subprocess.run(
                    cmd, shell=True, capture_output=True, text=True, timeout=15,
                )
                addr = _first_addr(proc.stdout.strip())
                if addr and addr.lower() != "0x0000000000000000000000000000000000000000":
                    found.append(f"{dex} {pair_name}: {addr}")
            except Exception:
                pass
    if found:
        return "Found pools:\n" + "\n".join(found)
    return "No common liquidity pools found for this token."


def tool_scan_approvals(target_address: str, rpc_url: str, fork_block: str = "") -> str:
    """Scan for ERC20 allowances granted to the target contract.

    Checks common high-value ERC20 tokens for non-zero allowances where the
    target is the approved spender. If a victim still has an active allowance,
    the target can act as a transferFrom proxy to drain their tokens.
    """
    rpc = _rpc_url_from_env(rpc_url)
    common_tokens = [
        ("WETH", "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"),
        ("USDC", "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"),
        ("USDT", "0xdAC17F958D2ee523a2206206994597C13D831ec7"),
        ("DAI", "0x6B175474E89094C44Da98b954EedeAC495271d0F"),
        ("WBTC", "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599"),
        ("stETH", "0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84"),
    ]
    block_arg = f" --block {fork_block}" if fork_block else ""
    results: list[str] = []
    for name, token_addr in common_tokens:
        try:
            # Check target balance first — need a balance command
            bal_cmd = f'cast call {token_addr} "balanceOf(address)(uint256)" {target_address} --rpc-url {rpc}{block_arg}'
            proc = subprocess.run(bal_cmd, shell=True, capture_output=True, text=True, timeout=10)
            bal_str = proc.stdout.strip().split()[0] if proc.stdout.strip() else "0"
            target_bal = int(bal_str) if bal_str.isdigit() else 0

            # Scan recent blocks for Approval events where spender = target
            # Approval topic: keccak("Approval(address,address,uint256)") = 0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925
            # topic1 = owner (indexed), topic2 = spender (indexed)
            approval_topic = "0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925"
            # Pad target address to 32 bytes for topic matching
            padded_target = "0x" + target_address[2:].lower().rjust(64, "0")
            logs_cmd = (
                'cast logs --from-block 0 '
                f'--address {token_addr} '
                f'--topic2 {padded_target} '
                f'--rpc-url {rpc}{block_arg} 2>/dev/null | head -30'
            )
            proc2 = subprocess.run(logs_cmd, shell=True, capture_output=True, text=True, timeout=20)
            log_output = proc2.stdout.strip()

            # Parse log entries for owner addresses (topic1)
            owners: set[str] = set()
            if log_output:
                for line in log_output.split("\n"):
                    if "topic1" in line or "0x" in line:
                        parts = line.split()
                        for p in parts:
                            p = p.strip().strip('"').strip(",")
                            if p.startswith("0x") and len(p) == 66 and p[2:26] == "0" * 24:
                                addr = "0x" + p[26:]
                                if addr != "0x0000000000000000000000000000000000000000":
                                    owners.add(addr)
            # For tokens where logs aren't available, check the target's allowance directly
            # Use a common owner address heuristic
            if not owners:
                continue

            # Check current allowance for each owner at fork block
            for owner in list(owners)[:10]:
                try:
                    allow_cmd = (
                        f'cast call {token_addr} "allowance(address,address)(uint256)" '
                        f'{owner} {target_address} --rpc-url {rpc}{block_arg}'
                    )
                    proc3 = subprocess.run(allow_cmd, shell=True, capture_output=True, text=True, timeout=10)
                    allow_str = proc3.stdout.strip().split()[0] if proc3.stdout.strip() else "0"
                    allowance = int(allow_str) if allow_str.isdigit() else 0
                    if allowance > 0:
                        # Also check owner balance
                        bal_cmd2 = f'cast call {token_addr} "balanceOf(address)(uint256)" {owner} --rpc-url {rpc}{block_arg}'
                        proc4 = subprocess.run(bal_cmd2, shell=True, capture_output=True, text=True, timeout=10)
                        owner_bal_str = proc4.stdout.strip().split()[0] if proc4.stdout.strip() else "0"
                        owner_bal = int(owner_bal_str) if owner_bal_str.isdigit() else 0
                        drainable = min(allowance, owner_bal)
                        if drainable > 0:
                            results.append(
                                f"{name}: owner={owner} allowance={allowance} owner_bal={owner_bal} drainable={drainable}"
                            )
                except Exception:
                    pass
        except Exception:
            pass
    if results:
        return "Allowances found where target is spender:\n" + "\n".join(results)
    return (
        "No active allowances found on common tokens where the target is spender. "
        "Consider also checking custom tokens the target interacts with via "
        "'cast call <token> \"allowance(address,address)(uint256)\" <owner> <target>'."
    )


def tool_fetch_source(address: str, chain: str = "mainnet",
                      workdir: str | Path = "") -> str:
    api_key = (os.environ.get("ETHERSCAN_API_KEY", "").strip()
               or os.environ.get("CODEX_API_KEY", "").strip())
    if not api_key:
        return "Error: Missing ETHERSCAN_API_KEY. Set ETHERSCAN_API_KEY in env."
    chain_ids = {"mainnet": "1", "bsc": "56", "base": "8453"}
    chain_id = chain_ids.get(chain, "1")
    url = (
        "https://api.etherscan.io/v2/api"
        f"?chainid={chain_id}&module=contract&action=getsourcecode"
        f"&address={address}&apikey={api_key}"
    )
    import requests
    try:
        resp = requests.get(url, timeout=15)
        data = resp.json()
    except Exception as e:
        return f"Error fetching source: {e}"
    if data.get("status") != "1":
        return f"Etherscan lookup failed: {data.get('message', 'unknown')}"
    items = data.get("result") or []
    if not items:
        return "No source found."
    item = items[0]
    src = str(item.get("SourceCode") or "").strip()
    if not src:
        return "Source code is empty (verified contract might not exist)."
    out_dir = Path(str(workdir)) / "etherscan_auto" / address.lower()
    out_dir.mkdir(parents=True, exist_ok=True)
    if src.startswith("{{") and src.endswith("}}"):
        try:
            blob = json.loads(src[1:-1])
            sources = blob.get("sources", {})
            for rel, meta in sources.items():
                content = ""
                if isinstance(meta, dict):
                    content = str(meta.get("content") or "")
                else:
                    content = str(meta)
                target = out_dir / rel.strip().lstrip("/").replace("\\", "/")
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(content, encoding="utf-8")
        except Exception as e:
            (out_dir / "Contract.sol").write_text(src, encoding="utf-8")
    else:
        (out_dir / "Contract.sol").write_text(src, encoding="utf-8")
    return (f"Source fetched to {out_dir}/. "
            f"Run 'forge remappings' if needed to add imports.")


def tool_task_complete(summary: str, workdir: str | Path,
                       min_profit_wei: int = 0,
                       rpc_url: str | None = None) -> str:
    """Auto-verify by running forge test. Returns VERIFIED_SUCCESS or error."""
    global LAST_FORGE_TEST_OUTPUT
    workdir = str(workdir)
    _log(f"task_complete called: {summary[:200]}")

    # Check test file integrity
    test_file = Path(workdir) / "test" / "ExploitPOC.t.sol"
    if test_file.exists():
        content = test_file.read_text(encoding="utf-8")
        if "AUDITHOUND_PROFIT_WEI" not in content:
            return (
                "VERIFICATION FAILED: Test file has been tampered with. "
                "Missing AUDITHOUND_PROFIT_WEI logging. "
                "Do not modify test/ExploitPOC.t.sol - it is auto-generated."
            )
        if "testExploit" not in content:
            return (
                "VERIFICATION FAILED: Test file has been tampered with. "
                "Missing testExploit function. "
                "Do not modify test/ExploitPOC.t.sol - it is auto-generated."
            )

    # Run forge test with AUDITHOUND_RPC_URL set (required by test template)
    env = os.environ.copy()
    if rpc_url:
        env["AUDITHOUND_RPC_URL"] = rpc_url
    try:
        result = subprocess.run(
            ["forge", "test", "-vvv"],
            cwd=workdir, capture_output=True, text=True, timeout=300,
            env=env,
        )
        LAST_FORGE_TEST_OUTPUT = result.stdout
        test_output = result.stdout + "\n" + result.stderr
    except subprocess.TimeoutExpired:
        return "VERIFICATION FAILED: forge test timed out (300s)."
    except Exception as e:
        return f"VERIFICATION FAILED: {type(e).__name__}: {e}"

    rc = result.returncode
    if rc != 0:
        # Check for common failure patterns
        if "profit below threshold" in test_output.lower():
            return (
                "VERIFICATION FAILED: Test compiled but profit below threshold.\n"
                "Optimize your exploit to extract more value.\n"
                f"Test output (last 1000 chars):\n{test_output[-1000:]}"
            )
        return (
            f"VERIFICATION FAILED: forge test exited with code {rc}.\n"
            f"Test output (last 1500 chars):\n{test_output[-1500:]}"
        )

    # rc == 0 → parse profit
    profit_wei = None
    for line in test_output.splitlines():
        m = re.search(r"AUDITHOUND_PROFIT_WEI\s+(\d+)", line)
        if m:
            profit_wei = int(m.group(1))
            break
    if profit_wei is None:
        # Fallback: look for "Profit:" pattern
        for line in test_output.splitlines():
            m = re.search(r"Profit:\s*(\d+)", line)
            if m:
                profit_wei = int(m.group(1))
                break

    if profit_wei is not None and profit_wei > 0:
        _log(f"VERIFIED SUCCESS: profit={profit_wei} wei")
        return "VERIFIED_SUCCESS"

    # Check if profit_any exists
    profit_any = None
    for line in test_output.splitlines():
        m = re.search(r"AUDITHOUND_PROFIT_ANY\s+(\d+)", line)
        if m:
            profit_any = int(m.group(1))
            break
    if profit_any is not None and profit_any > 0:
        _log(f"VERIFIED SUCCESS: profit_any={profit_any}")
        return "VERIFIED_SUCCESS"

    return (
        "VERIFICATION FAILED: Test passed but no profit detected.\n"
        "Make sure your exploit logs profit using:\n"
        "    emit log_named_uint(\"AUDITHOUND_PROFIT_WEI\", profit);\n"
        f"Test output (last 1000 chars):\n{test_output[-1000:]}"
    )


# ---------------------------------------------------------------------------
# TOOLS list — Red_V2-style descriptions
# ---------------------------------------------------------------------------
TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "run_shell_command",
            "description": "Execute a shell command (forge, cast, etc.) in the workspace.",
            "parameters": {
                "type": "object",
                "properties": {
                    "command": {
                        "type": "string",
                        "description": "The shell command to execute"
                    }
                },
                "required": ["command"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "read_file",
            "description": "Read the content of a file (absolute path or relative to workspace).",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "Path to the file"
                    }
                },
                "required": ["path"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "write_file",
            "description": "Write content to a file. Use this to modify src/FlawVerifier.sol.",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "Path to the file"
                    },
                    "content": {
                        "type": "string",
                        "description": "Content to write"
                    }
                },
                "required": ["path", "content"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "run_slither",
            "description": "Run Slither static analysis on a Solidity contract or directory.",
            "parameters": {
                "type": "object",
                "properties": {
                    "target": {
                        "type": "string",
                        "description": "Path to contract file or directory"
                    }
                },
                "required": ["target"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "find_swap_path",
            "description": "Find optimal DEX swap path using uniswap-smart-path tool.",
            "parameters": {
                "type": "object",
                "properties": {
                    "token_in": {
                        "type": "string",
                        "description": "Input token address"
                    },
                    "token_out": {
                        "type": "string",
                        "description": "Output token address"
                    },
                    "chain": {
                        "type": "string",
                        "description": "Chain name (mainnet, bsc, base)", "default": "ethereum"
                    }
                },
                "required": ["token_in", "token_out"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "check_uniswap_v3_pools",
            "description": "Check ALL Uniswap V3 pool fee tiers (100, 500, 3000, 10000) for a token pair.",
            "parameters": {
                "type": "object",
                "properties": {
                    "token_a": {
                        "type": "string",
                        "description": "First token address"
                    },
                    "token_b": {
                        "type": "string",
                        "description": "Second token address (usually WETH)"
                    },
                    "rpc_url": {
                        "type": "string",
                        "description": "RPC URL",
                        "default": "http://127.0.0.1:8545"
                    }
                },
                "required": ["token_a", "token_b"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "check_all_common_pools",
            "description": "SUPER EFFICIENT! Check ALL common DEX pairs (WETH, USDC, USDT, DAI) across Uniswap V2, V3 (all fee tiers), and SushiSwap in one call. Use this FIRST before checking individual pairs to save time!",
            "parameters": {
                "type": "object",
                "properties": {
                    "token_address": {
                        "type": "string",
                        "description": "The target token address"
                    },
                    "rpc_url": {
                        "type": "string",
                        "description": "RPC URL", "default": "http://127.0.0.1:8545"
                    }
                },
                "required": ["token_address"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "fetch_implementation_source",
            "description": "Fetch verified source code from Etherscan for a proxy implementation or any contract.",
            "parameters": {
                "type": "object",
                "properties": {
                    "address": {
                        "type": "string",
                        "description": "Contract address to fetch source for"
                    },
                    "chain": {
                        "type": "string",
                        "description": "Chain name (mainnet, bsc, base)", "default": "mainnet"
                    }
                },
                "required": ["address"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "task_complete",
            "description": "Call this ONLY after you have run forge test -vvv and verified profit. This function will AUTO-VERIFY by re-running the test. If verification fails, your completion will be REJECTED and you must fix the exploit.",
            "parameters": {
                "type": "object",
                "properties": {
                    "summary": {
                        "type": "string",
                        "description": "Summary of the exploit and verified profit amount"
                    }
                },
                "required": ["summary"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "scan_approvals",
            "description": "Scan common ERC20 tokens for allowances where the target contract is the approved spender. If victims still have active allowances, the target can drain their tokens via transferFrom. Use this to find alternative profit sources when the target itself holds no assets.",
            "parameters": {
                "type": "object",
                "properties": {
                    "target_address": {
                        "type": "string",
                        "description": "The target contract address to check as spender"
                    },
                    "rpc_url": {
                        "type": "string",
                        "description": "RPC URL", "default": "http://127.0.0.1:8545"
                    },
                    "fork_block": {
                        "type": "string",
                        "description": "Fork block number"
                    }
                },
                "required": ["target_address"],
                "additionalProperties": False,
            },
        },
    },
]

TOOL_DISPATCH = {
    "run_shell_command": tool_run_shell,
    "read_file": tool_read_file,
    "write_file": tool_write_file,
    "run_slither": tool_run_slither,
    "find_swap_path": tool_find_swap_path,
    "check_uniswap_v3_pools": tool_check_uniswap_v3_pools,
    "check_all_common_pools": tool_check_all_common_pools,
    "fetch_implementation_source": tool_fetch_source,
    "task_complete": tool_task_complete,
}


# ---------------------------------------------------------------------------
# System Prompt — Red_V2-style phased workflow
# ---------------------------------------------------------------------------
SYSTEM_PROMPT = """You are an expert Smart Contract Security Researcher and Exploit Developer.

## Your Mission
Exploit a vulnerability in the target smart contract to generate positive profit.
The vulnerability findings are provided in the user message as reference material.
Use them as a starting point, but verify and adapt based on actual on-chain state.

**Finding priority: Focus on Critical and High severity findings first.**
Only reference Medium findings if the higher-severity paths are clearly infeasible at the current fork state.

## Your Working Environment
- **Foundry Project**: Current working directory
- **Your Contract**: `src/FlawVerifier.sol` — implement `executeOnOpportunity()` method
- **Test File**: `test/ExploitPOC.t.sol` — use `forge test -vvv` to validate
- **Initial Funding**: Native tokens are pre-seeded to the verifier contract
- **RPC**: The anvil fork is running at the provided RPC URL
- **IMPORTANT**: When running `forge test`, always set `AUDITHOUND_RPC_URL=<rpc_url>` as an env var (the test file reads it to connect to the fork)
- **IMPORTANT**: Always run forge and cast commands from the current directory. Do NOT use `cd` to change away — use absolute paths to read source files instead.

## Available Tools

1. `run_shell_command`: Execute shell commands (forge, cast, slither, grep, etc.)
2. `read_file`: Read file contents
3. `write_file`: Write/modify files (use this to edit src/FlawVerifier.sol)
4. `run_slither`: Run Slither static analysis on a contract directory
5. `find_swap_path`: Find optimal DEX swap path using uniswap-smart-path
6. `check_all_common_pools`: **USE THIS FIRST for liquidity checks!** Checks all major DEX pairs in one call
7. `check_uniswap_v3_pools`: Check all Uniswap V3 fee tiers for a specific pair
8. `fetch_implementation_source`: Fetch verified source from Etherscan
9. `scan_approvals`: **Scan for allowances where target is spender!** If the target itself holds no assets, check who has approved it to spend — the target can drain third-party tokens via transferFrom.
10. `task_complete`: **Call ONLY when forge test passes with verified profit.** Auto-verifies by re-running the test.

## MANDATORY WORKFLOW

### Phase 1: Quick Analysis (MAX 8 steps)
You have at most 8 steps for analysis — use them efficiently:
1. Read the finding titles and pick the best Critical/High finding
2. Read the relevant source code sections
3. Use 1-2 cast commands to verify the exploit path is viable
4. Plan your attack

**After 8 steps you MUST move to Phase 2, even if analysis is incomplete.**

### Phase 2: Exploit & Iterate
1. Write `executeOnOpportunity()` in `src/FlawVerifier.sol`
2. Add helper functions, interfaces, state variables as needed
3. Run `AUDITHOUND_RPC_URL=<rpc> forge test -vvv`
4. Read errors, fix code, retest
5. Repeat until test passes with positive profit

### Phase 3: Complete
Call `task_complete` only when forge test passes with verified profit.

## Critical Constraints
- **NO cheatcodes** in src/FlawVerifier.sol: no vm.store, vm.etch, vm.mockCall, vm.prank, vm.startPrank, arbitrary balance injection, or arbitrary storage writes
- **NO mock contracts** — the exploit must work against the REAL on-chain contract
- **DO NOT deploy custom ERC20 tokens** to manufacture profit
- **DO NOT modify `test/ExploitPOC.t.sol`** — the test harness is auto-generated. If you modify it, `task_complete` will detect the change and reject your completion.
- **VERIFY all external contract addresses with `cast` before using them.** Do NOT rely on your training data for contract addresses. Example: `cast call <pool> "assetOf(address)(address)" <token> --rpc-url <rpc>` to look up aToken addresses.
- Profit must come from actual exploit of the target contract, not from setup capital
- Seeded capital is setup capital and must not be counted as profit
- Flash loans and realistic public on-chain actions are allowed

## Technical Notes
1. Always approve tokens before swapping: `IERC20(token).approve(router, type(uint256).max);`
2. Convert all profits to a measurable form (native token or known ERC20)
3. The test checks for AUDITHOUND_PROFIT_WEI / AUDITHOUND_PROFIT_ANY in console logs
4. Multi-hop swap paths (e.g., TOKEN → USDC → WETH) often have better liquidity than direct pairs
"""


# ---------------------------------------------------------------------------
# Agent loop — unbounded, like Red_V2
# ---------------------------------------------------------------------------
class AgentState:
    """Shared mutable state for tool dispatch."""
    def __init__(self, workdir: str, rpc_url: str, min_profit_wei: int):
        self.workdir = workdir
        self.rpc_url = rpc_url
        self.min_profit_wei = min_profit_wei
        self.blocked_count = 0


def dispatch_tool(tc, state: AgentState) -> str:
    """Execute a single tool call and return result string."""
    name = tc.function.name
    raw_args = tc.function.arguments or "{}"
    try:
        args = json.loads(raw_args)
    except json.JSONDecodeError:
        return f'ERROR: invalid JSON arguments: {raw_args[:200]}'

    # Log the tool call to stderr (captured as agent_stderr_attemptN.log)
    summary = _tool_call_summary(name, args, 120)
    _log(f"tool call [{name}]: {summary}")

    if name == "run_shell_command":
        cmd = str(args.get("command") or "")
        if not cmd:
            return "ERROR: missing 'command'"
        return tool_run_shell(cmd, state.workdir, state.rpc_url)

    elif name == "read_file":
        path = str(args.get("path") or "")
        if not path:
            return "ERROR: missing 'path'"
        return tool_read_file(path, state.workdir)

    elif name == "write_file":
        path = str(args.get("path") or "")
        content = str(args.get("content") or "")
        if not path:
            return "ERROR: missing 'path'"
        return tool_write_file(path, content, state.workdir)

    elif name == "run_slither":
        target = str(args.get("target") or ".")
        return tool_run_slither(target, state.workdir)

    elif name == "find_swap_path":
        token_in = str(args.get("token_in") or "")
        token_out = str(args.get("token_out") or "")
        chain = str(args.get("chain") or "ethereum")
        if not token_in or not token_out:
            return "ERROR: missing token_in or token_out"
        return tool_find_swap_path(token_in, token_out, chain)

    elif name == "check_uniswap_v3_pools":
        token_a = str(args.get("token_a") or "")
        token_b = str(args.get("token_b") or "")
        rpc = str(args.get("rpc_url") or state.rpc_url)
        if not token_a or not token_b:
            return "ERROR: missing token_a or token_b"
        return tool_check_uniswap_v3_pools(token_a, token_b, rpc)

    elif name == "check_all_common_pools":
        token_addr = str(args.get("token_address") or "")
        rpc = str(args.get("rpc_url") or state.rpc_url)
        if not token_addr:
            return "ERROR: missing token_address"
        return tool_check_all_common_pools(token_addr, rpc)

    elif name == "scan_approvals":
        target = str(args.get("target_address") or "")
        rpc = str(args.get("rpc_url") or state.rpc_url)
        fork_block = str(args.get("fork_block") or "")
        if not target:
            return "ERROR: missing target_address"
        return tool_scan_approvals(target, rpc, fork_block)

    elif name == "fetch_implementation_source":
        addr = str(args.get("address") or "")
        chain = str(args.get("chain") or "mainnet")
        if not addr:
            return "ERROR: missing 'address'"
        return tool_fetch_source(addr, chain, state.workdir)

    elif name == "task_complete":
        summary = str(args.get("summary") or args.get("message") or "")
        return tool_task_complete(summary, state.workdir,
                                  state.min_profit_wei, state.rpc_url)

    else:
        return f"ERROR: unknown tool '{name}'"


def run_agent_loop(
    client: OpenAI,
    model: str,
    prompt: str,
    workdir: str,
    rpc_url: str,
    min_profit_wei: int = 0,
    log_dir: str | None = None,
    max_iterations: int = AGENT_MAX_ITERATIONS,
    time_budget_seconds: int = AGENT_TIME_BUDGET_SECONDS,
) -> str:
    """Run the Red_V2-style unbounded agent loop.

    Returns the final assistant content (or "VERIFIED_SUCCESS" marker).
    Raises RuntimeError if max_iterations exceeded or time budget exhausted.
    """
    state = AgentState(workdir, rpc_url, min_profit_wei)
    start_time = time.time()
    _has_written_code = False
    _has_run_test = False
    _test_passed = False
    _written_code_step = -1
    _first_test_step = -1
    _last_test_step = -1
    _force_test_sent = False  # already told agent to test?
    _force_retest_sent = False  # already told agent to retest?

    messages: list[dict] = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": prompt},
    ]

    for step in range(max_iterations):
        # Check time budget
        elapsed = time.time() - start_time
        if elapsed > time_budget_seconds:
            remaining_min = (time_budget_seconds - elapsed) / 60
            _log(f"time budget exhausted: {elapsed:.0f}s used, budget={time_budget_seconds}s")
            raise RuntimeError(
                f"Agent time budget ({time_budget_seconds // 60} min) exhausted "
                f"after {step} steps ({elapsed:.0f}s). "
                f"Remaining: {remaining_min:.0f} min."
            )
        if step > 0 and step % 5 == 0:
            elapsed_min = elapsed / 60
            remaining_min = (time_budget_seconds - elapsed) / 60
            _log(f"progress: step={step} elapsed={elapsed_min:.0f}min remaining={remaining_min:.0f}min")

        _log(f"agent step {step}")

        # ---- API call ----
        try:
            resp = client.chat.completions.create(
                model=model,
                messages=messages,
                tools=TOOLS,
                tool_choice="auto",
            )
        except Exception as exc:
            _log(f"API error: {type(exc).__name__}: {exc}")
            raise RuntimeError(f"API call failed after {step} steps: {exc}")

        msg = resp.choices[0].message
        tool_calls = getattr(msg, "tool_calls", None) or []
        content = msg.content or getattr(msg, "reasoning_content", None) or ""

        # ---- Logging ----
        if log_dir:
            Path(log_dir).mkdir(parents=True, exist_ok=True)
            log_entry = {
                "ts": datetime.now(timezone.utc).isoformat(),
                "step": step,
                "tool_calls": len(tool_calls),
                "content_len": len(content),
            }
            with open(Path(log_dir) / "agent_events.jsonl", "a") as f:
                f.write(json.dumps(log_entry) + "\n")

        # ---- Tool processing ----
        if tool_calls:
            assistant_msg: dict = {
                "role": "assistant",
                "content": content,
                "tool_calls": [],
            }
            for tc in tool_calls:
                assistant_msg["tool_calls"].append({
                    "id": tc.id,
                    "type": "function",
                    "function": {
                        "name": tc.function.name,
                        "arguments": tc.function.arguments,
                    },
                })
            messages.append(assistant_msg)

            for tc in tool_calls:
                result = dispatch_tool(tc, state)
                # Log tool result to stderr (captured as agent_stderr_attemptN.log)
                _log(f"tool result [{tc.function.name}]: {len(result)} chars, "
                     f"first={result[:100].strip()!r}")
                # Track progress
                if tc.function.name == "write_file" and "FlawVerifier.sol" in (tc.function.arguments or ""):
                    if not _has_written_code:
                        _written_code_step = step
                    _has_written_code = True
                if tc.function.name == "run_shell_command" and "forge test" in (tc.function.arguments or ""):
                    if not _has_run_test:
                        _first_test_step = step
                    _has_run_test = True
                    _last_test_step = step
                    # Detect forge test passing: sets _test_passed to re-enable analysis tools
                    if not _test_passed and "AUDITHOUND_PROFIT" in result and "testExploit" in result and "[PASS]" in result:
                        _test_passed = True
                        _log(f"forge test PASSED at step {step}")
                # Check for VERIFIED_SUCCESS from task_complete
                if tc.function.name == "task_complete" and "VERIFIED_SUCCESS" in result:
                    _log("Agent completed successfully!")
                    return "VERIFIED_SUCCESS"
                messages.append({
                    "role": "tool",
                    "tool_call_id": tc.id,
                    "content": result,
                })

            # ---- Periodic forge test: every 5 steps after code exists ----
            if step >= MAX_ANALYSIS_STEPS and _has_written_code and step > _written_code_step + 2 and step % 5 == 0:
                _log(f"periodic forge test at step {step}")
                forge_cmd = f"AUDITHOUND_RPC_URL={rpc_url} forge test -vvv 2>&1"
                test_output = tool_run_shell(forge_cmd, workdir, rpc_url)
                if "AUDITHOUND_PROFIT_WEI" in test_output and "testExploit" in test_output and "FAIL" not in test_output and "revert" not in test_output.lower():
                    _test_passed = True
                    _log("periodic forge test PASSED, completing!")
                    return "VERIFIED_SUCCESS"

            # ---- Phase transition: Analysis → Exploit ----

            # ---- Phase transition: Analysis → Exploit ----
            if step == MAX_ANALYSIS_STEPS - 1 and not _has_written_code:
                _log("analysis phase complete, forcing transition to exploit phase")
                messages.append({
                    "role": "user",
                    "content": (
                        "[PHASE TRANSITION] Analysis phase is over. "
                        "Stop investigating. Now implement the exploit in src/FlawVerifier.sol, "
                        "run forge test -vvv, and call task_complete when it passes."
                    )
                })
            continue

        # ---- No tool calls — model produced final text ----
        # If it was a task_complete, check content
        if "VERIFIED_SUCCESS" in content or "verified" in content.lower():
            # But don't trust it — task_complete would have returned marker
            pass

        # If model responds without tool calls and no task_complete,
        # push it back on track
        messages.append({
            "role": "user",
            "content": (
                "You did not call any tools. Continue working on the exploit. "
                "Use run_shell_command and write_file to build and test "
                "your exploit, then call task_complete when forge test passes."
            ),
        })

    raise RuntimeError(f"Agent did not complete after {max_iterations} iterations")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Red_V2-style agent for AuditHoundV2 validation.")
    parser.add_argument("--workdir", required=True)
    parser.add_argument("--model", default=os.environ.get("CODEX_MODEL",
                                                          "deepseek-v4-pro"))
    parser.add_argument("--provider", default="deepseek",
                        choices=("codex", "deepseek", "claude"))
    parser.add_argument("--reasoning-effort", default="medium")
    parser.add_argument("--prompt-file", required=True)
    parser.add_argument("--rpc-url", default="http://127.0.0.1:8545")
    parser.add_argument("--log-dir", default="")
    parser.add_argument("--min-profit-wei", type=int, default=0)
    parser.add_argument("--max-iterations", type=int, default=AGENT_MAX_ITERATIONS)
    parser.add_argument("--time-budget-minutes", type=int, default=AGENT_TIME_BUDGET_SECONDS // 60)
    parser.add_argument("--target-root", default="", help="Target source directory (for path sandbox).")
    args = parser.parse_args()

    # Read prompt
    prompt_path = Path(args.prompt_file).expanduser().resolve()
    prompt = prompt_path.read_text(encoding="utf-8")
    if not prompt.strip():
        print("ERROR: prompt is empty", file=sys.stderr)
        return 1

    workdir = Path(args.workdir).expanduser().resolve()
    if not workdir.exists():
        print(f"ERROR: workdir does not exist: {workdir}", file=sys.stderr)
        return 1

    log_dir = str(Path(args.log_dir).expanduser().resolve()) if args.log_dir else None

    # Set up client
    client, resolved_model = _client_and_model(args.provider, args.model)
    _log(f"provider={args.provider} model={resolved_model} workdir={workdir}")

    try:
        result = run_agent_loop(
            client=client,
            model=resolved_model,
            prompt=prompt,
            workdir=str(workdir),
            rpc_url=args.rpc_url,
            min_profit_wei=args.min_profit_wei,
            log_dir=log_dir,
            max_iterations=args.max_iterations,
            time_budget_seconds=args.time_budget_minutes * 60,
        )
    except RuntimeError as e:
        print(f"AGENT FAILED: {e}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("\nAgent interrupted by user.", file=sys.stderr)
        return 1

    if result != "VERIFIED_SUCCESS":
        print(f"AGENT FAILED: unexpected result: {result[:200]}", file=sys.stderr)
        return 1

    # On success: read the final FlawVerifier.sol and print to stdout
    flayer_path = workdir / "src" / "FlawVerifier.sol"
    if flayer_path.exists():
        print(flayer_path.read_text(encoding="utf-8"))
        return 0
    else:
        print("ERROR: src/FlawVerifier.sol not found after agent completion",
              file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
