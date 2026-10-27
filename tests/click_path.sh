#!/usr/bin/env bash
# pass and fail always succeed, so `cond && pass || fail` is a safe if/else.
# shellcheck disable=SC2015
# Click-path test: drive the plugin the way the bar widget does, over IPC, and
# prove the shape lands on the workspace you are actually looking at.
#
# The bug this exists for: the widget cached the focused workspace id, so a
# panel click could split a workspace you had since left, while the workspace
# on screen kept a half-drawn shape. Geometry alone would not have caught
# that -- so this test also asserts no unexpected workspace was touched.
#
# There is no fixed preset list any more: shape is chosen by window count and
# rotates automatically, so "shape qhq" is gone. This exercises the real
# panel/IPC surface instead: `apply`, `shape cyclevariant` (the panel's one
# shape action, same as SUPER+SHIFT+J), and `release`.
#
# Requires a running omarchy shell (the plugin's IPC handler lives there) and
# foot for the throwaway windows.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPLY="$REPO/apply"
ID="io.github.babbletrax.centre-split"
WS="${CENTRE_SPLIT_TEST_WS:-90}"
APP="cs-click"
FAILURES=0

pass() { printf '  ok    %s\n' "$1"; }
fail() {
  printf '  FAIL  %s\n' "$1"
  FAILURES=$((FAILURES + 1))
}

geom() { # geometry of this test's windows, sorted left to right
  hyprctl clients -j | jq -r --argjson ws "$WS" --arg app "$APP" \
    '[.[] | select(.workspace.id == $ws and .class == $app)]
     | sort_by(.at[0]) | .[] | "\(.at[0]) \(.size[0])"' 2>/dev/null
}
layout_of() {
  hyprctl workspaces -j | jq -r --argjson ws "$WS" '.[] | select(.id == $ws) | .tiledLayout' 2>/dev/null
}
state_workspaces() {
  "$APPLY" status 2>/dev/null | jq -r '.state.workspaces // {} | keys[]' 2>/dev/null
}
# shellcheck disable=SC2329 # invoked by the EXIT trap
cleanup() {
  for a in $(hyprctl clients -j | jq -r --arg app "$APP" '.[] | select(.class == $app) | .address'); do
    hyprctl dispatch "hl.dsp.window.close({ window = \"address:$a\" })" >/dev/null
  done
  "$APPLY" release "$WS" >/dev/null 2>&1
  sleep 0.5
  [[ -n ${ORIGINAL_WS:-} ]] && hyprctl dispatch "hl.dsp.focus({ workspace = \"$ORIGINAL_WS\" })" >/dev/null
}
trap cleanup EXIT INT TERM

ORIGINAL_WS="$(hyprctl activeworkspace -j | jq -r '.id')"
BEFORE_STATE="$(state_workspaces | sort | tr '\n' ' ')"
echo "click-path test (workspace $WS, you were on $ORIGINAL_WS)"

# --- two real windows on the scratch workspace --------------------------------
# 2 windows exercises the richest variant list (4 shapes), so cyclevariant has
# the most room to prove it actually moved something.
hyprctl dispatch "hl.dsp.focus({ workspace = \"$WS\" })" >/dev/null
sleep 0.6
foot -a "$APP" -T CLICK-1 -e sleep 120 &
foot -a "$APP" -T CLICK-2 -e sleep 120 &
sleep 3
for a in $(hyprctl clients -j | jq -r --arg app "$APP" '.[] | select(.class == $app) | .address'); do
  hyprctl dispatch "hl.dsp.window.move({ window = \"address:$a\", workspace = \"$WS\", follow = false })" >/dev/null
done
sleep 1.5

found="$(geom | wc -l)"
[[ $found -eq 2 ]] && pass "two windows on workspace $WS" || fail "expected 2 windows, found $found"

# --- apply (what "Split this workspace" does) --------------------------------
omarchy-shell "$ID" apply >/dev/null 2>&1
sleep 5
[[ "$(layout_of)" == "lua:centre-split" ]] && pass "workspace reports the plugin layout" \
  || fail "workspace reports '$(layout_of)' instead of lua:centre-split"

# --- the regression: which workspace did it actually touch? ------------------
AFTER_STATE="$(state_workspaces | sort | tr '\n' ' ')"
unexpected=""
for ws in $AFTER_STATE; do
  [[ " $BEFORE_STATE " == *" $ws "* ]] && continue
  [[ $ws == "$WS" ]] && continue
  unexpected="$unexpected $ws"
done
if [[ -z $unexpected ]]; then
  pass "only workspace $WS was split (no stale-id damage)"
else
  fail "apply also split workspace(s)$unexpected"
fi
[[ " $AFTER_STATE " == *" $WS "* ]] && pass "the focused workspace was the one split" \
  || fail "workspace $WS was never split"

# --- cyclevariant (what the panel's shape button / SUPER+SHIFT+J does) -------
readarray -t before < <(geom)
before_w1="${before[0]##* }"
before_w2="${before[1]##* }"

omarchy-shell "$ID" shape cyclevariant >/dev/null 2>&1
sleep 2
readarray -t after < <(geom)
after_w1="${after[0]##* }"
after_w2="${after[1]##* }"

if [[ "$before_w1 $before_w2" != "$after_w1 $after_w2" ]]; then
  pass "cyclevariant re-tiled the workspace: $before_w1/$before_w2 -> $after_w1/$after_w2"
else
  fail "cyclevariant did not change the geometry ($before_w1/$before_w2 unchanged)"
fi
[[ "$(layout_of)" == "lua:centre-split" ]] && pass "still reports the plugin layout after cycling" \
  || fail "lost the plugin layout after cycling (reports '$(layout_of)')"

# --- release -------------------------------------------------------------------
omarchy-shell "$ID" release >/dev/null 2>&1
sleep 5
if [[ "$(layout_of)" == "dwindle" ]]; then
  pass "release puts the workspace back on dwindle"
else
  fail "release left the workspace on '$(layout_of)'"
fi
leftover="$("$APPLY" status 2>/dev/null | jq -r '.state.workspaces // {} | keys[] | select(. == "'"$WS"'")')"
[[ -z $leftover ]] && pass "workspace $WS removed from the saved state" \
  || fail "workspace $WS still saved after release"

echo
if ((FAILURES == 0)); then
  echo "click-path: all checks passed"
else
  echo "click-path: $FAILURES check(s) failed"
fi
exit $((FAILURES > 0))
