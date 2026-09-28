-- Centre Split — Hyprland 0.55+ custom layouts.
--
-- lua:centre-split         1/4 | 1/2 | 1/4   (first window takes the centre)
-- lua:centre-split-even    equal columns
-- lua:centre-split-thirds  1/3 | 1/3 | 1/3
-- lua:centre-split-half    1/2 | 1/2
--
-- Extra windows stack inside the named extra slot (the centre for 1/4·1/2·1/4).
-- This file is safe to dofile from Hyprland; it no-ops register() when `hl`
-- is missing so the same file can be loaded by tests.

local M = {}

M.PRESETS = {
  ["centre-split"] = {
    slots = { 0.25, 0.50, 0.25 },
    keep_place = true,
    extra = 2, -- 1-based: the half in the middle
    fill = "widest",
  },
  ["centre-split-even"] = {
    slots = { 0.50, 0.50 },
    keep_place = false,
    extra = 2,
    fill = "order",
  },
  ["centre-split-thirds"] = {
    slots = { 1 / 3, 1 / 3, 1 / 3 },
    keep_place = false,
    extra = 2,
    fill = "order",
  },
  ["centre-split-half"] = {
    slots = { 0.50, 0.50 },
    keep_place = false,
    extra = 1,
    fill = "order",
  },
}

local function copy_box(box)
  return { x = box.x, y = box.y, w = box.w, h = box.h }
end

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

local function slot_ranges(widths)
  local ranges = {}
  local x = 0
  for i = 1, #widths do
    ranges[i] = { x0 = x, x1 = x + widths[i] }
    x = ranges[i].x1
  end
  return ranges
end

local function fill_order(spec)
  local n = #spec.slots
  local idx = {}
  for i = 1, n do
    idx[i] = i
  end
  if spec.fill == "widest" then
    table.sort(idx, function(a, b)
      local wa, wb = spec.slots[a], spec.slots[b]
      if wa ~= wb then
        return wa > wb
      end
      return a < b
    end)
  end
  return idx
end

local function rescale_widths(slots, count)
  local used = {}
  local total = 0
  for i = 1, count do
    used[i] = slots[i]
    total = total + slots[i]
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

  local ranges
  if n >= slot_count then
    ranges = slot_ranges(spec.slots)
    local order = fill_order(spec)
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
    local order = fill_order(spec)
    for i = 1, n do
      groups[order[i]][#groups[order[i]] + 1] = ctx.targets[i]
    end
  else
    local widths = rescale_widths(spec.slots, n)
    ranges = slot_ranges(widths)
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

function M.hypr_name(preset)
  return "lua:" .. preset
end

function M.register()
  if not (hl and hl.layout and hl.layout.register) then
    return false
  end
  for name, spec in pairs(M.PRESETS) do
    hl.layout.register(name, {
      recalculate = function(ctx)
        M.place(ctx, spec)
      end,
    })
  end
  return true
end

M.register()

return M
