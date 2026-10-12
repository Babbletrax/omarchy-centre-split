.pragma library

// UI mirror of layouts.lua's shape model. layouts.lua is the source of
// truth for what Hyprland actually does; this file only draws the small
// preview and labels shown on the bar/panel.
//
// There is no fixed preset list any more: the shape is chosen automatically
// by how many windows are open (see layouts.lua's M.SHAPES) and rotates on
// its own as that count changes. The widget can only report what shape is
// currently showing (via `apply status`'s shape block: {windows, bucket,
// variant}) and offer "cycle to the next variant for this window count".

var LAYOUT = "lua:centre-split"

var BUCKET_LABELS = {
  0: "No windows",
  1: "Fullscreen",
  2: "2 windows",
  3: "3 windows",
  4: "4+ windows"
}

// Mirrors layouts.lua's M.SHAPES names, 1-indexed per bucket, for a plain-
// language variant label. Geometry itself is drawn generically below from
// windows/bucket alone, since the exact slot fractions live only in Lua.
var VARIANT_NAMES = {
  1: ["Fullscreen"],
  2: ["Even", "1/3 + 2/3", "2/3 + 1/3", "Half (top/bottom)"],
  3: ["Thirds", "2/3 + stacked pair"],
  4: ["Square", "2/3 + stacked column"]
}

function bucketLabel(bucket) {
  return BUCKET_LABELS[bucket] || BUCKET_LABELS[0]
}

function variantLabel(bucket, variant) {
  var names = VARIANT_NAMES[bucket]
  if (!names || !names.length) return ""
  var idx = (Number(variant) || 1) - 1
  if (idx < 0 || idx >= names.length) idx = 0
  return names[idx]
}

function shapeSummary(shape) {
  if (!shape) return "Split"
  var bucket = Number(shape.bucket) || 0
  if (bucket === 0) return "Split"
  var variant = variantLabel(bucket, shape.variant)
  return bucketLabel(bucket) + (variant ? " \u00b7 " + variant : "")
}

function isOurs(layout) {
  return String(layout || "") === LAYOUT
}
