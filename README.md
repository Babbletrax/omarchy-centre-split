# Centre Split

An Omarchy plugin that tiles a Hyprland workspace as **1/4 · 1/2 · 1/4**, with the half in the centre.

Omarchy’s default dwindle split for three windows is a half on the left and two quarters stacked on the right. This plugin registers a real Hyprland layout so the wide pane stays in the middle as windows open and close.

Also ships Even, Thirds, and Half (50/50). Extra windows stack in the centre column.

## Requirements

- Omarchy (Quattro plugin runtime)
- Hyprland 0.55 or newer (`hl.layout.register`)
- `hyprctl` and `jq` on `PATH`

No other runtime, package, background service, network access, or privileged command. The plugin talks only to Hyprland via `hyprctl`.

## Install

```sh
omarchy plugin add https://github.com/Babbletrax/omarchy-centre-split.git --enable
```

Then place the bar widget if it did not land on the left of the bar:

```sh
omarchy plugin enable io.github.babbletrax.centre-split --section left
```

Nothing is assigned to a workspace until you pick a split in the panel, so installing it does not change how your desktop tiles.

## Usage

Click the bar label (it reads `1/4 · 1/2 · 1/4` once that layout is active). Choose a split to apply it to the **current workspace**.

- **1/4 · 1/2 · 1/4** — first window takes the centre half; the second takes the left quarter; the third takes the right. Further windows stack in the centre.
- **Even** / **Thirds** / **Half** — equal columns. A single window fills the screen.
- **This workspace → dwindle** — hand the workspace back to Omarchy’s default tiling.
- **All workspaces → 1/4 · 1/2 · 1/4** — sets Hyprland’s default layout. Confirm you want that before clicking; it is the only action that changes the compositor default.

Bind the panel in `~/.config/hypr/bindings.lua` if you want a key:

```lua
o.bind("SUPER + ALT + C", "Centre split", "omarchy-shell shell summon io.github.babbletrax.centre-split '{}'")
```

## Files the plugin writes

| Path | What |
|------|------|
| `~/.config/omarchy/centre-split.json` | Saved default and per-workspace choices |
| `~/.local/state/omarchy/workspace-layouts/<id>.lua` | Same restore files Omarchy already uses for Super+L |

It does **not** edit `~/.config/hypr/hyprland.lua`. The background service re-registers the layouts when the shell starts.

To load the layouts at Hyprland start (before the shell), add this guarded block yourself at the end of `~/.config/hypr/hyprland.lua`:

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

Then, if you applied a split, hand workspaces back to dwindle (Super+L, or `hyprctl keyword general:layout dwindle`) and delete `~/.config/omarchy/centre-split.json` if you no longer want the saved choices. Leave or delete the optional `dofile` block in `hyprland.lua` — it checks the file exists first.

## License

MIT. See [LICENSE](LICENSE).
