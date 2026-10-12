-- Centre Split — one Hyprland 0.55+ custom layout: `lua:centre-split`.
--
-- WHY ONE LAYOUT. Hyprland 0.56.2 resolves a custom layout name loosely: with
-- two or more Lua layouts registered, every request returns the FIRST layout
-- registered, whatever name was asked for. One registration plus runtime
-- layout_msg commands is the only reliable way to offer several shapes. Do
-- not add a second hl.layout.register() here.
--
-- SHAPE MODEL (replaces the old named-preset system entirely). The shape is
-- chosen automatically by how many windows are open, never by a fixed name:
--
--   1 window   fullscreen, no quarters, no centre pane.
--   2 windows  even 50/50 -> 1/3+2/3 -> 2/3+1/3 -> half horizontal (top/bottom)
--   3 windows  even thirds -> one 2/3 pane + the other two stacked in 1/3
--   4+ windows square (2 even columns, windows distributed round-robin so it
--              grows into a real grid) -> one 2/3 pane + the rest stacked in 1/3
--
-- Each window count has a list of shape VARIANTS. Two things change which
-- variant is showing:
--   * auto-rotation: every time the number of open windows actually CHANGES
--     and lands on a given count, the next variant in that count's list is
--     selected (round-robin). No keypress. Re-arriving at "2 windows" later
--     shows a different variant than last time.
--   * manual cycle: the "cyclevariant" layout_msg (bound to SUPER+SHIFT+J,
--     separate from SUPER+J/togglesplit) advances the variant for however
--     many windows are open right now, on demand.
-- 5+ windows reuses the 4-window variant list; the stacking column just grows.
--
-- Safe to dofile from Hyprland: register() no-ops when `hl` is missing, so the
-- same file loads under plain lua for the geometry tests.

local M = {}

M.LAYOUT_NAME = "centre-split"

-- M.SHAPES[bucket] is the ordered variant list for that many windows.
-- bucket is window count clamped to [1,4] via M.bucket_for (5+ reuses [4]).
--
-- spec fields:
--   slots        column widths (or row heights when orientation="rows"),
--                fractions of the usable area, in position order.
--   fill         "order"      first N windows fill slots 1..N in order,
--                              extras pile into spec.extra (1-based slot).
--                "widest"     like "order" but windows fill the WIDEST slot
--                              first (so window 1 gets the big pane).
--                "distribute" EVERY window (any count) is assigned round-robin
--                              across all slots: window i -> slot ((i-1) %
--                              slot_count) + 1. This is what turns two even
--                              columns into a real 2x2+ grid as windows stack
--                              inside each column, instead of 1-per-column
--                              plus a single dumping slot.
--   extra        1-based slot index that windows beyond slot_count stack
--                into (fill="order"/"widest" only).
--   keep_place   with fewer windows than slots, keep each window in its
--                named slot instead of rescaling to fill the gap (used for
--                the 2/3+1/3 "widest" shapes so a lone extra window doesn't
--                collapse the ratio).
--   orientation  "rows" slices the area top-to-bottom instead of left-to-
--                right, and stacks within a row side-by-side instead of top-
--                to-bottom (the 2-window "half horizontal" shape).
M.SHAPES = {
  [1] = {
    { name = "fullscreen", slots = { 1 }, fill = "order" },
  },
  [2] = {
    { name = "even", slots = { 0.5, 0.5 }, fill = "order" },
    { name = "one-third-two-thirds", slots = { 1 / 3, 2 / 3 }, fill = "order" },
    { name = "two-thirds-one-third", slots = { 2 / 3, 1 / 3 }, fill = "order" },
    { name = "half-horizontal", slots = { 0.5, 0.5 }, fill = "order", orientation = "rows" },
  },
  [3] = {
    { name = "thirds", slots = { 1 / 3, 1 / 3, 1 / 3 }, fill = "order" },
    {
      name = "two-thirds-stack",
      slots = { 2 / 3, 1 / 3 },
      fill = "widest",
      extra = 2,
      keep_place = true,
    },
  },
  [4] = {
    { name = "square", slots = { 0.5, 0.5 }, fill = "distribute" },
    {
      name = "two-thirds-stack",
      slots = { 2 / 3, 1 / 3 },
      fill = "widest",
      extra = 2,
      keep_place = true,
    },
  },
}

-- Window count -> which SHAPES list applies. 0 windows has nothing to place.
function M.bucket_for(n)
  if n <= 0 then
    return 0
  end
  if n > 4 then
    return 4
  end
  return n
end

function M.shapes_for(n)
  local bucket = M.bucket_for(n)
  if bucket == 0 then
    return {}
  end
  return M.SHAPES[bucket]
end

-- Per-bucket "which variant is currently selected" (1-based index into
-- M.SHAPES[bucket]). 0 means "never selected yet" -- M.advance_variant moves
-- 0 -> 1 on first arrival, landing on the first/standard shape.
local state = {
  variant = { [1] = 0, [2] = 0, [3] = 0, [4] = 0 },
  last_count = 0,
}

function M.variant_index(bucket)
  local shapes = M.SHAPES[bucket]
  if not shapes or #shapes == 0 then
    return 0
  end
  local idx = state.variant[bucket] or 0
  if idx < 1 then
    idx = 1
  end
  if idx > #shapes then
    idx = ((idx - 1) % #shapes) + 1
  end
  return idx
end

function M.current_shape(n)
  local bucket = M.bucket_for(n)
  if bucket == 0 then
    return nil
  end
  local shapes = M.SHAPES[bucket]
  local idx = M.variant_index(bucket)
  if idx == 0 then
    return nil
  end
  return shapes[idx]
end

-- Advance bucket's variant by one step, wrapping. Used by both auto-rotation
-- (window count changed) and the manual "cyclevariant" message.
function M.advance_variant(bucket)
  local shapes = M.SHAPES[bucket]
  if not shapes or #shapes == 0 then
    return
  end
  local idx = state.variant[bucket] or 0
  state.variant[bucket] = (idx % #shapes) + 1
end

-- Test/restore-only hooks: exercise variant selection without a live ctx.
function M.set_variant(bucket, idx)
  local shapes = M.SHAPES[bucket]
  if not shapes or #shapes == 0 then
    return false
  end
  idx = ((idx - 1) % #shapes) + 1
  state.variant[bucket] = idx
  return true
end

function M.set_last_count(n)
  state.last_count = n
end

function M.last_count()
  return state.last_count
end

-- Slice the unit interval [x0, x1] out of a box's WIDTH. Ratios are taken
-- from the original box each time, so the arithmetic does not depend on
-- split order.
function M.slice_h(ctx, area, x0, x1)
  local box = area
  local span = 1 - x0
  if x0 > 0 then
    box = ctx:split(area, "right", span)
  end
  if x1 < 1 then
    box = ctx:split(box, "left", (x1 - x0) / span)
  end
  return box
end

-- Mirror of slice_h but slices a box's HEIGHT instead (for orientation="rows").
function M.slice_v(ctx, area, y0, y1)
  local box = area
  local span = 1 - y0
  if y0 > 0 then
    box = ctx:split(area, "bottom", span)
  end
  if y1 < 1 then
    box = ctx:split(box, "top", (y1 - y0) / span)
  end
  return box
end

-- Even vertical stack: split one target off at a time, topmost first.
function M.stack_v(ctx, targets, area)
  local n = #targets
  if n == 0 then
    return
  end
  if n == 1 then
    targets[1]:place(area)
    return
  end
  local ratio = 1 / n
  targets[1]:place(ctx:split(area, "top", ratio))
  local rest = {}
  for i = 2, n do
    rest[#rest + 1] = targets[i]
  end
  M.stack_v(ctx, rest, ctx:split(area, "bottom", 1 - ratio))
end

-- Mirror of stack_v but side-by-side (for orientation="rows", where a "row"
-- needs to subdivide horizontally instead of stacking vertically).
function M.stack_h(ctx, targets, area)
  local n = #targets
  if n == 0 then
    return
  end
  if n == 1 then
    targets[1]:place(area)
    return
  end
  local ratio = 1 / n
  targets[1]:place(ctx:split(area, "left", ratio))
  local rest = {}
  for i = 2, n do
    rest[#rest + 1] = targets[i]
  end
  M.stack_h(ctx, rest, ctx:split(area, "right", 1 - ratio))
end

function M.place(ctx, spec)
  local n = #ctx.targets
  if n == 0 then
    return
  end

  local slot_count = #spec.slots
  local groups = {}
  for i = 1, slot_count do
    groups[i] = {}
  end

  local function slot_ranges(widths)
    local ranges = {}
    local x = 0
    for i = 1, #widths do
      ranges[i] = { x0 = x, x1 = x + widths[i] }
      x = ranges[i].x1
    end
    return ranges
  end

  local function place_ranges(ranges)
    for i = 1, #ranges do
      if #groups[i] > 0 then
        if spec.orientation == "rows" then
          local area = M.slice_v(ctx, ctx.area, ranges[i].x0, ranges[i].x1)
          M.stack_h(ctx, groups[i], area)
        else
          local area = M.slice_h(ctx, ctx.area, ranges[i].x0, ranges[i].x1)
          M.stack_v(ctx, groups[i], area)
        end
      end
    end
  end

  if spec.fill == "distribute" then
    -- Round robin across ALL windows, any count: window i -> slot
    -- ((i-1) % slot_count) + 1. This is what makes the 4-window "square"
    -- a real grid (windows stack inside each column as more open) instead
    -- of 1-per-slot-plus-a-dumping-ground.
    for i = 1, n do
      local slot = ((i - 1) % slot_count) + 1
      groups[slot][#groups[slot] + 1] = ctx.targets[i]
    end
    place_ranges(slot_ranges(spec.slots))
    return
  end

  local function fill_order()
    local idx = {}
    for i = 1, slot_count do
      idx[i] = i
    end
    if spec.fill == "widest" then
      table.sort(idx, function(a, b)
        if spec.slots[a] ~= spec.slots[b] then
          return spec.slots[a] > spec.slots[b]
        end
        return a < b
      end)
    end
    return idx
  end

  local function rescale_widths(count)
    local used, total = {}, 0
    for i = 1, count do
      used[i] = spec.slots[i]
      total = total + used[i]
    end
    if total <= 0 then
      local even = 1 / count
      for i = 1, count do
        used[i] = even
      end
      return used
    end
    for i = 1, count do
      used[i] = used[i] / total
    end
    return used
  end

  local ranges
  if n >= slot_count then
    ranges = slot_ranges(spec.slots)
    local order = fill_order()
    for i = 1, slot_count do
      groups[order[i]][#groups[order[i]] + 1] = ctx.targets[i]
    end
    local extra = spec.extra
    if not extra or extra < 1 or extra > slot_count then
      extra = slot_count
    end
    for i = slot_count + 1, n do
      groups[extra][#groups[extra] + 1] = ctx.targets[i]
    end
  elseif spec.keep_place then
    ranges = slot_ranges(spec.slots)
    local order = fill_order()
    for i = 1, n do
      groups[order[i]][#groups[order[i]] + 1] = ctx.targets[i]
    end
  else
    ranges = slot_ranges(rescale_widths(n))
    for i = 1, n do
      groups[i][#groups[i] + 1] = ctx.targets[i]
    end
  end

  place_ranges(ranges)
end

local function recalculate(ctx)
  local n = #ctx.targets
  if n == 0 then
    return
  end
  local bucket = M.bucket_for(n)
  if n ~= state.last_count then
    -- A genuine change in window count (not just a resize/move recalc):
    -- auto-rotate to the next variant for the NEW count. First-ever arrival
    -- at a count (variant index 0) advances 0 -> 1, landing on the
    -- first/standard shape rather than skipping it.
    M.advance_variant(bucket)
    state.last_count = n
  end
  local shape = M.current_shape(n)
  if shape then
    M.place(ctx, shape)
  end
end

local function shell_quote(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

-- Persistence: a layout_msg dispatched straight at Hyprland (SUPER+J,
-- SUPER+SHIFT+J, or a hand-typed `hyprctl dispatch`) only ever mutates this
-- file's in-process `state` table. It never goes through `apply`, so without
-- this, `apply status` -- which reads ~/.config/omarchy/centre-split.json --
-- keeps reporting stale shape info even though the compositor has already
-- retiled. Schema: { shape: { variant: {"1":n,"2":n,"3":n,"4":n}, last_count:
-- n }, default: "...", workspaces: {...} }. default/workspaces are apply's
-- own fields and are preserved (merge, not overwrite).
local override_config_dir = nil

-- Test-only hook: point persistence at a scratch directory instead of the
-- real ~/.config/omarchy, so the regression suite can assert on the file
-- written by a direct dispatch without touching the user's actual state.
function M.set_config_dir_for_test(path)
  override_config_dir = path
end

local function state_paths()
  if override_config_dir then
    return override_config_dir, override_config_dir .. "/centre-split.json"
  end
  local xdg = os.getenv("XDG_CONFIG_HOME")
  local home = os.getenv("HOME") or "/root"
  local config_dir = ((xdg and xdg ~= "") and xdg or (home .. "/.config")) .. "/omarchy"
  return config_dir, config_dir .. "/centre-split.json"
end

local function persist_state()
  if os.getenv("CENTRE_SPLIT_NO_PERSIST") == "1" then
    return
  end
  local config_dir, state_file = state_paths()
  local qdir, qfile = shell_quote(config_dir), shell_quote(state_file)
  local variant_json = string.format(
    '{"1":%d,"2":%d,"3":%d,"4":%d}',
    state.variant[1] or 0,
    state.variant[2] or 0,
    state.variant[3] or 0,
    state.variant[4] or 0
  )
  local last_count = tostring(state.last_count or 0)
  local cmd = "mkdir -p " .. qdir .. " 2>/dev/null; "
    .. "tmp=$(mktemp " .. qdir .. "/centre-split.XXXXXX.json 2>/dev/null) || exit 0; "
    .. "if [ -s " .. qfile .. " ] && jq -e . " .. qfile .. " >/dev/null 2>&1; then "
    .. "jq --argjson variant '" .. variant_json .. "' --argjson lastcount " .. last_count .. " "
    .. "'.shape = {variant: $variant, last_count: $lastcount}' " .. qfile .. " >\"$tmp\" 2>/dev/null; "
    .. "else "
    .. "jq -n --argjson variant '" .. variant_json .. "' --argjson lastcount " .. last_count .. " "
    .. "'{shape: {variant: $variant, last_count: $lastcount}, default: \"\", workspaces: {}}' >\"$tmp\" 2>/dev/null; "
    .. "fi; "
    .. "if [ -s \"$tmp\" ] && jq -e . \"$tmp\" >/dev/null 2>&1; then mv \"$tmp\" " .. qfile .. "; else rm -f \"$tmp\"; fi"
  pcall(os.execute, cmd)
end

-- Surface a rejected layout_msg as a real toast. layout_msg rejections (a
-- non-true return) are swallowed by Hyprland's dispatch pipeline -- no crash,
-- no exception, exit code 0. Only fires when actually loaded inside Hyprland
-- (hl present), so the plain-Lua unit tests never shell out.
local function notify_reject(message)
  if not hl then
    return
  end
  if os.getenv("CENTRE_SPLIT_NOTIFY") == "0" then
    return
  end
  local headline = shell_quote("Centre split")
  local body = shell_quote(message)
  local cmd = "command -v omarchy-notification-send >/dev/null 2>&1 && "
    .. "omarchy-notification-send -u normal -t 6000 " .. headline .. " " .. body .. " >/dev/null 2>&1 || "
    .. "(command -v notify-send >/dev/null 2>&1 && "
    .. "notify-send -u normal -t 6000 -a 'Centre Split' " .. headline .. " " .. body .. " >/dev/null 2>&1) || true"
  pcall(os.execute, cmd)
end

local VALID_COMMANDS = "togglesplit, cyclevariant, reapply, or setvariant <1-4> <n>"

local function handle_message(ctx, msg)
  local text = tostring(msg or "")
  local command = text:match("^(%S+)") or ""

  if command == "togglesplit" then
    -- SUPER+J's default Omarchy binding. No shape-cycling here -- that's the
    -- dedicated "cyclevariant" command (SUPER+SHIFT+J) -- just a harmless
    -- forced reapply of whatever shape is already active for the current
    -- window count, so the keybind still does something useful.
    return true
  end

  if command == "cyclevariant" then
    -- Manual shape-cycle for the CURRENT window count. Bound to a dedicated
    -- keybind separate from togglesplit so SUPER+J's default behaviour is
    -- never ambiguous with deliberately picking a different shape.
    local n = #ctx.targets
    if n > 0 then
      M.advance_variant(M.bucket_for(n))
      state.last_count = n
      persist_state()
    end
    return true
  end

  if command == "reapply" then
    -- Handy from a keybinding: forces the layout to run again with no state
    -- change (recalculate() always runs after a truthy layout_msg return).
    return true
  end

  if command == "setvariant" then
    -- Restore-only: directly set bucket <1-4>'s variant index, so `apply
    -- restore` can rehydrate the saved shape after a reload wipes this
    -- module's in-process state. Not meant for interactive use.
    local bucket_str, idx_str = text:match("^%S+%s+(%d+)%s+(%d+)$")
    local bucket, idx = tonumber(bucket_str), tonumber(idx_str)
    if bucket and idx and M.SHAPES[bucket] and M.set_variant(bucket, idx) then
      return true
    end
    return "centre-split: usage: setvariant <1-4> <variant-index>"
  end

  local rejection = "centre-split: expected " .. VALID_COMMANDS
  local reason = (text == "" and rejection) or ("\"" .. text .. "\" not supported here \226\128\148 " .. rejection)
  notify_reject(reason)
  return rejection
end

-- Exposed for tests: handle_message is otherwise local so the compositor
-- call path is unambiguous.
M.handle_message = handle_message

-- Idempotent: Hyprland rejects a repeat registration with a Lua error, and this
-- file is loaded again on every shell start, Hyprland reload, and apply.
-- Returns a summary so callers can report a real failure instead of trusting a
-- zero exit code.
function M.register()
  local result = { registered = {}, skipped = {}, failed = {} }
  if not (hl and hl.layout and hl.layout.register) then
    result.unavailable = true
    return result
  end
  local ok, err = pcall(hl.layout.register, M.LAYOUT_NAME, {
    recalculate = recalculate,
    layout_msg = handle_message,
  })
  if ok then
    result.registered[#result.registered + 1] = M.LAYOUT_NAME
  elseif tostring(err):find("already registered", 1, true) then
    result.skipped[#result.skipped + 1] = M.LAYOUT_NAME
  else
    result.failed[#result.failed + 1] = M.LAYOUT_NAME .. ": " .. tostring(err)
  end
  return result
end

function M.summarise(result)
  if result.unavailable then
    return "Hyprland layout API unavailable (needs Hyprland 0.55+ with Lua layouts)"
  end
  if #result.failed > 0 then
    return "registration failed: " .. table.concat(result.failed, "; ")
  end
  if #result.skipped > 0 then
    return "already registered"
  end
  return "registered"
end

-- Register on load, so `dofile(path)` from hyprctl is the whole install step.
M.register()

-- `apply doctor`/`apply restore` reach this module through `hyprctl eval
-- "_CENTRE_SPLIT.<fn>(...)"` (eval shares Lua globals with the running
-- Hyprland session, unlike layout_msg which only reaches the registered
-- recalculate/layout_msg callbacks). Without this assignment that probe was
-- always reaching a nil global and silently failing.
_CENTRE_SPLIT = M

-- Note for anyone tempted to drive this from `hyprctl eval`: Hyprland keeps the
-- provider registered on the FIRST load, so a later dofile builds a second
-- module whose `state` the live provider never reads (register() pcalls, so the
-- blocked re-registration is not an error). eval also does not return values.
-- The shape only changes through a layout message -- `hl.dsp.layout("cyclevariant")`
-- -- and nowhere else.
return M
