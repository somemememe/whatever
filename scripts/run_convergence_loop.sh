#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="${1:?Usage: run_convergence_loop.sh <target_dir> [output_dir] [max_rounds] [converge_n] [merge_mode] [model] [codex_workers]}"
OUTPUT_DIR="${2:-$ROOT/output/$(basename "$TARGET_DIR")_$(date +%s)}"
MAX_ROUNDS="${3:-10}"
CONVERGE_N="${4:-2}"
MERGE_MODE="${5:-codex}"
MODEL="${6:-${CODEX_MODEL:-gpt-5.4}}"
CODEX_WORKERS="${7:-1}"
AGENT_TYPE="${AUDITHOUND_AGENT_TYPE:-codex}"
AGENT_TYPES_CSV="${AUDITHOUND_AGENT_TYPES:-}"
MERGE_MODEL="${AUDITHOUND_MERGE_MODEL:-$MODEL}"
SUMMARY_AGENT="${AUDITHOUND_SUMMARY_AGENT:-codex}"
SUMMARY_MODEL="${AUDITHOUND_SUMMARY_MODEL:-$MERGE_MODEL}"
RESUME="${AUDITHOUND_RESUME:-0}"
STATE_FILE="$OUTPUT_DIR/loop_state.json"

mkdir -p "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/rounds"

if [ ! -f "$OUTPUT_DIR/code_map.md" ]; then
  python3 "$ROOT/scripts/map_gen.py" "$TARGET_DIR" > "$OUTPUT_DIR/code_map.md"
fi

if [ ! -f "$OUTPUT_DIR/findings_acc.json" ]; then
  echo "[]" > "$OUTPUT_DIR/findings_acc.json"
fi

read_state_value() {
  local file="$1"
  local key="$2"
  python3 - "$file" "$key" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
key = sys.argv[2]

if not path.exists() or not path.read_text(encoding="utf-8").strip():
    print("")
    raise SystemExit(0)

data = json.loads(path.read_text(encoding="utf-8"))
value = data.get(key, "")
if isinstance(value, bool):
    print("true" if value else "false")
elif value is None:
    print("")
else:
    print(value)
PY
}

infer_last_completed_round() {
  python3 - "$OUTPUT_DIR/rounds" <<'PY'
import re
import sys
from pathlib import Path

rounds_dir = Path(sys.argv[1])
best = 0
for path in rounds_dir.glob("round_*"):
    if not path.is_dir():
        continue
    m = re.fullmatch(r"round_(\d+)", path.name)
    if not m:
        continue
    num = int(m.group(1))
    markers = [
        path / "round_state.json",
        path / "round_summary.md",
        path / "round_summary_stdout.log",
        path / "round_summary_stderr.log",
    ]
    if any(marker.exists() for marker in markers):
        best = max(best, num)
print(best)
PY
}

write_round_state() {
  local round_state_file="$1"
  local round_num="$2"
  local total_findings="$3"
  local delta="$4"
  local no_new_streak="$5"
  local converged="$6"

  python3 - "$round_state_file" "$STATE_FILE" "$round_num" "$total_findings" "$delta" "$no_new_streak" "$converged" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

round_state_file = Path(sys.argv[1])
loop_state_file = Path(sys.argv[2])
round_num = int(sys.argv[3])
total_findings = int(sys.argv[4])
delta = int(sys.argv[5])
no_new_streak = int(sys.argv[6])
converged = sys.argv[7].lower() == "true"
payload = {
    "last_completed_round": round_num,
    "last_total_findings": total_findings,
    "last_delta": delta,
    "no_new_streak": no_new_streak,
    "converged": converged,
    "updated_at": datetime.now(timezone.utc).isoformat(),
}
round_state_file.write_text(json.dumps(payload, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
loop_state_file.write_text(json.dumps(payload, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
PY
}

start_round=1
no_new=0

if [ "$RESUME" = "1" ]; then
  if [ -f "$STATE_FILE" ]; then
    last_completed="$(read_state_value "$STATE_FILE" "last_completed_round")"
    no_new_saved="$(read_state_value "$STATE_FILE" "no_new_streak")"
    converged_saved="$(read_state_value "$STATE_FILE" "converged")"
    start_round=$(( ${last_completed:-0} + 1 ))
    no_new="${no_new_saved:-0}"
    if [ "${converged_saved:-false}" = "true" ] && [ "$no_new" -ge "$CONVERGE_N" ]; then
      echo "Run already converged after round ${last_completed:-0}; nothing to resume."
      python3 "$ROOT/scripts/gen_report.py" \
        --findings "$OUTPUT_DIR/findings_acc.json" \
        --output "$OUTPUT_DIR/final_report.md"
      echo "Report written to $OUTPUT_DIR/final_report.md"
      exit 0
    fi
  else
    inferred_last_completed="$(infer_last_completed_round)"
    if [ "${inferred_last_completed:-0}" -gt 0 ]; then
      start_round=$(( inferred_last_completed + 1 ))
      no_new=0
      echo "Resuming legacy run without loop_state.json from round $start_round (no_new streak reset)."
    fi
  fi
fi

IFS=',' read -r -a AGENT_TYPES <<< "$AGENT_TYPES_CSV"

if [ "$start_round" -gt "$MAX_ROUNDS" ]; then
  echo "Nothing to do: start round $start_round is already beyond max rounds $MAX_ROUNDS."
  python3 "$ROOT/scripts/gen_report.py" \
    --findings "$OUTPUT_DIR/findings_acc.json" \
    --output "$OUTPUT_DIR/final_report.md"
  echo "Report written to $OUTPUT_DIR/final_report.md"
  exit 0
fi

for round in $(seq "$start_round" "$MAX_ROUNDS"); do
  RD="$OUTPUT_DIR/rounds/round_$round"
  if [ "$RESUME" = "1" ] && [ -d "$RD" ]; then
    BACKUP_DIR="$OUTPUT_DIR/rounds/round_${round}.resume_backup_$(date +%s)"
    mv "$RD" "$BACKUP_DIR"
    echo "Moved unfinished round directory to $BACKUP_DIR"
  fi
  mkdir -p "$RD"

  ROUND_SUMMARY_PATH=""
  if [ "$round" -gt 1 ]; then
    PREV_SUMMARY="$OUTPUT_DIR/rounds/round_$((round - 1))/round_summary.md"
    if [ -f "$PREV_SUMMARY" ]; then
      ROUND_SUMMARY_PATH="$PREV_SUMMARY"
    fi
  fi

  PROMPT_ARGS=(
    --map "$OUTPUT_DIR/code_map.md"
    --findings "$OUTPUT_DIR/findings_acc.json"
    --target "$TARGET_DIR"
    --output "$RD/prompt.md"
  )
  if [ -n "$ROUND_SUMMARY_PATH" ]; then
    PROMPT_ARGS+=(--round-summary "$ROUND_SUMMARY_PATH")
  fi
  if [ -f "$OUTPUT_DIR/global_summary.md" ]; then
    PROMPT_ARGS+=(--global-summary "$OUTPUT_DIR/global_summary.md")
  fi
  python3 "$ROOT/scripts/gen_prompt.py" "${PROMPT_ARGS[@]}"

  echo "=== Round $round ==="

  pids=()
  if [ -n "$AGENT_TYPES_CSV" ]; then
    codex_count=0
    opencode_count=0
    deepseek_count=0
    for agent in "${AGENT_TYPES[@]}"; do
      if [ -z "$agent" ]; then
        continue
      fi
      case "$agent" in
        codex)
          codex_count=$((codex_count + 1))
          label="${agent}_$codex_count"
          ;;
        opencode)
          opencode_count=$((opencode_count + 1))
          label="${agent}_$opencode_count"
          ;;
        deepseek)
          deepseek_count=$((deepseek_count + 1))
          label="${agent}_$deepseek_count"
          ;;
        *)
          echo "Unsupported agent type in AUDITHOUND_AGENT_TYPES: $agent" >&2
          exit 1
          ;;
      esac
      bash "$ROOT/scripts/run_agent.sh" "$agent" "$RD" "$TARGET_DIR" "$MODEL" "$label" &
      pids+=("$!")
    done
  else
    for worker in $(seq 1 "$CODEX_WORKERS"); do
      if [ "$CODEX_WORKERS" -eq 1 ]; then
        label="$AGENT_TYPE"
      else
        label="${AGENT_TYPE}_$worker"
      fi
      bash "$ROOT/scripts/run_agent.sh" "$AGENT_TYPE" "$RD" "$TARGET_DIR" "$MODEL" "$label" &
      pids+=("$!")
    done
  fi
  for pid in "${pids[@]}"; do
    wait "$pid"
  done

  prev=$(python3 -c "import json; from pathlib import Path; p=Path('$OUTPUT_DIR/findings_acc.json'); print(len(json.loads(p.read_text())))")

  python3 "$ROOT/scripts/merge.py" \
    --round-dir "$RD" \
    --target-dir "$TARGET_DIR" \
    --acc "$OUTPUT_DIR/findings_acc.json" \
    --round-num "$round" \
    --mode "$MERGE_MODE" \
    --model "$MERGE_MODEL"

  if ! python3 "$ROOT/scripts/summarize_round.py" \
    --round-dir "$RD" \
    --target-dir "$TARGET_DIR" \
    --findings "$OUTPUT_DIR/findings_acc.json" \
    --round-num "$round" \
    --agent "$SUMMARY_AGENT" \
    --model "$SUMMARY_MODEL" \
    --global-summary "$OUTPUT_DIR/global_summary.md"; then
    echo "Round $round summary failed" >&2
  fi

  curr=$(python3 -c "import json; from pathlib import Path; p=Path('$OUTPUT_DIR/findings_acc.json'); print(len(json.loads(p.read_text())))")
  delta=$((curr - prev))
  echo "Round $round done: +$delta findings (total: $curr)"

  if [ "$delta" -eq 0 ]; then
    no_new=$((no_new + 1))
  else
    no_new=0
  fi

  converged_now="false"
  if [ "$no_new" -ge "$CONVERGE_N" ]; then
    converged_now="true"
  fi

  write_round_state "$RD/round_state.json" "$round" "$curr" "$delta" "$no_new" "$converged_now"

  if [ "$no_new" -ge "$CONVERGE_N" ]; then
    echo "Converged after round $round"
    break
  fi
done

python3 "$ROOT/scripts/gen_report.py" \
  --findings "$OUTPUT_DIR/findings_acc.json" \
  --output "$OUTPUT_DIR/final_report.md"

echo "Report written to $OUTPUT_DIR/final_report.md"
