#!/usr/bin/env bash
# Everything that can be checked without touching the compositor, then the live
# geometry proof.
#
#   tests/run_all.sh            # unit tests + live geometry
#   tests/run_all.sh --units    # unit tests only (no windows opened)
#   tests/run_all.sh --shots    # also save screenshots per live case
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UNITS_ONLY=0
SHOT_ARGS=()

for arg in "$@"; do
  case "$arg" in
    --units) UNITS_ONLY=1 ;;
    --shots) SHOT_ARGS+=(--shots) ;;
    *) echo "run_all: unknown option '$arg'" >&2; exit 1 ;;
  esac
done

echo "== manifest and shell syntax =="
omarchy plugin validate "$REPO"
bash -n "$REPO/apply"
python3 -c "import ast,pathlib; ast.parse(pathlib.Path('$REPO/tests/visual_test.py').read_text())"
echo "ok"
echo

echo "== layout geometry (no Hyprland needed) =="
lua "$REPO/tests/layout_test.lua"
echo

if ((UNITS_ONLY)); then
  echo "unit tests only; skipping the live geometry pass"
  exit 0
fi

echo "== live geometry on a scratch workspace =="
python3 "$REPO/tests/visual_test.py" "${SHOT_ARGS[@]+"${SHOT_ARGS[@]}"}"
echo

echo "== click path over IPC (the way the panel drives it) =="
bash "$REPO/tests/click_path.sh"