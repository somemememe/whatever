#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
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

for d2_file in "$DIR"/[0-9][0-9]_*.d2; do
  base="${d2_file%.d2}"
  svg_file="${base}.svg"
  echo "Rendering SVG: $(basename "$d2_file")"
  d2 --layout=elk "$d2_file" "$svg_file"
  echo "  -> $(basename "$svg_file")"

  if [ "$RENDER_PDF" -eq 1 ]; then
    pdf_file="${base}.pdf"
    echo "Rendering PDF: $(basename "$d2_file")"
    d2 --layout=elk "$d2_file" "$pdf_file"
    echo "  -> $(basename "$pdf_file")"
  fi
done

echo "Done."
