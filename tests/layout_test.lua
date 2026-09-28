-- Geometry tests for layouts.lua. Run: lua tests/layout_test.lua

local here = debug.getinfo(1, "S").source:gsub("^@", "")
local dir = here:match("(.*/)") or "./"
local plugin = dofile(dir .. "../layouts.lua")
if not plugin then
  error("layouts.lua did not return the module")
end

local function mock_ctx(n, w, h)
  w = w or 1000
  h = h or 400
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

-- 3 windows, 1/4 1/2 1/4: first window is the centre half
do
  local ctx = mock_ctx(3)
  plugin.place(ctx, plugin.PRESETS["centre-split"])
  local a, b, c = ctx.targets[1].box, ctx.targets[2].box, ctx.targets[3].box
  check("qhq centre x", almost(a.x, 250), "x=" .. a.x)
  check("qhq centre w", almost(a.w, 500), "w=" .. a.w)
  check("qhq left x", almost(b.x, 0), "x=" .. b.x)
  check("qhq left w", almost(b.w, 250), "w=" .. b.w)
  check("qhq right x", almost(c.x, 750), "x=" .. c.x)
  check("qhq right w", almost(c.w, 250), "w=" .. c.w)
  check("qhq full height", almost(a.h, 400) and almost(b.h, 400) and almost(c.h, 400))
end

-- 1 window keep-place: sits in the centre 50%, not stretched
do
  local ctx = mock_ctx(1)
  plugin.place(ctx, plugin.PRESETS["centre-split"])
  local a = ctx.targets[1].box
  check("one window centre x", almost(a.x, 250), "x=" .. a.x)
  check("one window centre w", almost(a.w, 500), "w=" .. a.w)
end

-- 2 windows keep-place: centre + left, right empty
do
  local ctx = mock_ctx(2)
  plugin.place(ctx, plugin.PRESETS["centre-split"])
  check("two windows centre", almost(ctx.targets[1].box.x, 250) and almost(ctx.targets[1].box.w, 500))
  check("two windows left", almost(ctx.targets[2].box.x, 0) and almost(ctx.targets[2].box.w, 250))
end

-- 4 windows: extra stacks in the centre
do
  local ctx = mock_ctx(4)
  plugin.place(ctx, plugin.PRESETS["centre-split"])
  local a, extra = ctx.targets[1].box, ctx.targets[4].box
  check("extra in centre x", almost(a.x, extra.x) and almost(a.w, extra.w),
    string.format("a=(%.1f,%.1f) extra=(%.1f,%.1f)", a.x, a.w, extra.x, extra.w))
  check("extra stacked vertically", almost(a.h + extra.h, 400), "h=" .. a.h .. "+" .. extra.h)
end

-- even, 1 window rescales to full
do
  local ctx = mock_ctx(1)
  plugin.place(ctx, plugin.PRESETS["centre-split-even"])
  check("even one window full", almost(ctx.targets[1].box.x, 0) and almost(ctx.targets[1].box.w, 1000))
end

-- thirds, 3 windows equal
do
  local ctx = mock_ctx(3)
  plugin.place(ctx, plugin.PRESETS["centre-split-thirds"])
  check("thirds left", almost(ctx.targets[1].box.x, 0) and almost(ctx.targets[1].box.w, 1000 / 3, 1.0))
  check("thirds mid", almost(ctx.targets[2].box.x, 1000 / 3, 1.0) and almost(ctx.targets[2].box.w, 1000 / 3, 1.0))
  check("thirds right", almost(ctx.targets[3].box.x, 2000 / 3, 1.0))
end

if fails > 0 then
  os.exit(1)
end
print("all passed")
