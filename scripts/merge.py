#!/usr/bin/env python3
from __future__ import annotations

import argparse
import difflib
import json
import os
import re
import shutil
import subprocess
from collections import Counter
from fnmatch import fnmatchcase
from pathlib import Path


MERGE_PROMPT = """Below are findings and vulnerability signals from {n} agents auditing the same codebase,
plus accumulated findings from previous rounds. You need to inspect the source code when needed.

You are the merge and review layer for a audit.

Your task:
- merge new or materially improved reportable issues into the accumulated findings
- reconstruct plausible but poorly written findings or signals into low-confidence findings when the code supports them
- reject clearly non-reportable candidates with your reasons
- try to use this round's signals and the source code to look for additional findings yourself

Prefer downgrading severity or confidence over discarding a plausible issue.
Keep findings that can cause realistic protocol-level harm, including fund loss,
theft, insolvency, permanent lockup, economic manipulation, or permissionless DoS and some other realistic issues.

## Accumulated Findings
{existing}

## This Round's Agent Outputs
{outputs}
{include_note}
{exclude_note}

## Output
Return a JSON object with:
- `findings`: the COMPLETE updated findings list
- `rejected_candidates`: candidates rejected from this round, with concise reasons

Each `findings` element must have:
- `id`
- `severity`
- `confidence`
- `title`
- `locations`
- `claim`
- `impact`
- `paths`
- `round`
- `source_agents`

Preserve existing IDs for surviving findings whenever possible.
`source_agents` must include every agent that materially supports the final finding.

Each `rejected_candidates` element must have:
- `title`
- `source_agents`
- `reason`

Output ONLY valid JSON. No markdown. No prose.
"""


def extract_merge_result(text: str) -> tuple[list[dict], list[dict]]:
    text = text.strip()
    if not text:
        raise ValueError("empty merge output")

    try:
        data = json.loads(text)
        if isinstance(data, list):
            return data, []
        if isinstance(data, dict):
            findings = data.get("findings", data.get("updated_findings", []))
            rejected = data.get("rejected_candidates", data.get("rejected", []))
            if isinstance(findings, list):
                return findings, rejected if isinstance(rejected, list) else []
    except json.JSONDecodeError:
        pass

    obj_start = text.find("{")
    obj_end = text.rfind("}")
    if obj_start != -1 and obj_end != -1 and obj_end > obj_start:
        try:
            data = json.loads(text[obj_start : obj_end + 1])
            if isinstance(data, dict):
                findings = data.get("findings", data.get("updated_findings", []))
                rejected = data.get("rejected_candidates", data.get("rejected", []))
                if isinstance(findings, list):
                    return findings, rejected if isinstance(rejected, list) else []
        except json.JSONDecodeError:
            pass

    start = text.find("[")
    end = text.rfind("]")
    if start == -1 or end == -1 or end <= start:
        raise ValueError("could not find JSON merge result in merge output")

    data = json.loads(text[start : end + 1])
    if not isinstance(data, list):
        raise ValueError("merge output is not a JSON array")
    return data, []


def load_acc(path: Path) -> list[dict]:
    if not path.exists() or not path.read_text(encoding="utf-8").strip():
        return []
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, list):
        raise ValueError(f"accumulator must be a JSON array: {path}")
    return data


def collect_outputs(round_dir: Path) -> list[tuple[str, str]]:
    outputs: list[tuple[str, str]] = []
    for agent_dir in sorted(round_dir.glob("agent_*")):
        agent_name = agent_dir.name.replace("agent_", "")
        stdout_path = agent_dir / "stdout.log"
        if not stdout_path.exists():
            continue
        text = stdout_path.read_text(encoding="utf-8", errors="replace")
        if len(text) > 40000:
            text = text[:20000] + "\n\n[... truncated ...]\n\n" + text[-20000:]
        outputs.append((agent_name, text))
    return outputs


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


def matches_pattern(rel_path: str, pattern: str) -> bool:
    normalized = pattern.strip().strip("/")
    if not normalized:
        return False
    if rel_path == normalized or rel_path.startswith(normalized + "/"):
        return True
    return fnmatchcase(rel_path, normalized)


def is_included(rel_path: str, includes: list[str]) -> bool:
    if not includes:
        return True
    return any(matches_pattern(rel_path, pattern) for pattern in includes)


def extract_location_path(location: str) -> str:
    if not isinstance(location, str) or not location:
        return ""
    if ":" in location:
        return location.split(":", 1)[0]
    return location


def build_prompt(existing: list[dict], outputs: list[tuple[str, str]], excludes: list[str], includes: list[str]) -> str:
    rendered_outputs = []
    for name, text in outputs:
        rendered_outputs.append(f"### Agent: {name}\n```\n{text}\n```")
    include_note = ""
    if includes:
        include_lines = "\n".join(f"- `{item}`" for item in includes)
        include_note = f"""

## Included Direct Audit Scope
Only keep findings whose root cause location is inside files matching:
{include_lines}

Other files can still be read as context.
"""
    exclude_note = ""
    if excludes:
        exclude_lines = "\n".join(f"- `{item}`" for item in excludes)
        exclude_note = f"""

## Excluded From Direct Audit Scope
Do not keep findings whose reportable root cause exists solely in files matching:
{exclude_lines}

Those files may still be read as context for in-scope implementation code.
"""
    return MERGE_PROMPT.format(
        n=len(outputs),
        existing=json.dumps(existing, indent=2, ensure_ascii=False) if existing else "None yet.",
        outputs="\n\n".join(rendered_outputs) if rendered_outputs else "No agent outputs found.",
        include_note=include_note,
        exclude_note=exclude_note,
    )


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


def run_codex_merge(prompt: str, target_dir: Path, model: str) -> tuple[str, str]:
    reasoning_effort = os.environ.get("CODEX_REASONING_EFFORT", "medium")
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


def normalize_findings(
    items: list[dict],
    round_num: int,
    existing_round_by_id: dict[str, int] | None = None,
) -> list[dict]:
    existing_round_by_id = existing_round_by_id or {}
    normalized: list[dict] = []
    for item in items:
        if not isinstance(item, dict):
            continue
        locations = item.get("locations", [])
        if isinstance(locations, str):
            locations = [locations] if locations else []
        if not isinstance(locations, list):
            locations = []

        paths = item.get("paths", [])
        if isinstance(paths, str):
            paths = [paths] if paths else []
        if not isinstance(paths, list):
            paths = []

        if not paths:
            legacy_checks = item.get("checks", [])
            if isinstance(legacy_checks, str):
                legacy_checks = [legacy_checks] if legacy_checks else []
            if not isinstance(legacy_checks, list):
                legacy_checks = []
            paths = [value for value in legacy_checks if isinstance(value, str) and value]

        source_agents = item.get("source_agents", [])
        if isinstance(source_agents, str):
            source_agents = [source_agents] if source_agents else []
        if not isinstance(source_agents, list):
            source_agents = []

        item_id = item.get("id", "")
        if isinstance(item_id, str):
            item_id = item_id.strip()
        else:
            item_id = ""

        model_round = item.get("round")
        round_value = round_num
        if item_id and item_id in existing_round_by_id:
            # Existing finding: preserve original first-seen round.
            round_value = existing_round_by_id[item_id]
        elif isinstance(model_round, int) and model_round > 0:
            # New/renamed finding should normally be tagged to current round.
            # Keep model value only when it explicitly points to current round.
            if model_round == round_num:
                round_value = model_round

        obj = {
            "id": item_id,
            "severity": item.get("severity", "Informational"),
            "confidence": item.get("confidence", "low"),
            "title": item.get("title", ""),
            "locations": locations,
            "claim": item.get("claim", ""),
            "impact": item.get("impact", ""),
            "paths": paths,
            "round": round_value,
            "source_agents": source_agents,
        }
        normalized.append(obj)
    return normalized


def normalize_rejected(items: list[dict]) -> list[dict]:
    normalized: list[dict] = []
    for item in items:
        if not isinstance(item, dict):
            continue

        source_agents = item.get("source_agents", [])
        if isinstance(source_agents, str):
            source_agents = [source_agents] if source_agents else []
        if not isinstance(source_agents, list):
            source_agents = []

        normalized.append(
            {
                "title": item.get("title", ""),
                "source_agents": source_agents,
                "reason": item.get("reason", ""),
            }
        )
    return normalized


def normalize_string(value: object) -> str:
    if not isinstance(value, str):
        return ""
    return " ".join(value.lower().split())


def extract_agent_signals(round_dir: Path) -> list[dict]:
    signals: list[dict] = []
    title_re = re.compile(r'"title"\s*:\s*"((?:[^"\\]|\\.)*)"')

    for agent_dir in sorted(round_dir.glob("agent_*")):
        agent_name = agent_dir.name.replace("agent_", "")
        stdout_path = agent_dir / "stdout.log"
        if not stdout_path.exists():
            continue
        text = stdout_path.read_text(encoding="utf-8", errors="replace")
        seen_titles: set[str] = set()
        for match in title_re.finditer(text):
            raw_title = match.group(1)
            try:
                title = json.loads(f'"{raw_title}"')
            except json.JSONDecodeError:
                title = raw_title
            title = title.strip()
            if not title or title in seen_titles:
                continue
            seen_titles.add(title)
            signals.append({"agent": agent_name, "title": title})
    return signals


def best_agent_match(title: str, signals: list[dict]) -> dict | None:
    title_norm = normalize_string(title)
    if not title_norm or not signals:
        return None

    best: dict | None = None
    best_score = 0.0
    for signal in signals:
        signal_title = signal.get("title", "")
        signal_norm = normalize_string(signal_title)
        if not signal_norm:
            continue
        score = difflib.SequenceMatcher(None, title_norm, signal_norm).ratio()
        if score > best_score:
            best_score = score
            best = {
                "agent": signal.get("agent", ""),
                "title": signal_title,
                "score": round(score, 3),
            }
    return best


def finding_changed(existing: dict, current: dict) -> bool:
    fields = ("severity", "confidence", "title", "locations", "claim", "impact", "paths")
    return any(existing.get(field) != current.get(field) for field in fields)


def classify_finding_action(item: dict, existing_by_id: dict[str, dict], match: dict | None) -> str:
    item_id = item.get("id")
    if isinstance(item_id, str) and item_id in existing_by_id:
        previous = existing_by_id[item_id]
        if finding_changed(previous, item):
            return "existing_rewritten"

        old_sources = previous.get("source_agents", [])
        new_sources = item.get("source_agents", [])
        if not isinstance(old_sources, list):
            old_sources = []
        if not isinstance(new_sources, list):
            new_sources = []
        if set(new_sources) - set(old_sources):
            return "existing_support_added"
        return "existing_preserved"

    sources = item.get("source_agents", [])
    if not isinstance(sources, list):
        sources = []
    source_set = {source for source in sources if isinstance(source, str)}
    match_score = float(match.get("score", 0.0)) if match else 0.0

    if source_set == {"merge_layer"}:
        return "merge_synthesized"
    if match_score >= 0.85:
        return "exact_agent_candidate"
    if match_score >= 0.55 or any(source != "merge_layer" for source in source_set):
        return "rewritten_agent_signal"
    if "merge_layer" in source_set:
        return "merge_synthesized"
    return "new_unmatched"


def classify_rejection_reason(reason: str) -> str:
    text = normalize_string(reason)
    if any(token in text for token in ("duplicate", "already captured", "subsumed", "overlap")):
        return "duplicate_or_subsumed"
    if any(token in text for token in ("owner", "governance", "trust-model", "authorized", "privileged")):
        return "trust_or_owner_model"
    if any(token in text for token in ("speculative", "unsupported", "insufficient", "not supported", "not shown")):
        return "unsupported_or_speculative"
    if any(token in text for token in ("factually incorrect", "incorrect", "premise is")):
        return "factually_incorrect"
    if any(token in text for token in ("operational", "observability", "gas", "self-grief", "low value")):
        return "low_impact_or_operational"
    return "other"


def md_escape(value: object) -> str:
    text = str(value) if value is not None else ""
    return text.replace("|", "\\|").replace("\n", " ")


def build_merge_view(
    round_dir: Path,
    round_num: int,
    existing: list[dict],
    findings: list[dict],
    rejected: list[dict],
) -> dict:
    existing_by_id = {
        item.get("id"): item
        for item in existing
        if isinstance(item, dict) and isinstance(item.get("id"), str) and item.get("id")
    }
    signals = extract_agent_signals(round_dir)

    finding_entries: list[dict] = []
    for item in findings:
        if not isinstance(item, dict):
            continue
        match = best_agent_match(item.get("title", ""), signals)
        action = classify_finding_action(item, existing_by_id, match)
        finding_entries.append(
            {
                "id": item.get("id", ""),
                "action": action,
                "severity": item.get("severity", ""),
                "confidence": item.get("confidence", ""),
                "title": item.get("title", ""),
                "source_agents": item.get("source_agents", []),
                "best_agent_match": match,
                "locations": item.get("locations", []),
            }
        )

    rejected_entries: list[dict] = []
    for item in rejected:
        if not isinstance(item, dict):
            continue
        reason = item.get("reason", "")
        rejected_entries.append(
            {
                "title": item.get("title", ""),
                "source_agents": item.get("source_agents", []),
                "reason_category": classify_rejection_reason(reason),
                "reason": reason,
            }
        )

    action_counts = Counter(entry["action"] for entry in finding_entries)
    rejection_counts = Counter(entry["reason_category"] for entry in rejected_entries)
    new_actions = {
        "exact_agent_candidate",
        "rewritten_agent_signal",
        "merge_synthesized",
        "new_unmatched",
    }

    return {
        "round": round_num,
        "summary": {
            "total_findings": len(finding_entries),
            "new_findings": sum(action_counts[action] for action in new_actions),
            "updated_existing_findings": action_counts["existing_rewritten"] + action_counts["existing_support_added"],
            "rejected_candidates": len(rejected_entries),
            "action_counts": dict(sorted(action_counts.items())),
            "rejection_reason_counts": dict(sorted(rejection_counts.items())),
        },
        "findings": finding_entries,
        "rejected_candidates": rejected_entries,
    }


def render_merge_view_md(view: dict) -> str:
    summary = view.get("summary", {})
    lines = [
        f"# Merge View - Round {view.get('round')}",
        "",
        "## Summary",
        f"- total findings: {summary.get('total_findings', 0)}",
        f"- new findings: {summary.get('new_findings', 0)}",
        f"- updated existing findings: {summary.get('updated_existing_findings', 0)}",
        f"- rejected candidates: {summary.get('rejected_candidates', 0)}",
        "",
        "## Finding Actions",
    ]
    action_counts = summary.get("action_counts", {})
    if isinstance(action_counts, dict) and action_counts:
        for key, value in action_counts.items():
            lines.append(f"- {key}: {value}")
    else:
        lines.append("- none")

    lines.extend(["", "## New Or Updated Findings"])
    changed = [
        entry
        for entry in view.get("findings", [])
        if isinstance(entry, dict) and entry.get("action") != "existing_preserved"
    ]
    if changed:
        lines.append("| id | action | severity | confidence | source | title | best match |")
        lines.append("| --- | --- | --- | --- | --- | --- | --- |")
        for entry in changed:
            match = entry.get("best_agent_match")
            if isinstance(match, dict) and match:
                best = f"{match.get('agent', '')}:{match.get('score', '')} {match.get('title', '')}"
            else:
                best = ""
            sources = ",".join(entry.get("source_agents", [])) if isinstance(entry.get("source_agents"), list) else ""
            lines.append(
                "| "
                + " | ".join(
                    [
                        md_escape(entry.get("id", "")),
                        md_escape(entry.get("action", "")),
                        md_escape(entry.get("severity", "")),
                        md_escape(entry.get("confidence", "")),
                        md_escape(sources),
                        md_escape(entry.get("title", "")),
                        md_escape(best),
                    ]
                )
                + " |"
            )
    else:
        lines.append("- none")

    lines.extend(["", "## Rejection Reasons"])
    rejection_counts = summary.get("rejection_reason_counts", {})
    if isinstance(rejection_counts, dict) and rejection_counts:
        for key, value in rejection_counts.items():
            lines.append(f"- {key}: {value}")
    else:
        lines.append("- none")

    rejected = [entry for entry in view.get("rejected_candidates", []) if isinstance(entry, dict)]
    if rejected:
        lines.extend(["", "## Rejected Candidates", "| category | source | title | reason |", "| --- | --- | --- | --- |"])
        for entry in rejected:
            sources = ",".join(entry.get("source_agents", [])) if isinstance(entry.get("source_agents"), list) else ""
            lines.append(
                "| "
                + " | ".join(
                    [
                        md_escape(entry.get("reason_category", "")),
                        md_escape(sources),
                        md_escape(entry.get("title", "")),
                        md_escape(entry.get("reason", "")),
                    ]
                )
                + " |"
            )

    return "\n".join(lines) + "\n"


def write_merge_view(
    round_dir: Path,
    round_num: int,
    existing: list[dict],
    findings: list[dict],
    rejected: list[dict],
) -> None:
    view = build_merge_view(round_dir, round_num, existing, findings, rejected)
    (round_dir / "merge_view.json").write_text(
        json.dumps(view, indent=2, ensure_ascii=True) + "\n",
        encoding="utf-8",
    )
    (round_dir / "merge_view.md").write_text(render_merge_view_md(view), encoding="utf-8")


def filter_by_include_scope(findings: list[dict], includes: list[str]) -> tuple[list[dict], list[dict]]:
    if not includes:
        return findings, []

    kept: list[dict] = []
    dropped: list[dict] = []
    for item in findings:
        locations = item.get("locations", [])
        if isinstance(locations, str):
            locations = [locations] if locations else []
        if not isinstance(locations, list):
            locations = []

        if not locations:
            kept.append(item)
            continue

        in_scope = any(
            is_included(extract_location_path(loc), includes)
            for loc in locations
            if isinstance(loc, str) and loc
        )
        if in_scope:
            kept.append(item)
            continue

        dropped.append(
            {
                "title": item.get("title", ""),
                "source_agents": item.get("source_agents", []) if isinstance(item.get("source_agents", []), list) else [],
                "reason": "root cause locations are outside included direct audit scope",
            }
        )
    return kept, dropped


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--round-dir", required=True)
    parser.add_argument("--target-dir", required=True)
    parser.add_argument("--acc", required=True)
    parser.add_argument("--round-num", type=int, required=True)
    parser.add_argument("--mode", choices=("manual", "codex"), default="codex")
    parser.add_argument("--model", default="o3")
    parser.add_argument("--exclude", action="append", default=[])
    parser.add_argument("--include", action="append", default=[])
    parser.add_argument("--output")
    parser.add_argument("--result-file")
    args = parser.parse_args()

    round_dir = Path(args.round_dir).resolve()
    target_dir = Path(args.target_dir).resolve()
    acc_path = Path(args.acc).resolve()
    output_path = Path(args.output).resolve() if args.output else acc_path

    existing = load_acc(acc_path)
    existing_round_by_id: dict[str, int] = {}
    for item in existing:
        if not isinstance(item, dict):
            continue
        item_id = item.get("id")
        item_round = item.get("round")
        if isinstance(item_id, str) and item_id and isinstance(item_round, int) and item_round > 0:
            existing_round_by_id[item_id] = item_round
    outputs = collect_outputs(round_dir)
    excludes = load_excludes(args.exclude)
    includes = load_includes(args.include)
    prompt = build_prompt(existing, outputs, excludes, includes)
    (round_dir / "merge_prompt.md").write_text(prompt, encoding="utf-8")

    if args.mode == "manual":
        if not args.result_file:
            print("Manual merge requested. Fill a JSON object with `findings` and `rejected_candidates`, then rerun with --result-file.", flush=True)
            return 0
        raw = Path(args.result_file).read_text(encoding="utf-8")
        items, rejected = extract_merge_result(raw)
    else:
        try:
            stdout, stderr = run_codex_merge(prompt, target_dir, args.model)
        except FileNotFoundError as exc:
            (round_dir / "merge_stderr.log").write_text(str(exc) + "\n", encoding="utf-8")
            raise SystemExit(str(exc))
        (round_dir / "merge_stdout.log").write_text(stdout, encoding="utf-8")
        (round_dir / "merge_stderr.log").write_text(stderr, encoding="utf-8")
        items, rejected = extract_merge_result(stdout)

    normalized = normalize_findings(items, args.round_num, existing_round_by_id)
    rejected_normalized = normalize_rejected(rejected)
    normalized, include_rejections = filter_by_include_scope(normalized, includes)
    rejected_normalized.extend(include_rejections)
    output_path.write_text(json.dumps(normalized, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
    (round_dir / "merge_rejections.json").write_text(
        json.dumps(rejected_normalized, indent=2, ensure_ascii=True) + "\n",
        encoding="utf-8",
    )
    write_merge_view(round_dir, args.round_num, existing, normalized, rejected_normalized)
    print(json.dumps({"total": len(normalized), "path": str(output_path)}, ensure_ascii=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
