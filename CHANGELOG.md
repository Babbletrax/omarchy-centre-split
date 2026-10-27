# Changelog

All notable changes to this plugin are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed

- The shape now follows the number of windows on the workspace instead of a
  named preset. One window fills the screen; two windows rotate through even,
  1/3 + 2/3, 2/3 + 1/3 and a top/bottom half; three through even thirds and a
  2/3 pane with the others stacked; four or more through a 2x2 grid and a 2/3
  pane with the rest stacked. The variant for a window count advances each
  time the count changes, and the new `cyclevariant` layout message (Super +
  Shift + J, or the panel's shape button) advances it by hand.
- The named presets (1/4 · 1/2 · 1/4, Even, Thirds, Half), the panel's preset
  picker and the `apply preset` command were removed. `apply` now offers
  `register`, `apply`, `release`, `cyclevariant`, `default`, `restore`,
  `reclaim`, `status` and `doctor`.
- Super + J (`togglesplit`) re-applies the current shape instead of being
  silently rejected, and a rejected layout message now shows a desktop
  notification.

### Fixed

- A race where Omarchy's workspace-layout restore files were written while the
  workspace rule was still being flipped, which could leave a workspace
  showing the wrong layout. State is now written only after the re-tile is
  verified.
- `apply doctor` and `apply restore` referenced a module handle that
  `layouts.lua` never published.

### Added

- `homepage` in the manifest, this changelog, and CI for GitHub Actions and
  GitLab: manifest checks, `luac` and luacheck on `layouts.lua`, the layout
  geometry tests, qmllint, ShellCheck and shfmt on `apply` and the test
  scripts, gitleaks and a private-info scan.

## [1.1.0] - 2026-09-28

### Fixed

- A workspace could report dwindle while its windows still held the split's
  geometry, leaving a pane half-size or off-screen. Re-tiling now flips the
  rule through another layout with settle pauses and checks the windows
  moved, because re-setting a rule to its current value is a no-op.
- A shape click could split a workspace you had already left. The widget no
  longer caches the workspace id; `apply` and `release` accept `current`,
  resolved at the moment of the call.
- Borrowing the focused workspace to deliver a layout message now genuinely
  re-tiles it back instead of leaving a stale shape.
- A click that arrives while the helper is busy is queued instead of dropped.

### Added

- Geometry cases for re-splitting after release and for switching shape on a
  live workspace, and `tests/click_path.sh`, which drives the plugin over shell
  IPC and asserts the split lands on the focused workspace and no other.
- README sections on the re-tile rules, their symptoms and the IPC actions.

## [1.0.0] - 2026-09-28

### Added

- A Hyprland custom layout, `lua:centre-split`, that tiles a workspace as
  1/4 · 1/2 · 1/4 with the wide pane in the centre, plus Even, Thirds and
  Half (50/50) presets switched at runtime with a layout message. Only one
  layout is registered, because Hyprland resolves custom layout names by
  first-registered.
- Bar widget and panel to split the focused workspace, hand it back to
  dwindle, make the split the default layout, or re-apply saved choices after
  `hyprctl reload`; the same actions over shell IPC.
- `apply` helper that talks to Hyprland only through `hyprctl`, verifies each
  change by reading `tiledLayout` back, names a foreign Lua layout when one
  wins registration and clears it with `apply reclaim`, and never edits
  `hyprland.lua` or needs `sudo`.
- Native Omarchy notifications with a bounded lifetime (`CENTRE_SPLIT_NOTIFY=0`
  silences them).
- `tests/layout_test.lua` for the slot arithmetic without a compositor and
  `tests/visual_test.py`, which measures real window geometry on a scratch
  workspace.

[Unreleased]: https://github.com/Babbletrax/omarchy-centre-split/compare/577b85b...main
[1.1.0]: https://github.com/Babbletrax/omarchy-centre-split/compare/2983772...577b85b
[1.0.0]: https://github.com/Babbletrax/omarchy-centre-split/commit/c61aeb9
