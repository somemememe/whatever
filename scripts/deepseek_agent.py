#!/usr/bin/env python3
"""DeepSeek agent — mimics codex exec interface, calls DeepSeek API directly.

Reads all Solidity source files from the target directory's onchain_auto
subdirectory and appends them to the prompt context, so the agent can
actually read the contracts it is auditing.
"""

import argparse
import json
import os
import sys
from pathlib import Path
from openai import OpenAI

MAX_SOURCE_CHARS = 120_000  # safety cap on appended source


def _walk_onchain_auto(target_dir: str) -> list[Path]:
    """Return all .sol files under <target_dir>/onchain_auto/."""
    base = Path(target_dir) / "onchain_auto"
    if not base.exists():
        return []
    files: list[Path] = []
    for sol_file in sorted(base.rglob("*.sol")):
        # Skip FlawVerifier templates and Counter templates
        if sol_file.name in ("FlawVerifier.sol", "Counter.sol"):
            continue
        if sol_file.parent.name in ("src", "test", "script", "out", "cache", "lib"):
            # Skip framework boilerplate
            if sol_file.name in ("FlawVerifier.sol", "Counter.sol"):
                continue
            # Keep other src files (might be part of the actual contract in rare cases)
            if sol_file.parent.name in ("test", "script", "out", "cache"):
                continue
        files.append(sol_file)
    return files


def _read_source_context(target_dir: str, max_chars: int = MAX_SOURCE_CHARS) -> str:
    """Build a source-code appendix from onchain_auto files."""
    files = _walk_onchain_auto(target_dir)
    if not files:
        return ""

    read_files: list[tuple[str, str]] = []  # (relpath, content)
    total = 0
    for f in files:
        try:
            content = f.read_text(encoding="utf-8", errors="replace")
        except Exception:
            continue
        rel = str(f.relative_to(Path(target_dir)))
        chunk = content[:50_000]  # per-file cap to avoid single 100k-line files
        read_files.append((rel, chunk))
        total += len(chunk)
        if total > max_chars:
            break

    if not read_files:
        return ""

    lines = [
        "\n\n## Source Code Appendix (auto-loaded from onchain_auto)\n",
        f"The following {len(read_files)} source files are available in the target directory. "
        "You MUST read and audit these files. All file paths and line numbers in your "
        "findings must reference these actual files, not invented ones.\n",
    ]
    for rel, content in read_files:
        lines.append(f"### File: {rel}\n```solidity\n{content}\n```\n")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--model",
        default=os.environ.get("AUDITHOUND_DEEPSEEK_MODEL", "deepseek-v4-pro"),
    )
    parser.add_argument("--reasoning-effort", default="medium")
    parser.add_argument(
        "--target-dir",
        default=os.environ.get("AUDITHOUND_TARGET_DIR", ""),
        help="Target directory containing onchain_auto/",
    )
    args = parser.parse_args()

    api_key = (
        os.environ.get("DEEPSEEK_API_KEY", "").strip()
        or os.environ.get("OPENAI_API_KEY", "").strip()
    )
    if not api_key:
        print("No API key found. Set DEEPSEEK_API_KEY or OPENAI_API_KEY.", file=sys.stderr)
        return 1

    base_url = os.environ.get("DEEPSEEK_BASE_URL", "https://api.deepseek.com/v1")
    client = OpenAI(api_key=api_key, base_url=base_url)

    prompt = sys.stdin.read()
    if not prompt.strip():
        print("Empty prompt received on stdin.", file=sys.stderr)
        return 1

    # Append source context so deepseek agent can actually read the contracts
    source_context = ""
    if args.target_dir:
        source_context = _read_source_context(args.target_dir)
        if source_context:
            prompt = prompt + source_context

    messages = [{"role": "user", "content": prompt}]

    try:
        response = client.chat.completions.create(
            model=args.model,
            messages=messages,
        )
        content = response.choices[0].message.content or ""
        print(content)
    except Exception as exc:
        print(f"DeepSeek API error: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
