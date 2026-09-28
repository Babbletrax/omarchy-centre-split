# Centre Split

An Omarchy plugin that tiles a Hyprland workspace as **1/4 · 1/2 · 1/4**, with the wide pane in the centre.

Omarchy's default dwindle split for three windows is a half on one side and two quarters stacked on the other. This plugin registers a real Hyprland layout instead, so the half stays in the middle as windows open and close. Also ships Even, Thirds, and a plain 50/50.

- [Requirements](#requirements)
- [Install](#install)
- [Usage](#usage)
- [How it works](#how-it-works)
- [Testing](#testing)
- [Troubleshooting](#troubleshooting)
- [Files it writes](#files-it-writes)
- [Remove](#remove)

## Requirements

- Omarchy (Quattro plugin runtime)
- Hyprland 0.55 or newer (`hl.layout.register`)
- `hyprctl` and `jq` on `PATH`

No other runtime, package, background service, network access, or privileged command. Everything goes through `hyprctl`.

## Install

```sh
omarchy plugin add https://github.com/Babbletrax/omarchy-centre-split.git --enable
```

Check it landed on the bar; if not:

```sh
omarchy plugin enable io.github.babbletrax.centre-split --section left
```

Installing changes nothing about how your desktop tiles. No workspace uses the layout until you switch a split on.

## Usage

Click the bar label (it reads the active shape, e.g. `1/4 · 1/2 · 1/4`).

| Action | What it does |
|--------|--------------|
| **1/4 · 1/2 · 1/4** | The headline split. The first window takes the centre half, the second the left quarter, the third the right. A fourth stacks under the centre half, and so on. A lone window keeps the centre half rather than filling the screen. |
| **Even** | Two equal columns; a lone window fills the screen. |
| **Thirds** | Three equal columns. |
| **Half** | Plain 50/50. |
| **Split this workspace** | Switches the split on for the focused workspace. |
| **Back to dwindle** | Hands the focused workspace back to Omarchy's default tiling. |
| **Every workspace** | Sets Hyprland's default layout to the split. This is the only action that changes the compositor default, and only when you click it. |
| **Reapply** | Re-registers the layout and re-applies your saved choices. Use after `hyprctl reload`, which wipes runtime-registered layouts. |

The shape is per compositor, not per workspace: Hyprland resolves custom layout names by first-registered in this build (see [Troubleshooting](#troubleshooting)), so the plugin registers exactly one layout and the shape is switched with a layout message. Which *workspaces* use the split is still per workspace.

Switching a preset reaches the layout through the focused workspace, so if the workspace you are on is not split, the plugin borrows it for a moment — sets the split, sends the message, hands it straight back — and says so in its log.

Panel keybinding, in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + C", "Centre split", "omarchy-shell shell summon io.github.babbletrax.centre-split '{}'")
```

The helper is usable on its own — handy in a terminal, a script, or a keybinding:

```sh
apply register            # load the layout, set the saved preset
apply apply 3             # split workspace 3 with the saved preset
apply apply 3 thirds      # ...or with a named one
apply preset even         # switch the shape everywhere the split is on
apply release 3           # workspace 3 back to dwindle
apply default qhq         # make the split Hyprland's default layout
apply status              # active workspace, layout, preset, saved state (JSON)
apply doctor              # health report
apply reclaim             # clear a foreign Lua layout, then restore
```

Run them from the plugin directory, or by full path. `CENTRE_SPLIT_NOTIFY=0` silences the native notifications.

## How it works

`layouts.lua` registers one Hyprland custom layout, `lua:centre-split`, built on `hl.layout.register`. The preset picks a slot table (fractions of the work area); windows fill the widest slot first, extra windows stack vertically, and `layout_msg` switches the preset at runtime.

`apply` is the only thing that talks to Hyprland: it loads `layouts.lua` into the compositor with `hyprctl eval`, sets workspace rules and the default layout through the Lua API, and writes the plugin's own state file. It never edits `hyprland.lua` and never needs `sudo`.

The bar widget owns the helper calls, the error surface, the log lines, and the shell IPC contract; the panel is presentation only. Errors are reported three ways: inline in the panel, as a native notification (`omarchy-notification-send`), and as a log line prefixed `omarchy centre-split` so it shows up alongside the first-party services.

Two behaviours of this Hyprland build shape the design, and both were confirmed live rather than assumed:

- `hyprctl keyword` is a **silent no-op** ("keyword can't work with non-legacy parsers") and still exits 0, so the plugin drives the default layout through `hl.config` and reads the result back.
- Custom layout names resolve **by first-registered**, not exactly. With two or more Lua layouts registered, every request returns the first one. Hence one registered layout, and a verification step that reads `tiledLayout` back and fails loudly when the name did not resolve. If another plugin (or an experiment) registered a Lua layout first, `apply reclaim` clears the registration and starts over.

Two more, found the hard way:

- `hyprctl eval` **cannot drive the loaded layout**: it returns no values and shares no state with it. The preset therefore moves through `hyprctl dispatch 'hl.dsp.layout("<preset>")'`, which re-tiles immediately and answers a bad name with a real error.
- Re-setting a workspace rule to the value it already has **does not re-tile**, so the helper flips the rule through `dwindle` and back to make a preset change visible at once.

## Testing

```sh
tests/run_all.sh            # manifest, shell syntax, geometry units, live geometry
tests/run_all.sh --units    # no windows opened
tests/run_all.sh --shots    # also save tests/screenshots/<case>.png
```

`tests/layout_test.lua` runs `layouts.lua` against a mock layout context: slot arithmetic per preset, one/two/three/four windows, stacking, and preset bookkeeping. No compositor needed, so it works over SSH.

`tests/visual_test.py` is the visual proof. It opens real windows on a scratch workspace (default 90), applies each preset through the plugin's own helper, screenshots the result with `grim` when asked, and measures where Hyprland actually put the windows against the fractions that preset promises — width, x, height and y, plus a crisp check that the widest window is the middle one and is centred on the screen. It saves and restores the focused workspace and your saved preset, releases the scratch workspace afterwards, and clears desktop toasts before each screenshot so the image shows the tiling and nothing else. Cases: `qhq-3`, `qhq-1`, `qhq-2`, `qhq-4`, `even-2`, `thirds-3`, `halves-2`.

Before the cases it runs a one-window preflight: if the layout name does not resolve — a foreign Lua layout won registration — it clears that with `apply reclaim` and retries once, rather than failing seven times over.

Options: `--case qhq-3` (repeatable), `--keep-open`, `--workspace N`, `--shots`, `--json`, `--no-reclaim`.

## Troubleshooting

**Windows tile normally but never in the new shape.** The layout did not resolve. The panel shows the Hyprland error; from a terminal:

```sh
apply doctor
apply reclaim
```

`reclaim` reloads the Hyprland config (which clears runtime-registered layouts), re-registers, and re-applies your saved choices. The usual cause is another Lua layout registered earlier in the same session — including a leftover from experimenting with `hl.layout.register` by hand.

**A preset does not seem to take effect.** The shape reaches the layout through the focused workspace. If nothing changed, check the helper's own output rather than the panel:

```sh
apply preset thirds
```

It reports the Hyprland error verbatim (exit 3), and its log lines say when it borrowed the focused workspace to deliver the message.

**Nothing you do through `hyprctl eval` changes the layout.** By design: on this build `eval` returns no values and cannot reach the registered layout. Use `hl.dsp.layout("<preset>")` — that is the channel the plugin's own switching uses.

**The split reverted after `hyprctl reload`.** Expected: a reload drops runtime registrations and the workspace rules that named them. Click **Reapply**, or run `apply restore`. To have the layout present from Hyprland's first frame, add the guarded `dofile` block from [Files it writes](#files-it-writes).

**`hyprctl getoption general:layout` looks odd.** That option reports the config string, which is not evidence the layout resolved. The plugin verifies against each workspace's `tiledLayout` instead.

**Nothing at all appears in the panel.** Check the shell log for `omarchy centre-split`:

```sh
journalctl --user -u omarchy-shell -n 200 --no-pager | grep 'centre-split'
```

## Files it writes

| Path | What |
|------|------|
| `~/.config/omarchy/centre-split.json` | Saved preset, default layout, and per-workspace choices |
| `~/.local/state/omarchy/workspace-layouts/<id>.lua` | The same restore files Omarchy already uses for its own workspace-layout toggle |

It does **not** edit `~/.config/hypr/hyprland.lua`. To load the layout before the shell starts, add this guarded block yourself at the end of that file:

```lua
do
  local p = os.getenv("HOME") .. "/.config/omarchy/plugins/io.github.babbletrax.centre-split/layouts.lua"
  local f = io.open(p, "r")
  if f then f:close(); dofile(p) end
end
```

## Remove

```sh
omarchy plugin remove io.github.babbletrax.centre-split
```

Then hand any split workspaces back to dwindle (Super+L, or the panel's **Back to dwindle** before removing), and delete `~/.config/omarchy/centre-split.json` if you no longer want the saved choices. The optional `dofile` block can stay — it checks the file exists first — or be deleted.

## License

MIT. See [LICENSE](LICENSE).