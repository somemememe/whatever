#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path

from openai import OpenAI
def _truncate(text: str, limit: int = 12_000) -> str:
    if len(text) <= limit:
        return text
    return text[:limit] + f"\n...[truncated {len(text) - limit} chars]"


def _safe_path(base_dir: Path, raw_path: str) -> Path:
    path = Path(raw_path).expanduser()
    if path.is_absolute():
        return path.resolve()
    return (base_dir / path).resolve()


def _read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _write_text(path: Path, content: str) -> int:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    return len(content.encode("utf-8"))


def _resolve_api_key(provider: str) -> str:
    if provider == "deepseek":
        env_keys = ["DEEPSEEK_API_KEY", "OPENAI_API_KEY", "CODEX_API_KEY", "AUDITHOUND_OPENAI_API_KEY"]
    else:
        env_keys = ["OPENAI_API_KEY", "CODEX_API_KEY", "AUDITHOUND_OPENAI_API_KEY"]
    for key in env_keys:
        value = os.environ.get(key, "").strip()
        if value:
            return value
    raise SystemExit(
        "No API key found. Set OPENAI_API_KEY, CODEX_API_KEY, AUDITHOUND_OPENAI_API_KEY, or DEEPSEEK_API_KEY."
    )


def _resolve_model_name(provider: str, model: str) -> str:
    requested = str(model or "").strip()
    provider = provider.lower().strip()
    if provider != "deepseek":
        return requested

    alias = requested.lower()
    if alias in {"", "deepseek4.0", "deepseek-4.0", "deepseek-v4", "deepseek-v4-flash", "deepseek4", "deepseek-reasoner"}:
        env_model = (
            os.environ.get("AUDITHOUND_DEEPSEEK_MODEL", "").strip()
            or os.environ.get("DEEPSEEK_MODEL", "").strip()
        )
        return env_model or "deepseek-reasoner"
    return requested


def _client_and_model(provider: str, model: str) -> tuple[OpenAI, str]:
    provider = provider.lower().strip()
    api_key = _resolve_api_key(provider)
    base_url = None
    if provider == "deepseek":
        base_url = os.environ.get("DEEPSEEK_BASE_URL", "https://api.deepseek.com/v1")
    else:
        base_url = os.environ.get("OPENAI_BASE_URL") or None
    client = OpenAI(api_key=api_key, base_url=base_url)
    return client, _resolve_model_name(provider, model)


def _tool_shell(base_dir: Path, args: dict) -> dict:
    command = str(args.get("command") or "").strip()
    if not command:
        raise ValueError("run_shell_command requires 'command'")
    blocked_patterns = ["find /", "sudo ", "rm -rf /", "mkfs.", ":(){:|:&};:"]
    lowered = command.lower()
    for pat in blocked_patterns:
        if pat in lowered:
            return {
                "cwd": str(base_dir),
                "command": command,
                "returncode": 126,
                "stdout": "",
                "stderr": f"blocked command pattern: {pat}. Restrict exploration to workspace paths only.",
            }
    cwd = args.get("cwd")
    workdir = _safe_path(base_dir, str(cwd)) if cwd else base_dir
    timeout = float(args.get("timeout_seconds") or 180.0)
    proc = subprocess.run(
        command,
        cwd=str(workdir),
        shell=True,
        executable="/bin/bash",
        capture_output=True,
        text=True,
        timeout=timeout,
        check=False,
    )
    return {
        "cwd": str(workdir),
        "command": command,
        "returncode": proc.returncode,
        "stdout": _truncate(proc.stdout),
        "stderr": _truncate(proc.stderr),
    }


def _tool_read_file(base_dir: Path, args: dict) -> dict:
    raw_path = str(args.get("path") or "").strip()
    if not raw_path:
        raise ValueError("read_file requires 'path'")
    path = _safe_path(base_dir, raw_path)
    return {
        "path": str(path),
        "exists": path.exists(),
        "content": _truncate(_read_text(path) if path.exists() else ""),
    }


def _tool_write_file(base_dir: Path, args: dict) -> dict:
    raw_path = str(args.get("path") or "").strip()
    if not raw_path:
        raise ValueError("write_file requires 'path'")
    content = str(args.get("content") or "")
    path = _safe_path(base_dir, raw_path)
    bytes_written = _write_text(path, content)
    return {"path": str(path), "bytes_written": bytes_written}


def _tool_run_slither(base_dir: Path, args: dict) -> dict:
    slither_bin = shutil.which("slither")
    if not slither_bin:
        return {"error": "slither not found in PATH"}
    target = str(args.get("target") or ".").strip() or "."
    target_path = _safe_path(base_dir, target)
    extra_args = args.get("args") or []
    if not isinstance(extra_args, list):
        extra_args = []
    cmd = [slither_bin, str(target_path)] + [str(item) for item in extra_args if str(item).strip()]
    proc = subprocess.run(
        cmd,
        cwd=str(target_path if target_path.is_dir() else base_dir),
        capture_output=True,
        text=True,
        check=False,
    )
    return {
        "target": str(target_path),
        "returncode": proc.returncode,
        "stdout": _truncate(proc.stdout),
        "stderr": _truncate(proc.stderr),
    }


def _tool_find_swap_path(base_dir: Path, args: dict) -> dict:
    token_in = str(args.get("token_in") or "").strip()
    token_out = str(args.get("token_out") or "").strip()
    chain = str(args.get("chain") or "ethereum").strip()
    tool = shutil.which("uniswap-smart-path")
    if not tool:
        return {
            "token_in": token_in,
            "token_out": token_out,
            "chain": chain,
            "error": "uniswap-smart-path not found",
        }
    cmd = [tool, "--token-in", token_in, "--token-out", token_out, "--chain", chain]
    proc = subprocess.run(cmd, cwd=str(base_dir), capture_output=True, text=True, check=False)
    return {
        "token_in": token_in,
        "token_out": token_out,
        "chain": chain,
        "returncode": proc.returncode,
        "stdout": _truncate(proc.stdout),
        "stderr": _truncate(proc.stderr),
    }


def _first_addr(text: str) -> str:
    import re
    m = re.search(r"0x[a-fA-F0-9]{40}", text or "")
    return m.group(0) if m else ""


def _tool_check_uniswap_v3_pools(base_dir: Path, args: dict) -> dict:
    token_a = str(args.get("token_a") or "").strip()
    token_b = str(args.get("token_b") or "").strip()
    rpc_url = str(args.get("rpc_url") or os.environ.get("ETH_RPC_URL") or os.environ.get("RPC_URL") or "").strip()
    if not rpc_url:
        return {"error": "missing rpc_url", "token_a": token_a, "token_b": token_b}
    fee_tiers = [100, 500, 3000, 10000]
    factory = "0x1F98431c8aD98523631AE4a59f267346ea31F984"
    found = []
    lines = []
    for fee in fee_tiers:
        cmd = [
            "cast", "call", factory, "getPool(address,address,uint24)(address)",
            token_a, token_b, str(fee), "--rpc-url", rpc_url
        ]
        proc = subprocess.run(cmd, cwd=str(base_dir), capture_output=True, text=True, check=False)
        addr = _first_addr(proc.stdout.strip())
        if addr and addr.lower() != "0x0000000000000000000000000000000000000000":
            found.append({"fee": fee, "pool": addr})
            lines.append(f"V3 fee {fee}: {addr}")
    return {"token_a": token_a, "token_b": token_b, "found_pools": found, "summary": "\n".join(lines)}


def _tool_check_all_common_pools(base_dir: Path, args: dict) -> dict:
    token_address = str(args.get("token_address") or "").strip()
    rpc_url = str(args.get("rpc_url") or os.environ.get("ETH_RPC_URL") or os.environ.get("RPC_URL") or "").strip()
    if not rpc_url:
        return {"error": "missing rpc_url", "token_address": token_address}
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
            cmd = ["cast", "call", v3_factory, "getPool(address,address,uint24)(address)", token_address, pair_addr, str(fee), "--rpc-url", rpc_url]
            proc = subprocess.run(cmd, cwd=str(base_dir), capture_output=True, text=True, check=False)
            addr = _first_addr(proc.stdout.strip())
            if addr and addr.lower() != "0x0000000000000000000000000000000000000000":
                found.append({"dex": "Uniswap V3", "pair": pair_name, "fee": fee, "pool": addr})
        for dex, factory, sig in [
            ("Uniswap V2", v2_factory, "getPair(address,address)(address)"),
            ("SushiSwap", sushi_factory, "getPair(address,address)(address)"),
        ]:
            cmd = ["cast", "call", factory, sig, token_address, pair_addr, "--rpc-url", rpc_url]
            proc = subprocess.run(cmd, cwd=str(base_dir), capture_output=True, text=True, check=False)
            addr = _first_addr(proc.stdout.strip())
            if addr and addr.lower() != "0x0000000000000000000000000000000000000000":
                found.append({"dex": dex, "pair": pair_name, "pool": addr})
    return {"token_address": token_address, "found_pools": found, "count": len(found)}


def _curl_json(url: str, timeout_seconds: float = 20.0) -> dict:
    proc = subprocess.run(
        ["curl", "-ksS", "--max-time", str(timeout_seconds), url],
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"curl failed rc={proc.returncode}: {proc.stderr.strip()}")
    return json.loads(proc.stdout)


def _write_etherscan_source(item: dict, out_dir: Path) -> dict:
    src = str(item.get("SourceCode") or "").strip()
    out_dir.mkdir(parents=True, exist_ok=True)
    files_written = 0

    if src.startswith("{{") and src.endswith("}}"):
        blob = json.loads(src[1:-1])
        sources = blob.get("sources", {})
        if not isinstance(sources, dict):
            sources = {}
        for rel, meta in sources.items():
            if not isinstance(rel, str) or not rel.strip():
                continue
            rel_path = rel.strip().replace("\\", "/").lstrip("/")
            rel_path = str(Path(rel_path))
            if rel_path in {"", "."} or rel_path.startswith(".."):
                continue
            content = ""
            if isinstance(meta, dict):
                content = str(meta.get("content") or "")
            else:
                content = str(meta)
            target = out_dir / rel_path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(content, encoding="utf-8")
            files_written += 1
    else:
        (out_dir / "Contract.sol").write_text(src, encoding="utf-8")
        files_written = 1

    meta = {
        "contract_name": item.get("ContractName"),
        "compiler": item.get("CompilerVersion"),
        "evm_version": item.get("EVMVersion"),
        "optimization": item.get("OptimizationUsed"),
        "runs": item.get("Runs"),
        "proxy": item.get("Proxy"),
        "implementation": item.get("Implementation"),
        "license_type": item.get("LicenseType"),
        "files_written": files_written,
    }
    (out_dir / "_etherscan_meta.json").write_text(json.dumps(meta, indent=2, ensure_ascii=False), encoding="utf-8")
    return meta | {"files_written": files_written, "out_dir": str(out_dir)}


def _tool_fetch_source(base_dir: Path, args: dict) -> dict:
    address = str(args.get("implementation_address") or args.get("address") or "").strip()
    if not address.startswith("0x") or len(address) != 42:
        raise ValueError("fetch_implementation_source requires a valid 'address'")
    chain_id = str(args.get("chain_id") or os.environ.get("AUDITHOUND_CHAIN_ID") or "1").strip()
    api_key = str(args.get("api_key") or os.environ.get("ETHERSCAN_API_KEY") or os.environ.get("CODEX_API_KEY") or "").strip()
    if not api_key:
        raise ValueError("fetch_implementation_source requires api_key or ETHERSCAN_API_KEY")
    out_dir_raw = str(args.get("out_dir") or "").strip()
    out_dir = _safe_path(base_dir, out_dir_raw) if out_dir_raw else (base_dir / "onchain_auto" / address.lower())
    url = (
        "https://api.etherscan.io/v2/api"
        f"?chainid={chain_id}&module=contract&action=getsourcecode"
        f"&address={address}&apikey={api_key}"
    )
    data = _curl_json(url)
    result = data.get("result")
    if data.get("status") != "1" or not isinstance(result, list) or not result:
        return {"error": "etherscan lookup failed", "response": data}
    item = result[0]
    if not isinstance(item, dict):
        return {"error": "unexpected etherscan payload", "response": data}
    meta = _write_etherscan_source(item, out_dir)
    return {
        "address": address.lower(),
        "chain_id": chain_id,
        "out_dir": str(out_dir),
        "meta": meta,
    }


def _tool_task_complete(base_dir: Path, args: dict) -> dict:
    summary = str(args.get("summary") or args.get("message") or "").strip()
    return {"completed": True, "summary": summary}


TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "run_shell_command",
            "description": "Run a shell command in the current working directory or a specified path.",
            "parameters": {
                "type": "object",
                "properties": {
                    "command": {"type": "string"},
                    "cwd": {"type": "string"},
                    "timeout_seconds": {"type": "number"},
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
            "description": "Read a local file and return its contents.",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {"type": "string"},
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
            "description": "Write content to a local file, creating parent directories if necessary.",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {"type": "string"},
                    "content": {"type": "string"},
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
            "description": "Run Slither on a target directory or file.",
            "parameters": {
                "type": "object",
                "properties": {
                    "target": {"type": "string"},
                    "args": {"type": "array", "items": {"type": "string"}},
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
            "description": "Find likely swap path candidates from token_in to token_out.",
            "parameters": {
                "type": "object",
                "properties": {
                    "token_in": {"type": "string"},
                    "token_out": {"type": "string"},
                    "chain": {"type": "string"},
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
            "description": "Check whether common Uniswap V3 fee-tier pools exist for token pair.",
            "parameters": {
                "type": "object",
                "properties": {
                    "token_a": {"type": "string"},
                    "token_b": {"type": "string"},
                    "rpc_url": {"type": "string"},
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
            "description": "Probe common AMM pools for a token.",
            "parameters": {
                "type": "object",
                "properties": {
                    "token_address": {"type": "string"},
                    "rpc_url": {"type": "string"},
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
            "description": "Fetch verified source from Etherscan and materialize it locally.",
            "parameters": {
                "type": "object",
                "properties": {
                    "implementation_address": {"type": "string"},
                    "address": {"type": "string"},
                    "chain_id": {"type": "string"},
                    "chain": {"type": "string"},
                    "api_key": {"type": "string"},
                    "out_dir": {"type": "string"},
                },
                "required": [],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "task_complete",
            "description": "Signal that the task is complete and provide a short summary.",
            "parameters": {
                "type": "object",
                "properties": {
                    "summary": {"type": "string"},
                    "message": {"type": "string"},
                },
                "additionalProperties": False,
            },
        },
    },
]


TOOL_DISPATCH = {
    "run_shell_command": _tool_shell,
    "read_file": _tool_read_file,
    "write_file": _tool_write_file,
    "run_slither": _tool_run_slither,
    "find_swap_path": _tool_find_swap_path,
    "check_uniswap_v3_pools": _tool_check_uniswap_v3_pools,
    "check_all_common_pools": _tool_check_all_common_pools,
    "fetch_implementation_source": _tool_fetch_source,
    "task_complete": _tool_task_complete,
}


def _system_prompt(mode: str) -> str:
    base = (
        "You are a security auditing agent with structured tool access. "
        "Use tools whenever they materially reduce uncertainty. "
        "Treat tools as real execution capabilities; when a tool is needed, call it rather than simulating the result. "
        "If the prompt asks for only Solidity or only JSON, your final assistant message must obey that format, "
        "but tool calls are still allowed internally."
    )
    if mode == "validation":
        return base + (
            " You are generating or repairing a Foundry exploit PoC; keep the final answer to the exact format requested by the prompt. "
            "Prioritize concrete exploitability and profit maximization, using tools iteratively to discover viable attack paths. "
            "Convergence policy: at most one short reconnaissance phase, then produce code. Avoid repeated filesystem exploration."
        )
    if mode == "finding":
        return base + " You are performing static or hybrid finding generation over the provided source scope."
    return base


def _print_tool(name: str, payload: dict) -> None:
    print(f"[tool:{name}] {json.dumps(payload, ensure_ascii=True)}", file=os.sys.stderr)


def _append_log(log_dir: Path | None, event: str, payload: dict) -> None:
    if log_dir is None:
        return
    log_dir.mkdir(parents=True, exist_ok=True)
    rec = {"ts": datetime.now(timezone.utc).isoformat(), "event": event, "payload": payload}
    with (log_dir / "tool_loop_events.jsonl").open("a", encoding="utf-8") as f:
        f.write(json.dumps(rec, ensure_ascii=False) + "\n")


def _run_tool_loop(client: OpenAI, model: str, prompt: str, mode: str, max_steps: int, base_dir: Path, log_dir: Path | None = None) -> str:
    messages: list[dict] = [
        {"role": "system", "content": _system_prompt(mode)},
        {"role": "user", "content": prompt},
    ]

    for step in range(max_steps):
        remaining_steps = max_steps - step
        _append_log(log_dir, "step_start", {"step": step, "remaining_steps": remaining_steps, "model": model, "mode": mode})
        if remaining_steps <= 3:
            # Red_V2-style convergence guard: force finalization instead of endlessly probing tools.
            messages.append(
                {
                    "role": "system",
                    "content": (
                        "You are near the tool-call budget limit. Do not call more tools unless absolutely required "
                        "for syntax correctness. Produce the final required output now."
                    ),
                }
            )
        try:
            _append_log(log_dir, "api_request_start", {"step": step})
            resp = client.chat.completions.create(
                model=model,
                messages=messages,
                tools=TOOLS,
                tool_choice="auto",
            )
            _append_log(log_dir, "api_request_ok", {"step": step})
        except Exception as exc:
            _append_log(log_dir, "api_request_error", {"step": step, "error": f"{type(exc).__name__}: {exc}"})
            raise RuntimeError(f"API call failed (model={model}): {type(exc).__name__}: {exc}")
        choice = resp.choices[0]
        msg = choice.message
        tool_calls = getattr(msg, "tool_calls", None) or []
        content = msg.content or ""

        if tool_calls and remaining_steps > 1:
            _append_log(log_dir, "tool_calls_received", {"step": step, "count": len(tool_calls)})
            assistant_message = {
                "role": "assistant",
                "content": content,
                "tool_calls": [],
            }
            for tc in tool_calls:
                assistant_message["tool_calls"].append(
                    {
                        "id": tc.id,
                        "type": "function",
                        "function": {
                            "name": tc.function.name,
                            "arguments": tc.function.arguments,
                        },
                    }
                )
            messages.append(assistant_message)

            for tc in tool_calls:
                tool_name = tc.function.name
                raw_args = tc.function.arguments or "{}"
                try:
                    args = json.loads(raw_args)
                except json.JSONDecodeError:
                    args = {"_raw": raw_args}
                handler = TOOL_DISPATCH.get(tool_name)
                if handler is None:
                    payload = {"error": f"unsupported tool: {tool_name}", "args": args}
                else:
                    try:
                        _append_log(log_dir, "tool_call_start", {"step": step, "tool": tool_name, "args": args})
                        payload = handler(base_dir, args)
                        _append_log(log_dir, "tool_call_ok", {"step": step, "tool": tool_name})
                    except Exception as exc:
                        payload = {"error": f"{type(exc).__name__}: {exc}", "args": args}
                        _append_log(log_dir, "tool_call_error", {"step": step, "tool": tool_name, "error": f"{type(exc).__name__}: {exc}"})
                _print_tool(tool_name, payload)
                messages.append(
                    {
                        "role": "tool",
                        "tool_call_id": tc.id,
                        "content": json.dumps(payload, ensure_ascii=True),
                    }
                )
            continue
        if tool_calls and remaining_steps <= 2:
            # Last step safeguard: ignore new tool calls and force content output attempt.
            messages.append(
                {
                    "role": "system",
                    "content": "No more tool calls allowed now. Return final output immediately (code only if requested).",
                }
            )
            continue

        return content

    raise RuntimeError(f"tool loop did not terminate after {max_steps} steps")


def _default_provider() -> str:
    return os.environ.get("AUDITHOUND_TOOL_PROVIDER", "codex").strip().lower() or "codex"


def main() -> int:
    parser = argparse.ArgumentParser(description="Tool-calling runner for AuditHound/Red_V2-style agent workflows.")
    parser.add_argument("--model", default=os.environ.get("CODEX_MODEL", "gpt-5.4"))
    parser.add_argument(
        "--provider",
        default=_default_provider(),
        choices=("codex", "deepseek", "claude"),
        help="Provider used for tool-calling: codex (OpenAI SDK), deepseek, or claude (codex exec CLI).",
    )
    parser.add_argument(
        "--reasoning-effort",
        default=os.environ.get("CODEX_REASONING_EFFORT", "medium"),
        choices=("minimal", "low", "medium", "high", "xhigh"),
    )
    parser.add_argument("--workdir", default=str(Path.cwd()))
    parser.add_argument("--mode", choices=("finding", "validation", "generic"), default="generic")
    parser.add_argument("--max-steps", type=int, default=24)
    parser.add_argument("--prompt-file")
    parser.add_argument("--log-dir", default="")
    args = parser.parse_args()

    if args.prompt_file:
        prompt_path = Path(args.prompt_file).expanduser().resolve()
        prompt = prompt_path.read_text(encoding="utf-8")
    else:
        prompt = os.sys.stdin.read()

    if not prompt.strip():
        raise SystemExit("prompt is empty")

    workdir = Path(args.workdir).expanduser().resolve()
    log_dir = Path(args.log_dir).expanduser().resolve() if str(args.log_dir or "").strip() else None
    if not workdir.exists():
        raise SystemExit(f"workdir does not exist: {workdir}")

    if args.provider == "claude":
        if not shutil.which("codex"):
            print("codex CLI not found in PATH", file=os.sys.stderr)
            return 1
        cmd = [
            "codex",
            "exec",
            "--full-auto",
            "--sandbox",
            "workspace-write",
            "--skip-git-repo-check",
            "--model",
            args.model,
            "-c",
            f'model_reasoning_effort="{args.reasoning_effort}"',
            "--cd",
            str(workdir),
            "-",
        ]
        result = subprocess.run(cmd, input=prompt, capture_output=True, text=True)
        output = (result.stdout or "") + ("\n" + result.stderr if result.stderr else "")
        print(output)
        return result.returncode

    client, model = _client_and_model(args.provider, args.model)
    final = _run_tool_loop(client=client, model=model, prompt=prompt, mode=args.mode, max_steps=args.max_steps, base_dir=workdir, log_dir=log_dir)
    print(final)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
