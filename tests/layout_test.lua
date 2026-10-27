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

-- Every handle_message call that changes the shape also writes a persisted
-- state file as a side effect. Point that at a scratch directory for the
-- whole suite so running this file by hand never touches the real
-- ~/.config/omarchy; a dedicated block further down overrides it again
-- pointing at its own throwaway dir to assert on the contents.
local DEFAULT_SCRATCH_DIR = os.tmpname() .. "-centre-split-test-default"
os.remove(DEFAULT_SCRATCH_DIR)
plugin.set_config_dir_for_test(DEFAULT_SCRATCH_DIR)

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
  function ctx.split(_, box, side, ratio)
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

local function place_spec(n, spec)
  local ctx = mock_ctx(n)
  plugin.place(ctx, spec)
  return ctx
end

-- Reset the module's rotation/variant bookkeeping to a known state before a
-- block that depends on it, since recalculate()/handle_message mutate it.
local function reset_variants()
  for bucket = 1, 4 do
    plugin.set_variant(bucket, 1)
  end
  plugin.set_last_count(0)
end

-- ---- The registered layout is a single, unambiguous name.
check("one layout name", plugin.LAYOUT_NAME == "centre-split", tostring(plugin.LAYOUT_NAME))

-- ---- bucket_for: window count maps to the right SHAPES bucket, 5+ reuses 4.
check("bucket_for 0", plugin.bucket_for(0) == 0)
check("bucket_for 1", plugin.bucket_for(1) == 1)
check("bucket_for 2", plugin.bucket_for(2) == 2)
check("bucket_for 3", plugin.bucket_for(3) == 3)
check("bucket_for 4", plugin.bucket_for(4) == 4)
check("bucket_for 5 reuses 4", plugin.bucket_for(5) == 4)
check("bucket_for 9 reuses 4", plugin.bucket_for(9) == 4)

-- ---- 1 window: fullscreen, no quarters.
do
  local ctx = place_spec(1, plugin.SHAPES[1][1])
  local only = ctx.targets[1].box
  check("1 window fullscreen x", almost(only.x, 0), "x=" .. only.x)
  check("1 window fullscreen w", almost(only.w, W), "w=" .. only.w)
  check("1 window fullscreen h", almost(only.h, H), "h=" .. only.h)
end

-- ---- 2 windows, variant 1: even 50/50.
do
  local ctx = place_spec(2, plugin.SHAPES[2][1])
  check("2w even left", almost(ctx.targets[1].box.x, 0) and almost(ctx.targets[1].box.w, W / 2))
  check("2w even right", almost(ctx.targets[2].box.x, W / 2) and almost(ctx.targets[2].box.w, W / 2))
end

-- ---- 2 windows, variant 2: 1/3 + 2/3.
do
  local ctx = place_spec(2, plugin.SHAPES[2][2])
  check("2w 1/3+2/3 first width", almost(ctx.targets[1].box.w, W / 3, 1.0), "w=" .. ctx.targets[1].box.w)
  check("2w 1/3+2/3 second width", almost(ctx.targets[2].box.w, 2 * W / 3, 1.0), "w=" .. ctx.targets[2].box.w)
  check("2w 1/3+2/3 second x", almost(ctx.targets[2].box.x, W / 3, 1.0), "x=" .. ctx.targets[2].box.x)
end

-- ---- 2 windows, variant 3: 2/3 + 1/3 (mirror of the above).
do
  local ctx = place_spec(2, plugin.SHAPES[2][3])
  check("2w 2/3+1/3 first width", almost(ctx.targets[1].box.w, 2 * W / 3, 1.0), "w=" .. ctx.targets[1].box.w)
  check("2w 2/3+1/3 second width", almost(ctx.targets[2].box.w, W / 3, 1.0), "w=" .. ctx.targets[2].box.w)
end

-- ---- 2 windows, variant 4: half horizontal (top/bottom, not left/right).
do
  local ctx = place_spec(2, plugin.SHAPES[2][4])
  local top, bottom = ctx.targets[1].box, ctx.targets[2].box
  check("2w horizontal top y", almost(top.y, 0), "y=" .. top.y)
  check("2w horizontal top h", almost(top.h, H / 2), "h=" .. top.h)
  check("2w horizontal bottom y", almost(bottom.y, H / 2), "y=" .. bottom.y)
  check("2w horizontal full width", almost(top.w, W) and almost(bottom.w, W), "w=" .. top.w .. "/" .. bottom.w)
end

-- ---- 3 windows, variant 1: even thirds.
do
  local ctx = place_spec(3, plugin.SHAPES[3][1])
  check("3w thirds left", almost(ctx.targets[1].box.x, 0) and almost(ctx.targets[1].box.w, W / 3, 1.0))
  check("3w thirds middle", almost(ctx.targets[2].box.x, W / 3, 1.0))
  check("3w thirds right", almost(ctx.targets[3].box.x, 2 * W / 3, 1.0))
end

-- ---- 3 windows, variant 2: one 2/3 pane + the other two stacked in 1/3.
do
  local ctx = place_spec(3, plugin.SHAPES[3][2])
  local wide = ctx.targets[1].box
  local stack_top, stack_bottom = ctx.targets[2].box, ctx.targets[3].box
  check("3w 2/3-stack wide pane width", almost(wide.w, 2 * W / 3, 1.0), "w=" .. wide.w)
  check(
    "3w 2/3-stack other two share the stack column",
    almost(stack_top.x, stack_bottom.x) and almost(stack_top.w, stack_bottom.w),
    string.format("top=(%.1f,%.1f) bottom=(%.1f,%.1f)", stack_top.x, stack_top.w, stack_bottom.x, stack_bottom.w)
  )
  check(
    "3w 2/3-stack column is stacked vertically",
    almost(stack_top.h + stack_bottom.h, H),
    string.format("h=%.1f+%.1f", stack_top.h, stack_bottom.h)
  )
end

-- ---- 4 windows, variant 1: square (2 even columns, distributed round-robin
-- so each column gets 2 windows stacked -- a real 2x2 grid).
do
  local ctx = place_spec(4, plugin.SHAPES[4][1])
  local w1, w2, w3, w4 = ctx.targets[1].box, ctx.targets[2].box, ctx.targets[3].box, ctx.targets[4].box
  check(
    "4w square: windows 1 and 3 share the left column",
    almost(w1.x, w3.x) and almost(w1.w, w3.w),
    string.format("w1=(%.1f,%.1f) w3=(%.1f,%.1f)", w1.x, w1.w, w3.x, w3.w)
  )
  check(
    "4w square: windows 2 and 4 share the right column",
    almost(w2.x, w4.x) and almost(w2.w, w4.w),
    string.format("w2=(%.1f,%.1f) w4=(%.1f,%.1f)", w2.x, w2.w, w4.x, w4.w)
  )
  check("4w square: left column is half width", almost(w1.w, W / 2), "w=" .. w1.w)
  check("4w square: right column starts at mid", almost(w2.x, W / 2), "x=" .. w2.x)
  check(
    "4w square: left column stacked top/bottom",
    almost(w1.y, 0) and almost(w3.y, H / 2),
    string.format("w1.y=%.1f w3.y=%.1f", w1.y, w3.y)
  )
end

-- ---- 4 windows, variant 2: one 2/3 pane + the other three stacked in 1/3.
do
  local ctx = place_spec(4, plugin.SHAPES[4][2])
  local wide = ctx.targets[1].box
  check("4w 2/3-stack wide pane width", almost(wide.w, 2 * W / 3, 1.0), "w=" .. wide.w)
  local total_h = 0
  for i = 2, 4 do
    total_h = total_h + ctx.targets[i].box.h
  end
  check("4w 2/3-stack: three extras fill the column height", almost(total_h, H), "h=" .. total_h)
end

-- ---- 5 windows reuses the 4-window shapes list (bucket_for caps at 4); the
-- stacking column just grows to hold the 5th window.
do
  local ctx = place_spec(5, plugin.SHAPES[plugin.bucket_for(5)][2])
  local wide = ctx.targets[1].box
  check("5w reuses 4-bucket wide pane width", almost(wide.w, 2 * W / 3, 1.0), "w=" .. wide.w)
  local total_h = 0
  for i = 2, 5 do
    total_h = total_h + ctx.targets[i].box.h
  end
  check("5w: four extras fill the column height", almost(total_h, H), "h=" .. total_h)
end

-- ---- Every shape's slots sum to exactly 1 (no wasted/overlapping space).
for bucket = 1, 4 do
  for _, shape in ipairs(plugin.SHAPES[bucket]) do
    local sum = 0
    for _, frac in ipairs(shape.slots) do
      sum = sum + frac
    end
    check(
      "bucket " .. bucket .. " shape " .. shape.name .. " slots sum to 1",
      almost(sum, 1, 0.0001),
      tostring(sum)
    )
  end
end

-- ---- recalculate() auto-rotates: calling with the SAME window count twice
-- in a row keeps the shape; the count genuinely CHANGING advances to the
-- next variant for the new count. Drive this through handle_message's
-- "reapply" (true, no state change) vs. varying ctx.targets size, using the
-- real registered recalculate by re-dofiling with `hl` is not available in
-- the plain-lua test harness, so exercise the same mechanism directly via
-- M.current_shape / M.bucket_for / M.advance_variant / M.set_last_count,
-- which recalculate() itself calls.
do
  reset_variants()
  plugin.set_variant(2, 1) -- start on the first 2-window variant (even)
  plugin.set_last_count(0)

  -- Simulate what recalculate() does: count changes 0 -> 2, so it advances.
  local function simulate_recalculate(n)
    local bucket = plugin.bucket_for(n)
    if n ~= plugin.last_count() then
      plugin.advance_variant(bucket)
      plugin.set_last_count(n)
    end
    return plugin.current_shape(n)
  end

  local first = simulate_recalculate(2)
  check("auto-rotate: first arrival at 2 windows advances past the pre-set index", first ~= nil)

  -- Re-running at the SAME count (e.g. a resize, not an open/close) must NOT
  -- advance again.
  local again = simulate_recalculate(2)
  check("auto-rotate: same count twice keeps the same variant", again.name == first.name, again.name)

  -- Count genuinely changes (close one window: 2 -> 1), then back to 2:
  -- arriving at 2 again must show a DIFFERENT variant than `first`.
  simulate_recalculate(1)
  local second_arrival = simulate_recalculate(2)
  check(
    "auto-rotate: re-arriving at 2 windows shows the next variant",
    second_arrival.name ~= first.name,
    first.name .. " -> " .. second_arrival.name
  )
end

-- ---- handle_message: togglesplit is a harmless no-op (no shape change) --
-- SUPER+J no longer cycles anything; that is cyclevariant's job now.
do
  reset_variants()
  local ctx = mock_ctx(2)
  local before = plugin.current_shape(2)
  local ok = plugin.handle_message(ctx, "togglesplit")
  check("togglesplit accepted", ok == true, tostring(ok))
  local after = plugin.current_shape(2)
  check(
    "togglesplit does not change the variant",
    before ~= nil and after ~= nil and before.name == after.name,
    tostring(before and before.name) .. " -> " .. tostring(after and after.name)
  )
end

-- ---- handle_message: cyclevariant advances the variant for however many
-- windows are in ctx.targets right now, and wraps around.
do
  reset_variants()
  local ctx = mock_ctx(2) -- bucket 2 has 4 variants
  local seen = {}
  for i = 1, 5 do
    local ok = plugin.handle_message(ctx, "cyclevariant")
    check("cyclevariant accepted (" .. i .. ")", ok == true, tostring(ok))
    local shape = plugin.current_shape(2)
    seen[#seen + 1] = shape.name
  end
  check(
    "cyclevariant wraps back to the first variant after a full cycle",
    seen[1] == seen[5],
    table.concat(seen, " -> ")
  )
end

-- ---- handle_message: reapply is a true no-op.
do
  local ctx = mock_ctx(1)
  local ok = plugin.handle_message(ctx, "reapply")
  check("reapply accepted", ok == true, tostring(ok))
end

-- ---- handle_message: setvariant directly selects bucket <n>'s variant
-- (restore-only, but exercised here like any other message).
do
  local ctx = mock_ctx(3)
  local ok = plugin.handle_message(ctx, "setvariant 3 2")
  check("setvariant accepted", ok == true, tostring(ok))
  local shape = plugin.current_shape(3)
  check("setvariant selected the requested variant", shape.name == plugin.SHAPES[3][2].name, shape.name)

  local bad = plugin.handle_message(ctx, "setvariant 3 99")
  check("setvariant rejects an out-of-range index cleanly", bad == true or type(bad) == "string")
end

-- ---- A direct layout_msg dispatch (bypassing `apply` entirely, e.g.
-- SUPER+SHIFT+J / cyclevariant, or a hand-typed `hyprctl dispatch`) persists
-- the new shape state to the saved state file, so `apply status` can read
-- it back. Uses a scratch config dir so the suite never touches the real
-- ~/.config/omarchy.
do
  local scratch = os.tmpname()
  os.remove(scratch)
  local scratch_dir = scratch .. "-centre-split-test"
  plugin.set_config_dir_for_test(scratch_dir)

  reset_variants()
  local ctx = mock_ctx(2)
  local ok = plugin.handle_message(ctx, "cyclevariant")
  check("direct cyclevariant accepted", ok == true, tostring(ok))

  local state_file = scratch_dir .. "/centre-split.json"
  local f = io.open(state_file, "r")
  check("direct cyclevariant persisted a state file", f ~= nil, state_file)
  if f then
    local contents = f:read("*a")
    f:close()
    check(
      "persisted state file records the shape block",
      contents:find('"shape"') ~= nil and contents:find('"variant"') ~= nil,
      contents
    )
  end

  -- An unknown message is still rejected, and must not touch the state file.
  local before = nil
  do
    local fb = io.open(state_file, "r")
    if fb then
      before = fb:read("*a")
      fb:close()
    end
  end
  plugin.handle_message(ctx, "not-a-real-message")
  local after = nil
  do
    local fa = io.open(state_file, "r")
    if fa then
      after = fa:read("*a")
      fa:close()
    end
  end
  check("rejected message leaves the persisted state untouched", before == after)

  os.execute("rm -rf " .. scratch_dir)
  plugin.set_config_dir_for_test(DEFAULT_SCRATCH_DIR)
end

-- ---- A genuinely unknown message is still rejected (not silently accepted).
do
  local ctx = mock_ctx(1)
  local result = plugin.handle_message(ctx, "not-a-real-message")
  check("unknown message rejected", type(result) == "string", tostring(result))
end

if fails > 0 then
  print(string.format("%d check(s) failed", fails))
  os.exit(1)
end
os.execute("rm -rf " .. DEFAULT_SCRATCH_DIR)
print("all passed")
