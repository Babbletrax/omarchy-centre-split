-- Centre Split — one Hyprland 0.55+ custom layout: `lua:centre-split`.
--
-- WHY ONE LAYOUT. Hyprland 0.56.2 resolves a custom layout name loosely: with
-- two or more Lua layouts registered, every request returns the FIRST layout
-- registered, whatever name was asked for. Registering a family of layouts
-- therefore ships a plugin where Even/Thirds/Halves all silently run the same
-- shape. One registration plus a runtime preset message is the only reliable
-- way to offer several shapes. Do not add a second hl.layout.register() here.
--
-- Shapes (presets), switched at runtime through layout_msg:
--   qhq     1/4 | 1/2 | 1/4   first window takes the centre half (default)
--   even    equal columns
--   thirds  1/3 | 1/3 | 1/3
--   halves  1/2 | 1/2
--
-- Extra windows stack inside the preset's extra slot (the centre for qhq).
--
-- Presets are global to the plugin, not per workspace: only one name can be
-- registered, so a workspace either uses this layout or falls back to dwindle.
--
-- Safe to dofile from Hyprland: register() no-ops when `hl` is missing, so the
-- same file loads under plain lua for the geometry tests.

local M = {}

M.LAYOUT_NAME = "centre-split"

M.PRESETS = {
  qhq = {
    label = "1/4 · 1/2 · 1/4",
    slots = { 0.25, 0.50, 0.25 },
    keep_place = true, -- a lone window keeps the centre half instead of filling
    extra = 2,         -- 1-based: the half in the middle
    fill = "widest",   -- widest slot fills first, so window 1 gets the centre
  },
  even = {
    label = "Even",
    slots = { 0.50, 0.50 },
    keep_place = false,
    extra = 2,
    fill = "order",
  },
  thirds = {
    label = "Thirds",
    slots = { 1 / 3, 1 / 3, 1 / 3 },
    keep_place = false,
    extra = 2,
    fill = "order",
  },
  halves = {
    label = "Half",
    slots = { 0.50, 0.50 },
    keep_place = false,
    extra = 1,
    fill = "order",
  },
}

M.DEFAULT_PRESET = "qhq"

M.PRESET_NAMES = {}
do
  local names = {}
  for name in pairs(M.PRESETS) do
    names[#names + 1] = name
  end
  table.sort(names)
  M.PRESET_NAMES = names
end

local state = { preset = M.DEFAULT_PRESET }

function M.preset()
  return state.preset
end

function M.is_preset(name)
  return M.PRESETS[name] ~= nil
end

function M.set_preset(name)
  if not M.is_preset(name) then
    return false, "unknown preset: " .. tostring(name)
  end
  state.preset = name
  return true
end

-- Slice the unit interval [x0, x1] out of a box. Ratios are taken from the
-- original box each time, so the arithmetic does not depend on split order.
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

-- Even vertical stack: split one target off at a time, tallest first.
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
    if extra < 1 or extra > slot_count then
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

  for i = 1, #ranges do
    if #groups[i] > 0 then
      local area = M.slice_h(ctx, ctx.area, ranges[i].x0, ranges[i].x1)
      M.stack_v(ctx, groups[i], area)
    end
  end
end

local function recalculate(ctx)
  local spec = M.PRESETS[state.preset] or M.PRESETS[M.DEFAULT_PRESET]
  M.place(ctx, spec)
end

local function handle_message(ctx, msg)
  local text = tostring(msg or "")
  local command = text:match("^(%S+)") or ""
  if M.is_preset(command) then
    state.preset = command
    return true
  end
  if command == "preset" then
    local name = text:match("^%S+%s+(%S+)")
    if M.is_preset(name) then
      state.preset = name
      return true
    end
  end
  if command == "reapply" then
    -- Handy from a keybinding: forces the layout to run again.
    return true
  end
  return "centre-split: expected " .. table.concat(M.PRESET_NAMES, ", ") .. ", or preset <name>"
end

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

-- Note for anyone tempted to drive this from `hyprctl eval`: Hyprland keeps the
-- provider registered on the FIRST load, so a later dofile builds a second
-- module whose `state` the live provider never reads (register() pcalls, so the
-- blocked re-registration is not an error). eval also does not return values.
-- The preset is switched with a layout message -- `hl.dsp.layout("even")` -- and
-- nowhere else.
return M