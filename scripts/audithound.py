#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import posixpath
import subprocess
import tempfile
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_RUNNER = ROOT / "scripts" / "run_convergence_loop.sh"
DEFAULT_OUTPUT_ROOT = ROOT / "output"
DEFAULT_FOUNDRY_VALIDATOR = ROOT / "scripts" / "foundry_validate.py"

CHAIN_TO_ID = {
    "mainnet": "1",
    "ethereum": "1",
    "eth": "1",
    "bsc": "56",
    "arbitrum": "42161",
    "optimism": "10",
    "base": "8453",
    "polygon": "137",
}

PLACEHOLDER_SOL_NAMES = {"FlawVerifier.sol", "Counter.sol"}


def load_manifest(path: Path) -> dict:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise SystemExit(f"Manifest must be a JSON object: {path}")
    return data


def resolve_target_and_case_name(target_arg: str) -> tuple[Path, str]:
    raw = Path(target_arg).expanduser().resolve()

    if raw.is_file() and raw.name == "manifest.json":
        manifest = load_manifest(raw)
        target_root = Path(manifest["target_root"]).expanduser().resolve()
        case_name = str(manifest.get("audit_id") or raw.parent.name)
        return target_root, case_name

    manifest_path = raw / "manifest.json"
    if raw.is_dir() and manifest_path.exists():
        manifest = load_manifest(manifest_path)
        target_root = Path(manifest["target_root"]).expanduser().resolve()
        case_name = str(manifest.get("audit_id") or raw.name)
        return target_root, case_name

    if not raw.exists():
        raise SystemExit(f"Target does not exist: {raw}")
    if not raw.is_dir():
        raise SystemExit(f"Target must be a directory, materialized case dir, or manifest.json: {raw}")
    return raw, raw.name


def resolve_manifest_path(target_arg: str) -> Path | None:
    raw = Path(target_arg).expanduser().resolve()
    if raw.is_file() and raw.name == "manifest.json":
        return raw
    manifest_path = raw / "manifest.json"
    if raw.is_dir() and manifest_path.exists():
        return manifest_path
    return None


def default_output_dir(case_name: str) -> Path:
    return DEFAULT_OUTPUT_ROOT / f"{case_name}_{int(time.time())}"


def default_model_for_agent(agent: str) -> str:
    if agent == "opencode":
        return os.environ.get("OPENCODE_MODEL", "opencode/minimax-m2.5-free")
    return os.environ.get("CODEX_MODEL", "gpt-5.4")


def effective_excludes(cli_excludes: list[str] | None) -> list[str]:
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


def effective_includes(cli_includes: list[str] | None) -> list[str]:
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


def _is_likely_build_artifact(path: Path, root: Path) -> bool:
    rel_parts = [p.lower() for p in path.relative_to(root).parts]
    for p in rel_parts:
        if p.startswith("out") or p.startswith("cache"):
            return True
        if p in {"_baseline_excluded", "broadcast", "artifacts"}:
            return True
    return False


def _auditable_sol_files(target_root: Path) -> list[Path]:
    if not target_root.exists():
        return []
    files: list[Path] = []
    for p in sorted(target_root.rglob("*.sol")):
        if not p.is_file():
            continue
        if _is_likely_build_artifact(p, target_root):
            continue
        files.append(p)
    return files


def _has_real_source_code(target_root: Path) -> bool:
    files = _auditable_sol_files(target_root)
    if not files:
        return False
    names = {p.name for p in files}
    return not names.issubset(PLACEHOLDER_SOL_NAMES)


def _resolve_etherscan_api_key(manifest: dict, override: str | None) -> str:
    key = (override or "").strip()
    if key:
        return key
    for k in (
        "etherscan_api_key",
        "etherscan_key",
        "api_key",
    ):
        v = manifest.get(k)
        if isinstance(v, str) and v.strip():
            return v.strip()
    for env_k in (
        "ETHERSCAN_API_KEY",
        "ETHERSCAN_KEY",
    ):
        v = os.environ.get(env_k, "").strip()
        if v:
            return v
    raise SystemExit(
        "Auto on-chain materialization needs Etherscan API key. "
        "Set ETHERSCAN_API_KEY or pass --etherscan-api-key."
    )


def _fetch_etherscan_contract(chain_id: str, address: str, api_key: str) -> dict:
    url = (
        "https://api.etherscan.io/v2/api"
        f"?chainid={chain_id}&module=contract&action=getsourcecode"
        f"&address={address}&apikey={api_key}"
    )
    proc = subprocess.run(["curl", "-ksS", url], capture_output=True, text=True, check=False)
    if proc.returncode != 0:
        raise SystemExit(f"Failed to fetch Etherscan source for {address}: curl rc={proc.returncode}")
    try:
        data = json.loads(proc.stdout)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"Invalid Etherscan response for {address}: {exc}") from exc

    result = data.get("result")
    if data.get("status") != "1" or not isinstance(result, list) or not result:
        raise SystemExit(f"Etherscan source lookup failed for {address}: {data}")
    item = result[0]
    if not isinstance(item, dict):
        raise SystemExit(f"Unexpected Etherscan source payload for {address}")
    return item


def _write_source_payload(item: dict, out_dir: Path) -> int:
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
            # Etherscan can return absolute-like paths (e.g. "/contracts/X.sol").
            # Normalize to safe relative paths under out_dir.
            rel = rel.strip().replace("\\", "/")
            rel = rel.lstrip("/")
            rel = posixpath.normpath(rel)
            if rel in ("", ".") or rel.startswith("../"):
                continue
            content = ""
            if isinstance(meta, dict):
                content = str(meta.get("content") or "")
            else:
                content = str(meta)
            target = out_dir / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(content, encoding="utf-8")
            files_written += 1
    else:
        target = out_dir / "Contract.sol"
        target.write_text(src, encoding="utf-8")
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
    return files_written


def _materialize_onchain_sources(manifest: dict, api_key: str) -> Path:
    target_root = Path(str(manifest["target_root"])).expanduser().resolve()
    chain = str(manifest.get("chain") or "mainnet").lower()
    chain_id = CHAIN_TO_ID.get(chain, "1")

    target_addr = str(manifest.get("target_contract_address") or "").strip()
    if not target_addr.startswith("0x"):
        raise SystemExit("Manifest target_contract_address is missing or invalid.")

    materialized_base = target_root / "onchain_auto"
    materialized_base.mkdir(parents=True, exist_ok=True)

    fetched: list[dict] = []

    root_item = _fetch_etherscan_contract(chain_id, target_addr, api_key)
    root_out = materialized_base / target_addr.lower()
    _write_source_payload(root_item, root_out)
    fetched.append({"address": target_addr.lower(), "outdir": str(root_out)})

    proxy_flag = str(root_item.get("Proxy") or "0").strip()
    implementation = str(root_item.get("Implementation") or "").strip()
    if proxy_flag == "1" and implementation.startswith("0x"):
        impl_item = _fetch_etherscan_contract(chain_id, implementation, api_key)
        impl_out = materialized_base / implementation.lower()
        _write_source_payload(impl_item, impl_out)
        fetched.append({"address": implementation.lower(), "outdir": str(impl_out)})

    (materialized_base / "_index.json").write_text(json.dumps(fetched, indent=2, ensure_ascii=False), encoding="utf-8")
    print(json.dumps({"auto_materialized": True, "target_root": str(materialized_base), "fetched": fetched}, ensure_ascii=True))
    return materialized_base


def _write_temp_manifest(manifest: dict, new_target_root: Path) -> Path:
    patched = dict(manifest)
    patched["target_root"] = str(new_target_root)
    fd, tmp = tempfile.mkstemp(prefix="audithound_manifest_", suffix=".json")
    os.close(fd)
    out = Path(tmp)
    out.write_text(json.dumps(patched, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return out


def prepare_target_from_manifest(
    manifest_path: Path,
    auto_materialize_onchain: bool,
    etherscan_api_key: str | None,
) -> tuple[Path, str, Path]:
    manifest = load_manifest(manifest_path)
    target_root = Path(str(manifest["target_root"])).expanduser().resolve()
    case_name = str(manifest.get("audit_id") or manifest_path.parent.name)

    if not auto_materialize_onchain:
        return target_root, case_name, manifest_path

    if _has_real_source_code(target_root):
        return target_root, case_name, manifest_path

    api_key = _resolve_etherscan_api_key(manifest, etherscan_api_key)
    materialized_root = _materialize_onchain_sources(manifest, api_key)
    temp_manifest = _write_temp_manifest(manifest, materialized_root)
    return materialized_root, case_name, temp_manifest


def run_foundry_validation(
    manifest_path: Path,
    output_dir: Path,
    model: str,
    reasoning_effort: str,
    objective: str,
    top_k: int,
    min_profit: float,
    rpc_url: str | None,
    max_attempts: int,
    maximize_plateau: int,
    anvil_port: int | None,
    anvil_port_start: int | None,
    anvil_port_end: int | None,
    anvil_ready_timeout: float | None,
) -> int:
    findings_path = output_dir / "findings_acc.json"
    if not findings_path.exists():
        raise SystemExit(f"Foundry validation requested but findings file is missing: {findings_path}")

    cmd = [
        "python3",
        str(DEFAULT_FOUNDRY_VALIDATOR),
        "--manifest",
        str(manifest_path),
        "--findings",
        str(findings_path),
        "--output-dir",
        str(output_dir),
        "--top-k",
        str(top_k),
        "--objective",
        str(objective),
        "--min-profit",
        str(min_profit),
        "--model",
        model,
        "--reasoning-effort",
        reasoning_effort,
        "--max-attempts",
        str(max_attempts),
        "--maximize-plateau",
        str(maximize_plateau),
    ]
    if rpc_url:
        cmd.extend(["--rpc-url", rpc_url])
    if anvil_port is not None:
        cmd.extend(["--anvil-port", str(anvil_port)])
    if anvil_port_start is not None:
        cmd.extend(["--anvil-port-start", str(anvil_port_start)])
    if anvil_port_end is not None:
        cmd.extend(["--anvil-port-end", str(anvil_port_end)])
    if anvil_ready_timeout is not None:
        cmd.extend(["--anvil-ready-timeout", str(anvil_ready_timeout)])

    proc = subprocess.run(cmd, check=False)
    return proc.returncode


def run_loop(args: argparse.Namespace) -> int:
    manifest_path = resolve_manifest_path(args.target)
    manifest_for_validation: Path | None = manifest_path

    if manifest_path is not None:
        target_dir, case_name, manifest_for_validation = prepare_target_from_manifest(
            manifest_path=manifest_path,
            auto_materialize_onchain=args.auto_materialize_onchain,
            etherscan_api_key=args.etherscan_api_key,
        )
    else:
        target_dir, case_name = resolve_target_and_case_name(args.target)

    if args.resume and not args.output_dir:
        raise SystemExit("--resume requires --output-dir so the previous run can be located.")

    output_dir = Path(args.output_dir).expanduser().resolve() if args.output_dir else default_output_dir(case_name)
    if args.resume and not output_dir.exists():
        raise SystemExit(f"--resume requested but output directory does not exist: {output_dir}")

    output_dir.parent.mkdir(parents=True, exist_ok=True)
    excludes = effective_excludes(args.exclude)
    includes = effective_includes(args.include)

    env = os.environ.copy()
    env["AUDITHOUND_AGENT_TYPE"] = args.agent
    if args.agents:
        env["AUDITHOUND_AGENT_TYPES"] = args.agents
    env["CODEX_MODEL"] = args.model
    env["CODEX_REASONING_EFFORT"] = args.reasoning_effort
    env["AUDITHOUND_MERGE_MODEL"] = args.merge_model or args.model
    env["AUDITHOUND_CODEX_MODEL"] = args.codex_model or args.model
    env["AUDITHOUND_OPENCODE_MODEL"] = args.opencode_model or args.model
    env["AUDITHOUND_SUMMARY_AGENT"] = args.summary_agent
    env["AUDITHOUND_SUMMARY_MODEL"] = args.summary_model or env["AUDITHOUND_MERGE_MODEL"]
    env["AUDITHOUND_SUMMARY_REASONING_EFFORT"] = args.summary_reasoning_effort or args.reasoning_effort
    env["AUDITHOUND_EXCLUDE_GLOBS"] = json.dumps(excludes, ensure_ascii=True)
    env["AUDITHOUND_INCLUDE_GLOBS"] = json.dumps(includes, ensure_ascii=True)
    env["AUDITHOUND_RESUME"] = "1" if args.resume else "0"
    if args.opencode_api_key:
        env["OPENCODE_API_KEY"] = args.opencode_api_key
        env["MINIMAX_API_KEY"] = args.opencode_api_key

    cmd = [
        "bash",
        str(DEFAULT_RUNNER),
        str(target_dir),
        str(output_dir),
        str(args.max_rounds),
        str(args.converge_after),
        args.merge_mode,
        args.model,
        str(args.workers),
    ]

    print(
        json.dumps(
            {
                "target_dir": str(target_dir),
                "output_dir": str(output_dir),
                "agent": args.agent,
                "agents": args.agents,
                "model": args.model,
                "codex_model": env["AUDITHOUND_CODEX_MODEL"],
                "opencode_model": env["AUDITHOUND_OPENCODE_MODEL"],
                "merge_model": env["AUDITHOUND_MERGE_MODEL"],
                "summary_agent": env["AUDITHOUND_SUMMARY_AGENT"],
                "summary_model": env["AUDITHOUND_SUMMARY_MODEL"],
                "summary_reasoning_effort": env["AUDITHOUND_SUMMARY_REASONING_EFFORT"],
                "reasoning_effort": args.reasoning_effort,
                "resume": args.resume,
                "include": includes,
                "exclude": excludes,
                "max_rounds": args.max_rounds,
                "converge_after": args.converge_after,
                "merge_mode": args.merge_mode,
                "workers": args.workers,
                "foundry_validate": args.foundry_validate,
                "auto_materialize_onchain": args.auto_materialize_onchain,
                "manifest_for_validation": str(manifest_for_validation) if manifest_for_validation else None,
            },
            ensure_ascii=True,
        )
    )
    proc = subprocess.run(cmd, env=env, check=False)
    if proc.returncode != 0:
        return proc.returncode

    if not args.foundry_validate:
        return 0

    if manifest_for_validation is None:
        raise SystemExit("--foundry-validate requires target to be a manifest.json or a case dir containing manifest.json")

    return run_foundry_validation(
        manifest_path=manifest_for_validation,
        output_dir=output_dir,
        model=args.foundry_model or args.model,
        reasoning_effort=args.foundry_reasoning_effort or args.reasoning_effort,
        objective=args.foundry_objective,
        top_k=args.foundry_top_k,
        min_profit=args.foundry_min_profit,
        rpc_url=args.foundry_rpc_url,
        max_attempts=args.foundry_max_attempts,
        maximize_plateau=args.foundry_maximize_plateau,
        anvil_port=args.foundry_anvil_port,
        anvil_port_start=args.foundry_anvil_port_start,
        anvil_port_end=args.foundry_anvil_port_end,
        anvil_ready_timeout=args.foundry_anvil_ready_timeout,
    )


def run_validate(args: argparse.Namespace) -> int:
    if args.opencode_api_key:
        os.environ["OPENCODE_API_KEY"] = args.opencode_api_key
        os.environ["MINIMAX_API_KEY"] = args.opencode_api_key

    output_dir = Path(args.output_dir).expanduser().resolve()
    manifest_path = Path(args.manifest).expanduser().resolve()

    manifest_for_validation = manifest_path
    if args.auto_materialize_onchain:
        _, _, manifest_for_validation = prepare_target_from_manifest(
            manifest_path=manifest_path,
            auto_materialize_onchain=True,
            etherscan_api_key=args.etherscan_api_key,
        )

    return run_foundry_validation(
        manifest_path=manifest_for_validation,
        output_dir=output_dir,
        model=args.model,
        reasoning_effort=args.reasoning_effort,
        objective=args.objective,
        top_k=args.top_k,
        min_profit=args.min_profit,
        rpc_url=args.rpc_url,
        max_attempts=args.max_attempts,
        maximize_plateau=args.maximize_plateau,
        anvil_port=args.anvil_port,
        anvil_port_start=args.anvil_port_start,
        anvil_port_end=args.anvil_port_end,
        anvil_ready_timeout=args.anvil_ready_timeout,
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="audithound", description="CLI wrapper for AuditHoundV2.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    run_parser = subparsers.add_parser(
        "run",
        help="Run the convergence audit loop on a source directory, materialized case dir, or manifest.json.",
    )
    run_parser.add_argument(
        "target",
        help="Source directory, materialized case directory, or path to manifest.json.",
    )
    run_parser.add_argument(
        "--output-dir",
        help="Output directory. Defaults to AuditHoundV2/output/<case>_<timestamp>.",
    )
    run_parser.add_argument("--agent", default="codex", choices=("codex", "opencode"), help="Code agent to run.")
    run_parser.add_argument(
        "--agents",
        help="Comma-separated agents to run each round, e.g. codex,opencode or codex,codex,opencode. Overrides --agent/--workers shape.",
    )
    run_parser.add_argument("--model", help="Primary model for audit rounds.")
    run_parser.add_argument("--codex-model", help="Model for codex workers. Defaults to --model or codex default.")
    run_parser.add_argument("--opencode-model", help="Model for opencode workers. Defaults to --model or opencode default.")
    run_parser.add_argument(
        "--opencode-api-key",
        help=(
            "API key for opencode/minimax workers. "
            "Exports OPENCODE_API_KEY and MINIMAX_API_KEY to child workers."
        ),
    )
    run_parser.add_argument(
        "--merge-model",
        help="Model for merge/review. Defaults to --model.",
    )
    run_parser.add_argument(
        "--summary-agent",
        default="codex",
        choices=("codex", "opencode"),
        help="Agent used for round summaries. Defaults to codex.",
    )
    run_parser.add_argument(
        "--summary-model",
        help="Model for round summaries. Defaults to --merge-model.",
    )
    run_parser.add_argument(
        "--summary-reasoning-effort",
        choices=("minimal", "low", "medium", "high", "xhigh"),
        help="Reasoning effort for round summaries. Defaults to --reasoning-effort.",
    )
    run_parser.add_argument(
        "--reasoning-effort",
        default=os.environ.get("CODEX_REASONING_EFFORT", "medium"),
        choices=("minimal", "low", "medium", "high", "xhigh"),
        help="Reasoning effort passed to codex.",
    )
    run_parser.add_argument(
        "--exclude",
        action="append",
        help="Relative glob to exclude from direct audit scope, e.g. interfaces/**. May be repeated.",
    )
    run_parser.add_argument(
        "--include",
        action="append",
        help="Relative glob to include in direct audit scope, e.g. LayerZero/**. May be repeated.",
    )
    run_parser.add_argument(
        "--resume",
        action="store_true",
        help="Resume an interrupted run from an existing --output-dir instead of starting over.",
    )
    run_parser.add_argument("--max-rounds", type=int, default=10, help="Maximum audit rounds.")
    run_parser.add_argument(
        "--converge-after",
        type=int,
        default=2,
        help="Stop after this many consecutive no-new-finding rounds.",
    )
    run_parser.add_argument(
        "--merge-mode",
        default="codex",
        choices=("codex", "manual"),
        help="Merge mode.",
    )
    run_parser.add_argument("--workers", type=int, default=1, help="Parallel workers per round.")
    run_parser.add_argument(
        "--auto-materialize-onchain",
        action="store_true",
        default=True,
        help="When manifest target_root lacks real source, auto-fetch verified source from Etherscan using manifest params.",
    )
    run_parser.add_argument(
        "--etherscan-api-key",
        help="Etherscan API key override for auto on-chain source materialization.",
    )
    run_parser.add_argument(
        "--foundry-validate",
        action="store_true",
        help="After run completes, generate Foundry PoC files from findings and execute forge tests on forked state.",
    )
    run_parser.add_argument("--foundry-rpc-url", help="RPC URL override for Foundry validation.")
    run_parser.add_argument("--foundry-anvil-port", type=int, help="Fixed local anvil port for Foundry validation.")
    run_parser.add_argument("--foundry-anvil-port-start", type=int, default=18545, help="Anvil auto-port range start.")
    run_parser.add_argument("--foundry-anvil-port-end", type=int, default=18650, help="Anvil auto-port range end.")
    run_parser.add_argument("--foundry-anvil-ready-timeout", type=float, default=20.0, help="Seconds to wait for local anvil startup.")
    run_parser.add_argument(
        "--foundry-objective",
        choices=("threshold", "maximize"),
        default="maximize",
        help="Foundry validation objective: threshold=stop on first passing PoC, maximize=search best profit.",
    )
    run_parser.add_argument("--foundry-top-k", type=int, default=3, help="How many top findings to validate in Foundry.")
    run_parser.add_argument("--foundry-min-profit", type=float, default=0.001, help="Minimum profit threshold for Foundry validation.")
    run_parser.add_argument("--foundry-max-attempts", type=int, default=3, help="Maximum PoC generation/validation attempts per finding.")
    run_parser.add_argument(
        "--foundry-maximize-plateau",
        type=int,
        default=2,
        help="Stop Foundry maximize search after this many non-improving successful attempts.",
    )
    run_parser.add_argument("--foundry-model", help="Model for generating Foundry PoC contracts.")
    run_parser.add_argument(
        "--foundry-reasoning-effort",
        choices=("minimal", "low", "medium", "high", "xhigh"),
        help="Reasoning effort for Foundry PoC generation.",
    )
    run_parser.set_defaults(func=run_loop)

    validate_parser = subparsers.add_parser(
        "validate",
        help="Run Foundry validation for an existing run output directory.",
    )
    validate_parser.add_argument("--manifest", required=True, help="Path to case manifest.json.")
    validate_parser.add_argument("--output-dir", required=True, help="Run output directory containing findings_acc.json.")
    validate_parser.add_argument("--rpc-url", help="RPC URL override.")
    validate_parser.add_argument("--anvil-port", type=int, help="Fixed local anvil port for this validate run.")
    validate_parser.add_argument("--anvil-port-start", type=int, default=18545, help="Anvil auto-port range start.")
    validate_parser.add_argument("--anvil-port-end", type=int, default=18650, help="Anvil auto-port range end.")
    validate_parser.add_argument("--anvil-ready-timeout", type=float, default=20.0, help="Seconds to wait for local anvil startup.")
    validate_parser.add_argument(
        "--objective",
        choices=("threshold", "maximize"),
        default="maximize",
        help="Validation objective: threshold=stop on first passing PoC, maximize=search best profit.",
    )
    validate_parser.add_argument("--top-k", type=int, default=3)
    validate_parser.add_argument("--min-profit", type=float, default=0.001)
    validate_parser.add_argument("--max-attempts", type=int, default=3, help="Maximum PoC generation/validation attempts per finding.")
    validate_parser.add_argument(
        "--maximize-plateau",
        type=int,
        default=2,
        help="Stop maximize search after this many non-improving successful attempts.",
    )
    validate_parser.add_argument("--model", default=os.environ.get("CODEX_MODEL", "gpt-5.4"))
    validate_parser.add_argument(
        "--opencode-api-key",
        help=(
            "Optional API key for opencode/minimax calls during validation. "
            "Exports OPENCODE_API_KEY and MINIMAX_API_KEY for this process."
        ),
    )
    validate_parser.add_argument(
        "--reasoning-effort",
        choices=("minimal", "low", "medium", "high", "xhigh"),
        default=os.environ.get("CODEX_REASONING_EFFORT", "medium"),
    )
    validate_parser.add_argument(
        "--auto-materialize-onchain",
        action="store_true",
        default=True,
        help="When manifest target_root lacks real source, auto-fetch verified source from Etherscan using manifest params.",
    )
    validate_parser.add_argument(
        "--etherscan-api-key",
        help="Etherscan API key override for auto on-chain source materialization.",
    )
    validate_parser.set_defaults(func=run_validate)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    if getattr(args, "command", None) == "run":
        if not args.model:
            args.model = default_model_for_agent(args.agent)
        if not args.codex_model:
            args.codex_model = os.environ.get("CODEX_MODEL", "gpt-5.4")
        if not args.opencode_model:
            args.opencode_model = os.environ.get("OPENCODE_MODEL", "opencode/minimax-m2.5-free")
        if not args.foundry_model:
            args.foundry_model = args.model
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
