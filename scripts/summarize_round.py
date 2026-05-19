#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
from pathlib import Path


SUMMARY_PROMPT = """You are summarizing one audit round.

Write a short markdown summary of this round only.

Write the summary in this exact structure:

# Round {round_num} Summary

## Agent: <agent_name>
- files touched
- files revisited / highest-attention files
- main issue directions investigated
- promising but not retained directions

Repeat one `## Agent: <agent_name>` section for each agent in this round.

## Cross-Agent Status
- main overlap in file/area attention
- notable differences in attention
- underexplored but suspicious files/functions if clearly supported by the logs

## Retained Findings
- short summary of findings retained from this round after merge

Rules:
- use only information visible in the logs and retained findings
- do not invent hidden reasoning or unsupported conclusions
- keep it concise and useful for later retrieval
- do not repeat the full findings verbatim
- keep each agent section separate; do not blend them together
- focus on current-state reporting, not broad advice for the next round
- if you mention an underexplored hotspot, state it as current status, not as a long recommendation

## Retained Findings From This Round
{retained}

## This Round's Agent Logs
{logs}

Output only markdown.
"""


GLOBAL_SUMMARY_PROMPT = """You maintain a concise global audit memory for future audit agents.

Update the existing global memory by folding in durable observations from the
latest round summary. The goal is an accumulated cross-round audit view, not a
per-round recap.

This memory is optional context only. Findings are stored separately.

Write the updated memory in this exact structure:

# Global Audit Memory

## Scope Touched
- files/contracts/flows that have mattered across rounds, with short issue-direction notes

## Issue Directions Seen
- recurring or promising vulnerability directions seen across the audit

## Useful Context
- compact cross-round observations 

Rules:
- keep it compact
- preserve useful prior context while integrating new durable observations
- prefer stable cross-round patterns over latest-round details
- fold repeated wording into a single clearer observation
- keep the memory descriptive rather than prescriptive

## Existing Global Memory
{existing}

## Latest Round Summary
{round_summary}

Output only markdown.
"""


def load_findings(path: Path) -> list[dict]:
    if not path.exists() or not path.read_text(encoding="utf-8").strip():
        return []
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, list):
        raise ValueError(f"findings file must be a JSON array: {path}")
    return data


def load_merged_finding_ids(path: Path) -> set[str]:
    if not path.exists() or not path.read_text(encoding="utf-8").strip():
        return set()

    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        return set()
    findings = data.get("findings", [])
    if not isinstance(findings, list):
        return set()

    ids: set[str] = set()
    for item in findings:
        if not isinstance(item, dict):
            continue
        item_id = item.get("id")
        if isinstance(item_id, str) and item_id:
            ids.add(item_id)
    return ids


def compute_retained_findings(findings: list[dict], round_dir: Path, round_num: int) -> list[dict]:
    current_ids = load_merged_finding_ids(round_dir / "merge_stdout.log")
    if current_ids:
        prev_ids: set[str] = set()
        rounds_dir = round_dir.parent
        prev_candidates: list[tuple[int, Path]] = []
        for path in rounds_dir.glob("round_*"):
            if not path.is_dir():
                continue
            name = path.name
            if ".resume_backup_" in name:
                continue
            try:
                num = int(name.split("_", 1)[1])
            except (ValueError, IndexError):
                continue
            if num < round_num:
                prev_candidates.append((num, path))
        if prev_candidates:
            prev_path = sorted(prev_candidates, key=lambda x: x[0])[-1][1]
            prev_ids = load_merged_finding_ids(prev_path / "merge_stdout.log")

        new_ids = current_ids - prev_ids if prev_ids else current_ids
        if new_ids:
            retained = [
                item
                for item in findings
                if isinstance(item, dict) and isinstance(item.get("id"), str) and item.get("id") in new_ids
            ]
            if retained:
                return retained

    # Fallback for legacy runs where merge logs are missing/unparseable.
    return [item for item in findings if isinstance(item, dict) and item.get("round") == round_num]


def load_text(path: Path, default: str) -> str:
    if not path.exists() or not path.read_text(encoding="utf-8", errors="replace").strip():
        return default
    text = path.read_text(encoding="utf-8", errors="replace")
    if len(text) > 20000:
        text = text[:10000] + "\n\n[... truncated ...]\n\n" + text[-10000:]
    return text


def collect_logs(round_dir: Path) -> list[tuple[str, str, str]]:
    logs: list[tuple[str, str, str]] = []
    for agent_dir in sorted(round_dir.glob("agent_*")):
        agent_name = agent_dir.name.replace("agent_", "")
        stderr_text = ""
        stdout_text = ""

        stderr_path = agent_dir / "stderr.log"
        if stderr_path.exists():
            stderr_text = stderr_path.read_text(encoding="utf-8", errors="replace")
        stdout_path = agent_dir / "stdout.log"
        if stdout_path.exists():
            stdout_text = stdout_path.read_text(encoding="utf-8", errors="replace")

        if len(stderr_text) > 20000:
            stderr_text = stderr_text[:10000] + "\n\n[... truncated ...]\n\n" + stderr_text[-10000:]
        if len(stdout_text) > 12000:
            stdout_text = stdout_text[:6000] + "\n\n[... truncated ...]\n\n" + stdout_text[-6000:]

        logs.append((agent_name, stderr_text, stdout_text))
    return logs


def build_prompt(retained: list[dict], logs: list[tuple[str, str, str]], round_num: int) -> str:
    retained_text = json.dumps(retained, indent=2, ensure_ascii=False) if retained else "None."
    rendered_logs = []
    for agent_name, stderr_text, stdout_text in logs:
        rendered_logs.append(
            f"### Agent: {agent_name}\n"
            f"#### Process Log\n```\n{stderr_text}\n```\n\n"
            f"#### Final Output\n```\n{stdout_text}\n```"
        )
    return SUMMARY_PROMPT.format(
        round_num=round_num,
        retained=retained_text,
        logs="\n\n".join(rendered_logs) if rendered_logs else "No logs found.",
    )


def build_global_prompt(existing: str, round_summary: str) -> str:
    return GLOBAL_SUMMARY_PROMPT.format(existing=existing, round_summary=round_summary)


def resolve_codex_cli() -> str:
    found = shutil.which("codex")
    if found:
        return found

    candidates = [
        "/Users/lu/.antigravity/extensions/openai.chatgpt-0.4.79-darwin-arm64/bin/macos-aarch64/codex",
        str(Path.home() / ".antigravity/extensions/openai.chatgpt-0.4.79-darwin-arm64/bin/macos-aarch64/codex"),
        str(Path.home() / ".local/bin/codex"),
        "/opt/homebrew/bin/codex",
        "/usr/local/bin/codex",
    ]
    for candidate in candidates:
        path = Path(candidate)
        if path.exists() and os.access(path, os.X_OK):
            return str(path)

    raise FileNotFoundError("codex CLI not found in PATH or known install locations")


def resolve_opencode_cli() -> str:
    found = shutil.which("opencode")
    if found:
        return found

    candidates = [
        str(Path.home() / ".local/bin/opencode"),
        "/opt/homebrew/bin/opencode",
        "/usr/local/bin/opencode",
    ]
    for candidate in candidates:
        path = Path(candidate)
        if path.exists() and os.access(path, os.X_OK):
            return str(path)

    raise FileNotFoundError("opencode CLI not found in PATH or known install locations")


def run_codex_summary(prompt: str, target_dir: Path, model: str) -> tuple[str, str]:
    reasoning_effort = os.environ.get(
        "AUDITHOUND_SUMMARY_REASONING_EFFORT",
        os.environ.get("CODEX_REASONING_EFFORT", "medium"),
    )
    codex_bin = resolve_codex_cli()
    proc = subprocess.run(
        [
            codex_bin,
            "-a",
            "never",
            "exec",
            "--cd",
            str(target_dir),
            "--sandbox",
            "workspace-write",
            "--skip-git-repo-check",
            "-m",
            model,
            "-c",
            f'model_reasoning_effort="{reasoning_effort}"',
            "-",
        ],
        input=prompt,
        text=True,
        capture_output=True,
        check=False,
    )
    return proc.stdout, proc.stderr


def run_opencode_summary(prompt: str, target_dir: Path, model: str, round_dir: Path, task_file_name: str = "round_summary_task.md") -> tuple[str, str]:
    opencode_bin = resolve_opencode_cli()
    task_file = round_dir / task_file_name
    task_file.write_text(prompt, encoding="utf-8")

    xdg_root = round_dir / ".summary_opencode_xdg"
    (xdg_root / "data").mkdir(parents=True, exist_ok=True)
    (xdg_root / "cache").mkdir(parents=True, exist_ok=True)
    (xdg_root / "state").mkdir(parents=True, exist_ok=True)
    (xdg_root / "config").mkdir(parents=True, exist_ok=True)

    env = os.environ.copy()
    env["XDG_DATA_HOME"] = str(xdg_root / "data")
    env["XDG_CACHE_HOME"] = str(xdg_root / "cache")
    env["XDG_STATE_HOME"] = str(xdg_root / "state")
    env["XDG_CONFIG_HOME"] = str(xdg_root / "config")

    proc = subprocess.run(
        [
            opencode_bin,
            "run",
            "--dir",
            str(target_dir),
            "--dangerously-skip-permissions",
            "-m",
            model,
            f"Read the file at {task_file} in full. Follow all instructions in that file exactly. Return only the markdown summary requested there.",
        ],
        text=True,
        capture_output=True,
        check=False,
        env=env,
    )
    return proc.stdout, proc.stderr


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--round-dir", required=True)
    parser.add_argument("--target-dir", required=True)
    parser.add_argument("--findings", required=True)
    parser.add_argument("--round-num", type=int, required=True)
    parser.add_argument("--agent", choices=("codex", "opencode"), default="codex")
    parser.add_argument("--model", default="gpt-5.4")
    parser.add_argument("--global-summary")
    args = parser.parse_args()

    round_dir = Path(args.round_dir).resolve()
    target_dir = Path(args.target_dir).resolve()
    findings = load_findings(Path(args.findings).resolve())
    retained = compute_retained_findings(findings, round_dir, args.round_num)
    logs = collect_logs(round_dir)
    prompt = build_prompt(retained, logs, args.round_num)

    try:
        if args.agent == "opencode":
            stdout, stderr = run_opencode_summary(prompt, target_dir, args.model, round_dir)
        else:
            stdout, stderr = run_codex_summary(prompt, target_dir, args.model)
    except FileNotFoundError as exc:
        (round_dir / "round_summary_stderr.log").write_text(str(exc) + "\n", encoding="utf-8")
        raise SystemExit(str(exc))

    round_summary_text = stdout.strip() + "\n"
    (round_dir / "round_summary_stdout.log").write_text(stdout, encoding="utf-8")
    (round_dir / "round_summary_stderr.log").write_text(stderr, encoding="utf-8")
    (round_dir / "round_summary.md").write_text(round_summary_text, encoding="utf-8")

    global_summary_path = None
    if args.global_summary:
        global_summary_path = Path(args.global_summary).resolve()
        existing_global = load_text(global_summary_path, "No global memory yet.")
        global_prompt = build_global_prompt(existing_global, round_summary_text)
        (round_dir / "global_summary_task.md").write_text(global_prompt, encoding="utf-8")
        try:
            if args.agent == "opencode":
                global_stdout, global_stderr = run_opencode_summary(
                    global_prompt,
                    target_dir,
                    args.model,
                    round_dir,
                    "global_summary_task.md",
                )
            else:
                global_stdout, global_stderr = run_codex_summary(global_prompt, target_dir, args.model)
        except FileNotFoundError as exc:
            (round_dir / "global_summary_stderr.log").write_text(str(exc) + "\n", encoding="utf-8")
            raise SystemExit(str(exc))
        (round_dir / "global_summary_stdout.log").write_text(global_stdout, encoding="utf-8")
        (round_dir / "global_summary_stderr.log").write_text(global_stderr, encoding="utf-8")
        global_summary_path.parent.mkdir(parents=True, exist_ok=True)
        global_summary_path.write_text(global_stdout.strip() + "\n", encoding="utf-8")

    print(
        json.dumps(
            {
                "path": str(round_dir / "round_summary.md"),
                "global_summary": str(global_summary_path) if global_summary_path else None,
            },
            ensure_ascii=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
