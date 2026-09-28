.pragma library

// UI mirror of the presets in layouts.lua. layouts.lua is the source of truth
// for what Hyprland actually does; this file only draws the thumbnails and
// labels. Adding a preset means touching three places: layouts.lua (geometry),
// PRESETS in the apply helper (validation and labels), and this list (UI).

var LAYOUT = "lua:centre-split"

var PRESETS = [
  {
    id: "qhq",
    name: "1/4 · 1/2 · 1/4",
    detail: "Wide pane in the centre. The first window lands there.",
    slots: [0.25, 0.5, 0.25]
  },
  {
    id: "even",
    name: "Even",
    detail: "Equal columns. A lone window fills the screen.",
    slots: [0.5, 0.5]
  },
  {
    id: "thirds",
    name: "Thirds",
    detail: "Three equal columns.",
    slots: [1 / 3, 1 / 3, 1 / 3]
  },
  {
    id: "halves",
    name: "Half",
    detail: "Plain 50 / 50.",
    slots: [0.5, 0.5]
  }
]

function presets() {
  return PRESETS
}

function presetById(id) {
  var key = String(id || "")
  for (var i = 0; i < PRESETS.length; i++) {
    if (PRESETS[i].id === key) return PRESETS[i]
  }
  return PRESETS[0]
}

function labelFor(id) {
  return presetById(id).name
}

function isOurs(layout) {
  return String(layout || "") === LAYOUT
}