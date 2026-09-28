.pragma library

var PRESETS = [
  {
    id: "centre-split",
    name: "1/4 · 1/2 · 1/4",
    detail: "Wide pane in the centre. First window lands there.",
    hypr: "lua:centre-split",
    slots: [0.25, 0.5, 0.25],
    keepPlace: true,
    extra: 1
  },
  {
    id: "centre-split-even",
    name: "Even",
    detail: "Equal columns. A lone window fills the screen.",
    hypr: "lua:centre-split-even",
    slots: [0.5, 0.5],
    keepPlace: false,
    extra: 1
  },
  {
    id: "centre-split-thirds",
    name: "Thirds",
    detail: "Three equal columns.",
    hypr: "lua:centre-split-thirds",
    slots: [1 / 3, 1 / 3, 1 / 3],
    keepPlace: false,
    extra: 1
  },
  {
    id: "centre-split-half",
    name: "Half",
    detail: "Classic 50 / 50. Dwindle’s usual 3-window leftover lives here as two columns.",
    hypr: "lua:centre-split-half",
    slots: [0.5, 0.5],
    keepPlace: false,
    extra: 0
  }
]

var RELEASE = {
  id: "dwindle",
  name: "Dwindle",
  detail: "Hand the workspace back to Omarchy’s default tiling.",
  hypr: "dwindle",
  slots: [1],
  keepPlace: false,
  extra: 0
}

function presets() {
  return PRESETS
}

function presetById(id) {
  var key = String(id || "")
  for (var i = 0; i < PRESETS.length; i++) {
    if (PRESETS[i].id === key || PRESETS[i].hypr === key)
      return PRESETS[i]
  }
  if (key === "dwindle" || key === "scrolling" || key === "master")
    return RELEASE
  return PRESETS[0]
}

function isOurs(layout) {
  var name = String(layout || "")
  return name.indexOf("lua:centre-split") === 0 || name.indexOf("centre-split") === 0
}

function barLabel(layout) {
  var preset = presetById(layout)
  if (preset && preset.id !== "dwindle")
    return preset.name
  return "Split"
}
