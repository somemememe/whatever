#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
D2_FILE="$DIR/agent_architecture.d2"
SVG_FILE="$DIR/agent_architecture.svg"
PDF_FILE="$DIR/agent_architecture.pdf"

RENDER_PDF=0
if [ "${1:-}" = "--pdf" ]; then
  RENDER_PDF=1
fi

if ! command -v d2 >/dev/null 2>&1; then
  echo "d2 is not installed. Install it first (e.g. brew install d2)." >&2
  exit 1
fi

if ! command -v dot >/dev/null 2>&1; then
  echo "graphviz is not installed. Install it first (e.g. brew install graphviz)." >&2
  exit 1
fi

echo "Rendering SVG..."
d2 --layout=elk "$D2_FILE" "$SVG_FILE"
echo "SVG ready: $SVG_FILE"

if [ "$RENDER_PDF" -eq 1 ]; then
  echo "Rendering PDF..."
  d2 --layout=elk "$D2_FILE" "$PDF_FILE"
  echo "PDF ready: $PDF_FILE"
else
  echo "Skip PDF (pass --pdf to render)."
fi
