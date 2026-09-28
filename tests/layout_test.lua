-- Geometry tests for layouts.lua. Run: lua tests/layout_test.lua
--
-- layouts.lua is loaded here without Hyprland: register() no-ops when `hl` is
-- missing, so the same code the compositor runs can be exercised with a mock
-- layout context.

local here = debug.getinfo(1, "S").source:gsub("^@", "")
local dir = here:match("(.*/)") or "./"
local plugin = dofile(dir .. "../layouts.lua")
if not plugin then
  error("layouts.lua did not return the module")
end

local W, H = 1000, 400

local function mock_ctx(n, w, h)
  w = w or W
  h = h or H
  local targets = {}
  for i = 1, n do
    targets[i] = {
      index = i,
      box = nil,
      place = function(self, box)
        self.box = { x = box.x, y = box.y, w = box.w, h = box.h }
      end,
    }
  end
  local ctx = {
    area = { x = 0, y = 0, w = w, h = h },
    targets = targets,
  }
  function ctx:split(box, side, ratio)
    if side == "left" then
      return { x = box.x, y = box.y, w = box.w * ratio, h = box.h }
    elseif side == "right" then
      return { x = box.x + box.w * (1 - ratio), y = box.y, w = box.w * ratio, h = box.h }
    elseif side == "top" then
      return { x = box.x, y = box.y, w = box.w, h = box.h * ratio }
    elseif side == "bottom" then
      return { x = box.x, y = box.y + box.h * (1 - ratio), w = box.w, h = box.h * ratio }
    end
    error("bad side " .. tostring(side))
  end
  return ctx
end

local function almost(a, b, eps)
  eps = eps or 0.51
  return math.abs(a - b) <= eps
end

local fails = 0
local function check(name, cond, detail)
  if cond then
    print("ok  " .. name)
  else
    fails = fails + 1
    print("FAIL  " .. name .. "  " .. (detail or ""))
  end
end

local function place(n, preset)
  local ctx = mock_ctx(n)
  plugin.place(ctx, plugin.PRESETS[preset])
  return ctx
end

-- ---- The registered layout is a single, unambiguous name.
check("one layout name", plugin.LAYOUT_NAME == "centre-split", tostring(plugin.LAYOUT_NAME))
check("four presets", #plugin.PRESET_NAMES == 4, table.concat(plugin.PRESET_NAMES, ","))

-- ---- Preset bookkeeping.
check("default preset is qhq", plugin.preset() == plugin.DEFAULT_PRESET, plugin.preset())
check("set_preset accepts a known name", plugin.set_preset("even") == true)
check("set_preset took effect", plugin.preset() == "even", plugin.preset())
local ok, err = plugin.set_preset("nonsense")
check("set_preset rejects an unknown name", ok == false and type(err) == "string", tostring(err))
check("preset unchanged after a rejected set", plugin.preset() == "even", plugin.preset())
plugin.set_preset("qhq")

-- ---- qhq (1/4 | 1/2 | 1/4), three windows: the centre half gets window 1.
do
  local ctx = place(3, "qhq")
  local centre, left, right = ctx.targets[1].box, ctx.targets[2].box, ctx.targets[3].box
  check("qhq centre x", almost(centre.x, 250), "x=" .. centre.x)
  check("qhq centre w", almost(centre.w, 500), "w=" .. centre.w)
  check("qhq left x", almost(left.x, 0), "x=" .. left.x)
  check("qhq left w", almost(left.w, 250), "w=" .. left.w)
  check("qhq right x", almost(right.x, 750), "x=" .. right.x)
  check("qhq right w", almost(right.w, 250), "w=" .. right.w)
  check(
    "qhq full height",
    almost(centre.h, H) and almost(left.h, H) and almost(right.h, H),
    string.format("%s/%s/%s", centre.h, left.h, right.h)
  )
end

-- ---- qhq with one window keeps the centre half (no rescale to fullscreen).
do
  local ctx = place(1, "qhq")
  local only = ctx.targets[1].box
  check("one window stays centre x", almost(only.x, 250), "x=" .. only.x)
  check("one window stays centre w", almost(only.w, 500), "w=" .. only.w)
  check("one window full height", almost(only.h, H), "h=" .. only.h)
end

-- ---- qhq with two windows: centre, then the left quarter.
do
  local ctx = place(2, "qhq")
  check(
    "two windows: centre first",
    almost(ctx.targets[1].box.x, 250) and almost(ctx.targets[1].box.w, 500)
  )
  check(
    "two windows: then left",
    almost(ctx.targets[2].box.x, 0) and almost(ctx.targets[2].box.w, 250)
  )
end

-- ---- qhq with four windows: the extra stacks inside the centre half.
do
  local ctx = place(4, "qhq")
  local first, extra = ctx.targets[1].box, ctx.targets[4].box
  check(
    "extra shares the centre column",
    almost(first.x, extra.x) and almost(first.w, extra.w),
    string.format("first=(%.1f,%.1f) extra=(%.1f,%.1f)", first.x, first.w, extra.x, extra.w)
  )
  check(
    "extra stacks vertically in it",
    almost(first.h + extra.h, H),
    string.format("h=%.1f+%.1f", first.h, extra.h)
  )
  check("centre stack starts at the top", almost(first.y, 0), "y=" .. first.y)
  check("extra sits below", almost(extra.y, H / 2), "y=" .. extra.y)
end

-- ---- even: one window fills the screen, two split evenly.
do
  local one = place(1, "even")
  check(
    "even one window fills",
    almost(one.targets[1].box.x, 0) and almost(one.targets[1].box.w, W)
  )
  local two = place(2, "even")
  check(
    "even two windows",
    almost(two.targets[1].box.w, W / 2) and almost(two.targets[2].box.x, W / 2)
  )
end

-- ---- thirds: three equal columns, left to right.
do
  local ctx = place(3, "thirds")
  check(
    "thirds left",
    almost(ctx.targets[1].box.x, 0) and almost(ctx.targets[1].box.w, W / 3, 1.0)
  )
  check(
    "thirds middle",
    almost(ctx.targets[2].box.x, W / 3, 1.0) and almost(ctx.targets[2].box.w, W / 3, 1.0)
  )
  check("thirds right", almost(ctx.targets[3].box.x, 2000 / 3, 1.0))
end

-- ---- halves: plain 50/50, and a lone window fills.
do
  local ctx = place(2, "halves")
  check("halves left", almost(ctx.targets[1].box.x, 0) and almost(ctx.targets[1].box.w, W / 2))
  check("halves right", almost(ctx.targets[2].box.x, W / 2))
  local one = place(1, "halves")
  check("halves one window fills", almost(one.targets[1].box.w, W))
end

-- ---- Every preset accounts for exactly the whole width.
for _, name in ipairs(plugin.PRESET_NAMES) do
  local sum = 0
  for _, frac in ipairs(plugin.PRESETS[name].slots) do
    sum = sum + frac
  end
  check("preset " .. name .. " slots sum to 1", almost(sum, 1, 0.0001), tostring(sum))
end

if fails > 0 then
  print(string.format("%d check(s) failed", fails))
  os.exit(1)
end
print("all passed")