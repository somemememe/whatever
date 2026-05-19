#!/bin/bash
set -euo pipefail

resolve_codex_cli() {
  if command -v codex >/dev/null 2>&1; then
    command -v codex
    return 0
  fi

  local candidates=(
    "/Users/lu/.antigravity/extensions/openai.chatgpt-0.4.79-darwin-arm64/bin/macos-aarch64/codex"
    "$HOME/.antigravity/extensions/openai.chatgpt-0.4.79-darwin-arm64/bin/macos-aarch64/codex"
    "$HOME/.local/bin/codex"
    "/opt/homebrew/bin/codex"
    "/usr/local/bin/codex"
  )

  local path
  for path in "${candidates[@]}"; do
    if [ -x "$path" ]; then
      echo "$path"
      return 0
    fi
  done

  return 1
}

resolve_opencode_cli() {
  if command -v opencode >/dev/null 2>&1; then
    command -v opencode
    return 0
  fi

  local candidates=(
    "$HOME/.local/bin/opencode"
    "/opt/homebrew/bin/opencode"
    "/usr/local/bin/opencode"
  )

  local path
  for path in "${candidates[@]}"; do
    if [ -x "$path" ]; then
      echo "$path"
      return 0
    fi
  done

  return 1
}

AGENT_TYPE="${1:?Usage: run_agent.sh <agent_type> <round_dir> <target_dir> [model] [agent_label]}"
ROUND_DIR="${2:?Usage: run_agent.sh <agent_type> <round_dir> <target_dir> [model] [agent_label]}"
TARGET_DIR="${3:?Usage: run_agent.sh <agent_type> <round_dir> <target_dir> [model] [agent_label]}"
MODEL="${4:-${CODEX_MODEL:-gpt-5.4}}"
AGENT_LABEL="${5:-$AGENT_TYPE}"
REASONING_EFFORT="${CODEX_REASONING_EFFORT:-medium}"
CODEX_BIN="$(resolve_codex_cli || true)"
OPENCODE_BIN="$(resolve_opencode_cli || true)"

case "$AGENT_TYPE" in
  codex)
    MODEL="${AUDITHOUND_CODEX_MODEL:-$MODEL}"
    ;;
  opencode)
    MODEL="${AUDITHOUND_OPENCODE_MODEL:-$MODEL}"
    ;;
esac

AGENT_DIR="$ROUND_DIR/agent_$AGENT_LABEL"
PROMPT_FILE="$ROUND_DIR/prompt.md"

mkdir -p "$AGENT_DIR"

if [ ! -f "$PROMPT_FILE" ]; then
  echo "Prompt file not found: $PROMPT_FILE" >&2
  exit 1
fi

case "$AGENT_TYPE" in
  codex)
    if [ -z "$CODEX_BIN" ]; then
      echo "codex CLI not found" > "$AGENT_DIR/stdout.log"
      echo "codex CLI not found in PATH or known install locations" > "$AGENT_DIR/stderr.log"
      exit 1
    fi
    "$CODEX_BIN" -a never exec \
      --cd "$TARGET_DIR" \
      --sandbox workspace-write \
      --skip-git-repo-check \
      -m "$MODEL" \
      -c "model_reasoning_effort=\"$REASONING_EFFORT\"" \
      - < "$PROMPT_FILE" \
      > "$AGENT_DIR/stdout.log" 2> "$AGENT_DIR/stderr.log"
    ;;
  claude)
    echo "[claude integration not implemented yet]" > "$AGENT_DIR/stdout.log"
    : > "$AGENT_DIR/stderr.log"
    ;;
  opencode)
    if [ -z "$OPENCODE_BIN" ]; then
      echo "opencode CLI not found" > "$AGENT_DIR/stdout.log"
      echo "opencode CLI not found in PATH or known install locations" > "$AGENT_DIR/stderr.log"
      exit 1
    fi

    TASK_FILE="$AGENT_DIR/current_task.md"
    cp "$PROMPT_FILE" "$TASK_FILE"

    # Optional shared XDG root for opencode login/session state.
    # Default keeps per-worker isolation to avoid cross-worker DB contention.
    XDG_ROOT="${AUDITHOUND_OPENCODE_XDG_ROOT:-$AGENT_DIR/.opencode_xdg}"
    mkdir -p "$XDG_ROOT/data" "$XDG_ROOT/cache" "$XDG_ROOT/state" "$XDG_ROOT/config"

    XDG_DATA_HOME="$XDG_ROOT/data" \
    XDG_CACHE_HOME="$XDG_ROOT/cache" \
    XDG_STATE_HOME="$XDG_ROOT/state" \
    XDG_CONFIG_HOME="$XDG_ROOT/config" \
    "$OPENCODE_BIN" run \
      --dir "$TARGET_DIR" \
      --dangerously-skip-permissions \
      -m "$MODEL" \
      "Read the file at $TASK_FILE in full. Follow all instructions in that file exactly. Return only the JSON array specified there." \
      > "$AGENT_DIR/stdout.log" 2> "$AGENT_DIR/stderr.log"
    ;;
  *)
    echo "Unsupported agent type: $AGENT_TYPE" >&2
    exit 1
    ;;
esac
