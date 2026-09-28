#!/usr/bin/env bash
# Click-path test: drive the plugin the way the bar widget does, over IPC, and
# prove the split lands on the workspace you are actually looking at.
#
# The bug this exists for: the widget cached the focused workspace id, so a
# shape click could split a workspace you had since left, while the workspace on
# screen kept a half-drawn shape. Geometry alone would not have caught that --
# so this test also asserts that no unexpected workspace was touched.
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
fail() { printf '  FAIL  %s\n' "$1"; FAILURES=$((FAILURES + 1)); }

chem() { # geometry of this test's windows, sorted left to right
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
cleanup() {
  for a in $(hyprctl clients -j | jq -r --arg app "$APP" '.[] | select(.class == $app) | .address'); do
    hyprctl dispatch "hl.dsp.window.close({ window = \"address:$a\" })" >/dev/null
  done
  "$APPLY" release "$WS" >/dev/null 2>&1
  # The shape is global to the compositor, so switching it here re-tiles every
  # workspace that is split -- put the user's saved preset back.
  if [[ -n ${SAVED_PRESET:-} ]]; then
    "$APPLY" preset "$SAVED_PRESET" >/dev/null 2>&1
  fi
  sleep 0.5
  [[ -n ${ORIGINAL_WS:-} ]] && hyprctl dispatch "hl.dsp.focus({ workspace = \"$ORIGINAL_WS\" })" >/dev/null
}
trap cleanup EXIT INT TERM

ORIGINAL_WS="$(hyprctl activeworkspace -j | jq -r '.id')"
SAVED_PRESET="$("$APPLY" status 2>/dev/null | jq -r '.state.preset // "qhq"')"
BEFORE_STATE="$(state_workspaces | sort | tr '\n' ' ')"
echo "click-path test (workspace $WS, you were on $ORIGINAL_WS)"

# --- three real windows on the scratch workspace -----------------------------
hyprctl dispatch "hl.dsp.focus({ workspace = \"$WS\" })" >/dev/null; sleep 0.6
foot -a "$APP" -T CLICK-1 -e sleep 120 &
foot -a "$APP" -T CLICK-2 -e sleep 120 &
foot -a "$APP" -T CLICK-3 -e sleep 120 &
sleep 3
for a in $(hyprctl clients -j | jq -r --arg app "$APP" '.[] | select(.class == $app) | .address'); do
  hyprctl dispatch "hl.dsp.window.move({ window = \"address:$a\", workspace = \"$WS\", follow = false })" >/dev/null
done
sleep 1.5

found="$(chem | wc -l)"
[[ $found -eq 3 ]] && pass "three windows on workspace $WS" || fail "expected 3 windows, found $found"

# --- shape click (what the panel row does) -----------------------------------
omarchy-shell "$ID" shape qhq >/dev/null 2>&1
sleep 5
readarray -t g < <(chem)
ws_widths=(${g[0]:-0 0} ${g[1]:-0 0} ${g[2]:-0 0})
left="${g[0]:-0 0}"; mid="${g[1]:-0 0}"; right="${g[2]:-0 0}"
left_w="${left##* }"; mid_w="${mid##* }"; right_w="${right##* }"
ratio_ok() { # <a> <b> -- within 1.5% of each other
  python3 -c "import sys;a,b=int(sys.argv[1]),int(sys.argv[2]);sys.exit(0 if abs(a-b) <= max(a,b)*0.015 else 1)" "$1" "$2"
}
if ratio_ok "$left_w" "$right_w" && ((mid_w > left_w * 19 / 10)); then
  pass "shape qhq from the panel: $left_w / $mid_w / $right_w (wide pane centred)"
else
  fail "shape qhq geometry wrong: $left_w / $mid_w / $right_w"
fi
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
  fail "shape click also split workspace(s)$unexpected"
fi
[[ " $AFTER_STATE " == *" $WS "* ]] && pass "the focused workspace was the one split" \
  || fail "workspace $WS was never split"

# --- switching the shape on a live split -------------------------------------
omarchy-shell "$ID" shape thirds >/dev/null 2>&1
sleep 5
readarray -t g2 < <(chem)
w1="${g2[0]:-0 0}"; w2="${g2[1]:-0 0}"; w3="${g2[2]:-0 0}"
if ratio_ok "${w1##* }" "${w2##* }" && ratio_ok "${w2##* }" "${w3##* }"; then
  pass "shape thirds re-tiled every window: ${w1##* } / ${w2##* } / ${w3##* }"
else
  fail "thirds did not re-tile every window: ${w1##* } / ${w2##* } / ${w3##* }"
fi

# --- release -----------------------------------------------------------------
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