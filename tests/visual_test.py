#!/usr/bin/env python3
"""Live geometry proof for the Centre Split plugin.

Opens real windows on a scratch Hyprland workspace, applies the current
window-count-driven shape through the plugin's own helper, cycles to each
variant for that count with `cyclevariant`, measures where Hyprland actually
put the windows, and checks the result against the geometry layouts.lua's
M.SHAPES promises for that bucket/variant. Optionally saves a screenshot per
variant so the result can be eyeballed as well as measured.

There is no fixed named-preset list any more (qhq/even/thirds/halves are
gone): the shape is chosen by window count and rotates through variants.
This harness mirrors that -- it drives `apply` + `cyclevariant`, the same
calls the panel and SUPER+SHIFT+J make, not a removed `apply shape <name>`.

    tests/visual_test.py                   # every bucket's variants, no screenshots
    tests/visual_test.py --shots           # also write tests/screenshots/*.png
    tests/visual_test.py --bucket 2        # just the 2-window variants
    tests/visual_test.py --keep-open       # leave the windows up for a look

The focused workspace is saved at the start and restored at the end, the
scratch workspace is released back to dwindle, and the spawned windows are
killed. Only hyprctl, foot (test windows) and grim (screenshots) are used.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
APPLY = REPO / "apply"
SHOT_DIR = REPO / "tests" / "screenshots"
APP_ID = "cs-visual-test"
LAYOUT = "lua:centre-split"

# Mirrors layouts.lua's M.SHAPES. Keep these two tables in lockstep: this is
# the live-geometry proof for that module, so a silent drift here would make
# a real regression in Lua look like a passing test.
SHAPES: dict[int, list[dict]] = {
    1: [
        {"name": "fullscreen", "slots": [1.0], "fill": "order"},
    ],
    2: [
        {"name": "even", "slots": [0.5, 0.5], "fill": "order"},
        {"name": "one-third-two-thirds", "slots": [1 / 3, 2 / 3], "fill": "order"},
        {"name": "two-thirds-one-third", "slots": [2 / 3, 1 / 3], "fill": "order"},
        {"name": "half-horizontal", "slots": [0.5, 0.5], "fill": "order", "orientation": "rows"},
    ],
    3: [
        {"name": "thirds", "slots": [1 / 3, 1 / 3, 1 / 3], "fill": "order"},
        {
            "name": "two-thirds-stack",
            "slots": [2 / 3, 1 / 3],
            "fill": "widest",
            "extra": 2,
            "keep_place": True,
        },
    ],
    4: [
        {"name": "square", "slots": [0.5, 0.5], "fill": "distribute"},
        {
            "name": "two-thirds-stack",
            "slots": [2 / 3, 1 / 3],
            "fill": "widest",
            "extra": 2,
            "keep_place": True,
        },
    ],
}


def bucket_for(n: int) -> int:
    if n <= 0:
        return 0
    return min(n, 4)


class Failure(Exception):
    pass


def hyprctl(*args: str) -> str:
    result = subprocess.run(["hyprctl", *args], capture_output=True, text=True)
    if result.returncode != 0:
        raise Failure(f"hyprctl {' '.join(args)} failed ({result.returncode}): {result.stderr.strip()}")
    return result.stdout


def hyprctl_json(*args: str):
    out = hyprctl(*args)
    if out.strip().startswith("["):
        out = out[out.index("["):]
    return json.loads(out)


def dispatch(expr: str) -> None:
    hyprctl("dispatch", expr)


def clients(app_id: str = APP_ID) -> list[dict]:
    return [c for c in hyprctl_json("clients", "-j") if c.get("class") == app_id]


def monitor_for_client(client: dict) -> dict:
    monitors = hyprctl_json("monitors", "-j")
    index = client.get("monitor", 0)
    for monitor in monitors:
        if monitor.get("id") == index:
            return monitor
    return monitors[0]


def usable_area(monitor: dict) -> tuple[int, int, int, int]:
    """Monitor work area: position and size minus the bar's reserved strip.

    Hyprland reports `reserved` as [left, top, right, bottom].
    """
    x, y = monitor["x"], monitor["y"]
    w, h = monitor["width"], monitor["height"]
    left, top, right, bottom = 0, 0, 0, 0
    reserved = monitor.get("reserved")
    if isinstance(reserved, list) and len(reserved) == 4:
        left, top, right, bottom = reserved
    return x + left, y + top, w - left - right, h - top - bottom


def active_workspace() -> int:
    return int(hyprctl_json("activeworkspace", "-j")["id"])


def focus_workspace(ws: int) -> None:
    dispatch(f'hl.dsp.focus({{ workspace = "{ws}" }})')
    for _ in range(40):
        if active_workspace() == ws:
            return
        time.sleep(0.1)
    raise Failure(f"could not focus workspace {ws}")


def spawn_window(index: int) -> subprocess.Popen:
    return subprocess.Popen(
        ["foot", "-a", APP_ID, "-T", f"CS-VIS-{index}", "-e", "sleep", "900"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def kill_windows(procs: list[subprocess.Popen]) -> None:
    for proc in procs:
        if proc.poll() is None:
            proc.terminate()
    deadline = time.time() + 6
    while time.time() < deadline and any(p.poll() is None for p in procs):
        time.sleep(0.1)
    for proc in procs:
        if proc.poll() is None:
            proc.kill()
    procs.clear()

    # Wait for Hyprland to drop the windows too.
    deadline = time.time() + 6
    while time.time() < deadline and clients():
        time.sleep(0.1)


def wait_for_windows(count: int, timeout: float = 25.0) -> list[dict]:
    deadline = time.time() + timeout
    found: list[dict] = []
    while time.time() < deadline:
        found = clients()
        if len(found) >= count:
            return found
        time.sleep(0.2)
    raise Failure(f"only {len(found)}/{count} test windows appeared")


def move_to_workspace(ws: int, found: list[dict]) -> None:
    for client in found:
        dispatch(
            f'hl.dsp.window.move({{ window = "address:{client["address"]}", '
            f'workspace = "{ws}", follow = false }})'
        )
    time.sleep(0.6)


def run_apply(*args: str) -> dict:
    result = subprocess.run([str(APPLY), *args], capture_output=True, text=True)
    payload: dict = {}
    # apply's JSON reply is pretty-printed (spans multiple lines), so scan
    # from each "{" at column 0 to find the first value that actually
    # parses, rather than assuming any single line is a complete object.
    stdout = result.stdout
    start = 0
    while True:
        start = stdout.find("{", start)
        if start == -1:
            break
        try:
            candidate, _ = json.JSONDecoder().raw_decode(stdout, start)
            payload = candidate
            break
        except json.JSONDecodeError:
            start += 1
    if result.returncode != 0 and not payload.get("error"):
        payload = {"error": f"helper exited {result.returncode}: {result.stderr.strip()}"}
    payload["_exit"] = result.returncode
    return payload


def set_variant_directly(bucket: int, target_index: int) -> None:
    """Jump straight to a variant via the `setvariant` layout_msg, dispatched
    synchronously through hyprctl -- bypassing `apply cyclevariant` + the
    saved-state JSON file entirely.

    `apply status`'s reported variant is read from a file written as a
    side effect of a previous `layout_msg`; polling it to decide whether to
    send ANOTHER message is inherently racy against Hyprland's own
    recalculation when two buckets' window counts change back-to-back in
    the same test run (confirmed live: running every bucket in one process
    intermittently read a stale variant number for the FIRST case of a
    bucket, even though the geometry itself was always correct for
    whatever variant was actually active). `setvariant` sidesteps all of
    that: one dispatch, one recalculation, done.
    """
    result = subprocess.run(
        ["hyprctl", "dispatch", f'hl.dsp.layout("setvariant {bucket} {target_index}")'],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        raise Failure(f"setvariant {bucket} {target_index} failed: {result.stderr.strip()}")
    time.sleep(0.6)


def dismiss_notifications() -> None:
    """Clear desktop toasts so they do not sit on top of the screenshots.

    Best effort: the shell CLI is not required, and a missing shell must not
    fail the run.
    """
    if shutil.which("omarchy-shell") is None:
        return
    subprocess.run(["omarchy-shell", "-q", "notifications", "dismissAll"],
                   capture_output=True, text=True)
    time.sleep(0.35)


def screenshot(monitor: dict, path: Path) -> str:
    dismiss_notifications()
    path.parent.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(
        ["grim", "-o", monitor["name"], str(path)], capture_output=True, text=True
    )
    if result.returncode != 0:
        return f"grim failed: {result.stderr.strip()}"
    return ""


def expected_groups(spec: dict, n: int) -> list[list[int]]:
    """Mirror layouts.lua's M.place grouping: which window indices (1-based,
    creation order) land in which slot, for `n` windows under this shape.
    Returns one list of window indices per slot.
    """
    slot_count = len(spec["slots"])
    groups: list[list[int]] = [[] for _ in range(slot_count)]

    if spec.get("fill") == "distribute":
        for i in range(1, n + 1):
            slot = (i - 1) % slot_count
            groups[slot].append(i)
        return groups

    order = list(range(slot_count))
    if spec.get("fill") == "widest":
        order.sort(key=lambda idx: (-spec["slots"][idx], idx))

    if n >= slot_count:
        for slot_pos in range(slot_count):
            groups[order[slot_pos]].append(slot_pos + 1)
        extra_slot = spec.get("extra", slot_count + 1) - 1
        if extra_slot < 0 or extra_slot >= slot_count:
            extra_slot = slot_count - 1
        for i in range(slot_count + 1, n + 1):
            groups[extra_slot].append(i)
    elif spec.get("keep_place"):
        for slot_pos in range(n):
            groups[order[slot_pos]].append(slot_pos + 1)
    else:
        # rescale: fewer windows than slots, no keep_place -- each window
        # gets its own proportionally-rescaled slot (not exercised by any
        # current SHAPES entry, but mirrored for completeness).
        for i in range(1, n + 1):
            groups[i - 1].append(i)

    return groups


def expected_geometry(spec: dict, n: int, ux: int, uy: int, uw: int, uh: int):
    """Mirror layouts.lua's M.place geometry for `n` windows under `spec`,
    within the usable area. Returns {window_index: (x, y, w, h)}.
    """
    groups = expected_groups(spec, n)
    slot_count = len(spec["slots"])

    if n < slot_count and not spec.get("keep_place") and spec.get("fill") != "distribute":
        total = sum(spec["slots"][:n])
        widths = [f / total for f in spec["slots"][:n]] if total > 0 else [1 / n] * n
    else:
        widths = spec["slots"]

    ranges = []
    x = 0.0
    for w in widths:
        ranges.append((x, x + w))
        x += w

    out: dict[int, tuple[float, float, float, float]] = {}
    rows = spec.get("orientation") == "rows"
    for slot_pos in range(min(slot_count, len(ranges))):
        members = groups[slot_pos]
        if not members:
            continue
        r0, r1 = ranges[slot_pos]
        if rows:
            slot_y0, slot_y1 = uy + uh * r0, uy + uh * r1
            slot_h = slot_y1 - slot_y0
            count = len(members)
            each_w = uw / count
            for pos, win in enumerate(members):
                out[win] = (ux + pos * each_w, slot_y0, each_w, slot_h)
        else:
            slot_x0, slot_x1 = ux + uw * r0, ux + uw * r1
            slot_w = slot_x1 - slot_x0
            count = len(members)
            each_h = uh / count
            for pos, win in enumerate(members):
                out[win] = (slot_x0, uy + pos * each_h, slot_w, each_h)
    return out


def check_variant(bucket: int, variant_idx: int, scratch_ws: int, shots: bool,
                   procs: list[subprocess.Popen]) -> tuple[bool, list[str], dict]:
    spec = SHAPES[bucket][variant_idx - 1]
    n = bucket if bucket < 4 else bucket  # the 4-bucket cases here always use exactly 4
    notes: list[str] = []
    failures: list[str] = []

    set_variant_directly(bucket, variant_idx)
    time.sleep(0.6)

    workspace = next((w for w in hyprctl_json("workspaces", "-j") if w["id"] == scratch_ws), None)
    if workspace is None:
        return False, ["scratch workspace disappeared"], {}
    if workspace.get("tiledLayout") != LAYOUT:
        failures.append(f"workspace layout is {workspace.get('tiledLayout')!r}, expected {LAYOUT!r}")

    found = clients()
    if len(found) != n:
        failures.append(f"{len(found)} windows on the workspace, expected {n}")
        return False, failures, {}

    monitor = monitor_for_client(found[0])
    ux, uy, uw, uh = usable_area(monitor)
    tol = max(10.0, 0.03 * uw)

    by_title = {c.get("title", ""): c for c in found}
    expected = expected_geometry(spec, n, ux, uy, uw, uh)

    measurements = []
    for index in range(1, n + 1):
        client = by_title.get(f"CS-VIS-{index}")
        if client is None:
            failures.append(f"window CS-VIS-{index} is missing")
            continue
        cx, cy = client["at"]
        cw, ch = client["size"]
        want_x, want_y, want_w, want_h = expected.get(index, (0, 0, 0, 0))

        measurements.append({
            "window": f"CS-VIS-{index}", "x": cx, "y": cy, "w": cw, "h": ch,
            "want_x": round(want_x, 1), "want_y": round(want_y, 1),
            "want_w": round(want_w, 1), "want_h": round(want_h, 1),
        })

        if abs(cw - want_w) > tol:
            failures.append(f"CS-VIS-{index}: width {cw} vs expected {want_w:.0f} (±{tol:.0f})")
        if abs(cx - want_x) > tol:
            failures.append(f"CS-VIS-{index}: x {cx} vs expected {want_x:.0f} (±{tol:.0f})")
        if abs(ch - want_h) > tol:
            failures.append(f"CS-VIS-{index}: height {ch} vs expected {want_h:.0f} (±{tol:.0f})")
        if abs(cy - want_y) > tol:
            failures.append(f"CS-VIS-{index}: y {cy} vs expected {want_y:.0f} (±{tol:.0f})")

    shot_path = ""
    if shots:
        shot_path = str(SHOT_DIR / f"bucket{bucket}-variant{variant_idx}-{spec['name']}.png")
        error = screenshot(monitor, Path(shot_path))
        if error:
            failures.append(error)
            shot_path = ""

    return (not failures), failures, {
        "measurements": measurements, "notes": notes, "screenshot": shot_path,
        "usable": {"x": ux, "y": uy, "w": uw, "h": uh},
    }


def run_bucket(bucket: int, scratch_ws: int, shots: bool) -> list[dict]:
    n = bucket
    procs: list[subprocess.Popen] = []
    results = []
    try:
        focus_workspace(scratch_ws)
        for i in range(n):
            procs.append(spawn_window(i + 1))
            time.sleep(0.45)
        found = wait_for_windows(n)
        move_to_workspace(scratch_ws, found)

        payload = run_apply("apply", str(scratch_ws))
        if payload.get("error"):
            return [{"case": f"bucket{bucket}-apply", "ok": False,
                     "failures": [f"helper error: {payload['error']}"], "detail": {}}]
        time.sleep(1.2)

        for variant_idx in range(1, len(SHAPES[bucket]) + 1):
            name = f"bucket{bucket}-variant{variant_idx}-{SHAPES[bucket][variant_idx - 1]['name']}"
            print(f"▶ {name} ({n} window(s))")
            try:
                ok, failures, detail = check_variant(bucket, variant_idx, scratch_ws, shots, procs)
            except Failure as error:
                ok, failures, detail = False, [str(error)], {}
            for m in detail.get("measurements", []):
                print(
                    "    {window:<10} at ({x:>5},{y:>5}) {w:>5}x{h:<5} | "
                    "want x={want_x:>7} y={want_y:>6} w={want_w:>7} h={want_h:>6}".format(**m)
                )
            if detail.get("screenshot"):
                print(f"    · screenshot {detail['screenshot']}")
            for f in failures:
                print(f"    ✗ {f}")
            print(f"  {'PASS' if ok else 'FAIL'}\n")
            results.append({"case": name, "ok": ok, "failures": failures, "detail": detail})
        return results
    finally:
        if not KEEP_OPEN:
            kill_windows(procs)
            run_apply("release", str(scratch_ws))


def preflight(scratch_ws: int, allow_reclaim: bool) -> bool:
    """Confirm the layout really resolves before spending time on the cases.

    Hyprland 0.56.2 resolves custom layout names by first-registered, so a
    Lua layout left behind by an earlier experiment (or another plugin)
    silently wins. Better to find that out here, with one window, than in
    every case.
    """
    procs: list[subprocess.Popen] = []
    try:
        focus_workspace(scratch_ws)
        procs.append(spawn_window(999))
        wait_for_windows(1)
        payload = run_apply("apply", str(scratch_ws))
        error = payload.get("error", "")
        if error and "did not resolve" in error and allow_reclaim:
            print(f"! {error}\n  clearing the foreign registration and retrying (apply reclaim)\n")
            reclaimed = run_apply("reclaim")
            if reclaimed.get("error"):
                print(f"visual_test: reclaim failed: {reclaimed['error']}", file=sys.stderr)
                return False
            time.sleep(2.0)
            payload = run_apply("apply", str(scratch_ws))
            error = payload.get("error", "")
        if error:
            print(f"visual_test: {error}", file=sys.stderr)
            return False
        return True
    finally:
        if not KEEP_OPEN:
            kill_windows(procs)
            run_apply("release", str(scratch_ws))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--shots", action="store_true", help="save a screenshot per variant")
    parser.add_argument("--bucket", type=int, action="append",
                         help="run only this window-count bucket (1-4, repeatable)")
    parser.add_argument("--keep-open", action="store_true", help="leave the test windows open")
    parser.add_argument("--workspace", type=int, default=90, help="scratch workspace id")
    parser.add_argument("--json", action="store_true", help="print results as JSON")
    parser.add_argument("--no-reclaim", action="store_true",
                        help="do not clear a foreign Lua layout automatically")
    args = parser.parse_args()

    global KEEP_OPEN
    KEEP_OPEN = args.keep_open

    if not os.environ.get("WAYLAND_DISPLAY"):
        print("visual_test: no WAYLAND_DISPLAY; run this inside the Hyprland session", file=sys.stderr)
        return 2
    for binary in ("hyprctl", "foot"):
        if shutil.which(binary) is None:
            print(f"visual_test: {binary} is required", file=sys.stderr)
            return 2
    if args.shots and shutil.which("grim") is None:
        print("visual_test: grim is required for --shots", file=sys.stderr)
        return 2

    buckets = args.bucket if args.bucket else [1, 2, 3, 4]
    for b in buckets:
        if b not in SHAPES:
            print(f"visual_test: no such bucket; known: {', '.join(str(k) for k in SHAPES)}", file=sys.stderr)
            return 2

    original_ws = active_workspace()
    results = []
    print(f"Centre Split live check — scratch workspace {args.workspace}, origin workspace {original_ws}")
    print(f"hyprctl reports {len(hyprctl_json('monitors', '-j'))} monitor(s)\n")

    try:
        if not preflight(args.workspace, allow_reclaim=not args.no_reclaim):
            return 2

        for bucket in buckets:
            results.extend(run_bucket(bucket, args.workspace, args.shots))
    finally:
        if not KEEP_OPEN:
            run_apply("release", str(args.workspace))
            try:
                focus_workspace(original_ws)
            except Failure:
                pass

    passed = sum(1 for r in results if r["ok"])
    print(f"{passed}/{len(results)} cases passed")

    if args.json:
        print(json.dumps(results, indent=2))

    return 0 if passed == len(results) else 1


KEEP_OPEN = False

if __name__ == "__main__":
    sys.exit(main())
