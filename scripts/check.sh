#!/usr/bin/env bash
# Run every check CI runs. Tools that are missing locally are skipped with a
# note; CI installs all of them. Usage: scripts/check.sh [--strict]
set -euo pipefail

cd "$(dirname "$0")/.."
strict=0
[[ ${1:-} == --strict ]] && strict=1
failed=0

note() { printf '\n== %s\n' "$*"; }
skip() {
  echo "skipped: $1 not installed"
  if ((strict)); then failed=1; fi
}
run() { "$@" || failed=1; }

note "manifest"
if command -v jq >/dev/null; then
  run jq -e '
    .schemaVersion == 1 and (.id | test("^[A-Za-z0-9][A-Za-z0-9._-]*$")) and (.id | startswith("omarchy.") | not)
    and (.kinds | index("bar-widget")) != null and (.entryPoints.barWidget | type == "string")
    and (.kinds | index("service")) != null and (.entryPoints.service | type == "string")
  ' manifest.json >/dev/null
  for entry in $(jq -r '.entryPoints[]' manifest.json); do run test -f "$entry"; done
  if command -v omarchy-plugin-validate >/dev/null; then run omarchy-plugin-validate .; fi
  link=$(find . -name .git -prune -o -type l -print -quit)
  [[ -z $link ]] || {
    echo "symlink not allowed in a plugin: $link"
    failed=1
  }
else skip jq; fi

note "lua: layouts.lua"
luac=$(command -v luac || command -v luac5.4 || true)
if [[ -n $luac ]]; then run "$luac" -p layouts.lua tests/layout_test.lua; else skip luac; fi
if command -v luacheck >/dev/null; then
  run luacheck --no-color layouts.lua tests/layout_test.lua
else skip luacheck; fi

note "layout geometry tests (no compositor)"
lua=$(command -v lua || command -v lua5.4 || true)
if [[ -n $lua ]]; then run "$lua" tests/layout_test.lua; else skip lua; fi

note "python syntax"
run python3 -I -B -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" tests/visual_test.py

note "Model.js syntax (node)"
if command -v node >/dev/null; then
  # QML JavaScript libraries start with a .pragma line that plain JS rejects.
  tmp=$(mktemp --suffix=.js)
  sed 's/^\.pragma .*$//' Model.js >"$tmp"
  run node --check "$tmp"
  rm -f "$tmp"
else skip node; fi

note "qmllint"
qtbin=/usr/lib/qt6/bin
qmllint=$(command -v qmllint6 || command -v qmllint || echo "$qtbin/qmllint")
qmlformat=$(command -v qmlformat6 || command -v qmlformat || echo "$qtbin/qmlformat")
qml_files=(BarWidget.qml Panel.qml Service.qml)
if [[ -x $qmllint ]] && "$qmllint" --help 2>&1 | grep -- --max-warnings >/dev/null; then
  # Quickshell/Omarchy modules (qs.*, Quickshell) are not available to qmllint
  # outside the shell, so only syntax and hard errors fail the build.
  run "$qmllint" --silent --max-warnings -1 "${qml_files[@]}"
elif [[ -x $qmlformat ]]; then
  # Older Qt (6.4) qmllint fails on any warning; use the QML parser instead.
  echo "qmllint without --max-warnings; syntax check with qmlformat"
  for f in "${qml_files[@]}"; do run "$qmlformat" "$f" >/dev/null; done
else skip qmllint; fi

note "shell scripts"
mapfile -t scripts < <({
  echo apply
  find . -name '*.sh' -not -path './.git/*'
} | sed 's|^\./||' | sort)
for f in "${scripts[@]}"; do run bash -n "$f"; done
if command -v shellcheck >/dev/null; then run shellcheck "${scripts[@]}"; else skip shellcheck; fi
if command -v shfmt >/dev/null && shfmt --version >/dev/null 2>&1; then
  run shfmt -d -i 2 -ci -bn "${scripts[@]}"
else skip shfmt; fi

note "private-info scan"
run scripts/private-scan.sh

note "gitleaks"
if gitleaks version >/dev/null 2>&1; then
  run gitleaks detect --no-banner --redact --source . --log-level warn
else skip gitleaks; fi

if ((failed)); then
  echo
  echo "checks FAILED"
  exit 1
fi
echo
echo "all checks passed"
