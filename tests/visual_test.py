#!/usr/bin/env python3
"""Live geometry proof for the Centre Split plugin.

Opens real windows on a scratch Hyprland workspace, applies a preset through the
plugin's own helper, measures where Hyprland actually put the windows, and checks
the result against the shape that preset promises. Optionally saves a screenshot
per case so the result can be eyeballed as well as measured.

    tests/visual_test.py                 # every case, no screenshots
    tests/visual_test.py --shots         # also write tests/screenshots/*.png
    tests/visual_test.py --case qhq-3    # just one case
    tests/visual_test.py --keep-open     # leave the windows up for a look

The focused workspace is saved at the start and restored at the end, the scratch
workspace is released back to dwindle, and the spawned windows are killed.
Only hyprctl, foot (test windows) and grim (screenshots) are used.
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

# Slot widths per preset, matching layouts.lua.
SLOTS = {
    "qhq": [0.25, 0.50, 0.25],
    "even": [0.50, 0.50],
    "thirds": [1 / 3, 1 / 3, 1 / 3],
    "halves": [0.50, 0.50],
}

# Each expectation is (slot index, row index, rows in that slot) in window
# creation order: the order the layout fills slots in.
CASES = [
    {
        "name": "qhq-3",
        "preset": "qhq",
        "windows": 3,
        "why": "the headline shape: first window takes the centre half",
        "expect": [(1, 0, 1), (0, 0, 1), (2, 0, 1)],
    },
    {
        "name": "qhq-1",
        "preset": "qhq",
        "windows": 1,
        "why": "a lone window keeps the centre half instead of filling the screen",
        "expect": [(1, 0, 1)],
    },
    {
        "name": "qhq-2",
        "preset": "qhq",
        "windows": 2,
        "why": "centre half first, then the left quarter",
        "expect": [(1, 0, 1), (0, 0, 1)],
    },
    {
        "name": "qhq-4",
        "preset": "qhq",
        "windows": 4,
        "why": "a fourth window stacks inside the centre half",
        "expect": [(1, 0, 2), (0, 0, 1), (2, 0, 1), (1, 1, 2)],
    },
    {
        "name": "even-2",
        "preset": "even",
        "windows": 2,
        "why": "two equal columns",
        "expect": [(0, 0, 1), (1, 0, 1)],
    },
    {
        "name": "thirds-3",
        "preset": "thirds",
        "windows": 3,
        "why": "three equal columns",
        "expect": [(0, 0, 1), (1, 0, 1), (2, 0, 1)],
    },
    {
        "name": "halves-2",
        "preset": "halves",
        "windows": 2,
        "why": "plain 50/50",
        "expect": [(0, 0, 1), (1, 0, 1)],
    },
    {
        "name": "resplit-after-release",
        "preset": "qhq",
        "windows": 4,
        "why": "splitting again a workspace that had the split, was handed back, and kept its windows",
        "pre": [["apply", "<ws>", "qhq"], ["release", "<ws>"]],
        "expect": [(1, 0, 2), (0, 0, 1), (2, 0, 1), (1, 1, 2)],
    },
    {
        "name": "switch-shape-live",
        "preset": "qhq",
        "expect_preset": "thirds",
        "windows": 3,
        "why": "switching the shape re-tiles every window already on a split workspace",
        "switch": [["preset", "thirds"]],
        "expect": [(0, 0, 1), (1, 0, 1), (2, 0, 1)],
    },
]


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
    payload = {}
    for line in result.stdout.splitlines():
        line = line.strip()
        if line.startswith("{"):
            try:
                payload = json.loads(line)
            except json.JSONDecodeError:
                pass
    if result.returncode != 0 and not payload.get("error"):
        payload = {"error": f"helper exited {result.returncode}: {result.stderr.strip()}"}
    payload["_exit"] = result.returncode
    return payload


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


def check_case(case: dict, scratch_ws: int, shots: bool) -> tuple[bool, list[str], dict]:
    notes: list[str] = []
    failures: list[str] = []
    procs: list[subprocess.Popen] = []

    try:
        focus_workspace(scratch_ws)
        for i in range(case["windows"]):
            procs.append(spawn_window(i + 1))
            time.sleep(0.45)

        found = wait_for_windows(case["windows"])
        move_to_workspace(scratch_ws, found)

        def step(args: list[str]) -> dict:
            return run_apply(*[str(scratch_ws) if a == "<ws>" else a for a in args])

        # Anything the case needs to happen to the workspace before the shape it
        # is checking: an earlier split, a release, and so on.
        for args in case.get("pre", []):
            payload = step(args)
            if payload.get("error"):
                failures.append(f"pre-step {' '.join(args)}: {payload['error']}")
            time.sleep(0.9)

        # Apply the preset through the plugin's own helper.
        payload = run_apply("apply", str(scratch_ws), case["preset"])
        if payload.get("error"):
            failures.append(f"helper error: {payload['error']}")
        time.sleep(1.2)

        # Switching the shape must move every window on the workspace, not just
        # the next one to open.
        if case.get("switch"):
            before = {c["title"]: (tuple(c["at"]), tuple(c["size"])) for c in clients()}
            for args in case["switch"]:
                payload = step(args)
                if payload.get("error"):
                    failures.append(f"switch-step {' '.join(args)}: {payload['error']}")
            time.sleep(1.5)
            after = {c["title"]: (tuple(c["at"]), tuple(c["size"])) for c in clients()}
            stale = [t for t in before if t in after and before[t] == after[t]]
            if stale:
                failures.append(
                    f"still at their pre-switch geometry after the shape changed: {', '.join(sorted(stale))}"
                )

        workspace = next(
            (w for w in hyprctl_json("workspaces", "-j") if w["id"] == scratch_ws), None
        )
        if workspace is None:
            failures.append("scratch workspace disappeared")
            return False, failures, {}
        if workspace.get("tiledLayout") != LAYOUT:
            failures.append(
                f"workspace layout is {workspace.get('tiledLayout')!r}, expected {LAYOUT!r}"
            )

        found = clients()
        if len(found) != case["windows"]:
            failures.append(f"{len(found)} windows on the workspace, expected {case['windows']}")
            return False, failures, {}

        monitor = monitor_for_client(found[0])
        ux, uy, uw, uh = usable_area(monitor)
        tol = max(10.0, 0.025 * uw)

        # Hyprland hands windows back without a creation marker, so pair them
        # with the expectation list by title (CS-VIS-<n>).
        by_title = {c.get("title", ""): c for c in found}
        expected_preset = case.get("expect_preset", case["preset"])
        slots = SLOTS[expected_preset]

        # Slot x-ranges and, inside a slot, the y-ranges of its stacked rows.
        slot_x = []
        x = ux
        for frac in slots:
            width = uw * frac
            slot_x.append((x, x + width))
            x += width

        rows_in_slot: dict[int, int] = {}
        for slot, _row, rows in case["expect"]:
            rows_in_slot[slot] = max(rows_in_slot.get(slot, 1), rows)

        measurements = []
        for index, (slot, row, rows) in enumerate(case["expect"], start=1):
            client = by_title.get(f"CS-VIS-{index}")
            if client is None:
                failures.append(f"window CS-VIS-{index} is missing")
                continue
            cx, cy = client["at"]
            cw, ch = client["size"]
            want_x0, want_x1 = slot_x[slot]
            want_w = want_x1 - want_x0
            want_y = uy + (uh * row / rows)
            want_h = uh / rows

            measurements.append(
                {
                    "window": f"CS-VIS-{index}",
                    "slot": slot,
                    "row": f"{row + 1}/{rows}",
                    "x": cx,
                    "y": cy,
                    "w": cw,
                    "h": ch,
                    "want_x": round(want_x0, 1),
                    "want_w": round(want_w, 1),
                    "want_y": round(want_y, 1),
                    "want_h": round(want_h, 1),
                }
            )

            if abs(cw - want_w) > tol:
                failures.append(
                    f"CS-VIS-{index}: width {cw} vs expected {want_w:.0f} (±{tol:.0f})"
                )
            if abs(cx - want_x0) > tol:
                failures.append(
                    f"CS-VIS-{index}: x {cx} vs expected {want_x0:.0f} (±{tol:.0f})"
                )
            if abs(ch - want_h) > tol:
                failures.append(
                    f"CS-VIS-{index}: height {ch} vs expected {want_h:.0f} (±{tol:.0f})"
                )
            if abs(cy - want_y) > tol:
                failures.append(f"CS-VIS-{index}: y {cy} vs expected {want_y:.0f} (±{tol:.0f})")

        # The crisp, human-meaningful check for the headline preset: the widest
        # window sits in the middle of the screen, between the two narrower ones.
        if expected_preset == "qhq" and case["windows"] >= 3:
            ordered = sorted(found, key=lambda c: c["at"][0])
            centre_window = ordered[1]
            widest = max(found, key=lambda c: c["size"][0])
            screen_centre = ux + uw / 2
            window_centre = centre_window["at"][0] + centre_window["size"][0] / 2
            if centre_window["title"] != widest["title"]:
                failures.append(
                    f"widest window is {widest['title']}, not the middle one {centre_window['title']}"
                )
            if abs(window_centre - screen_centre) > tol:
                failures.append(
                    f"middle window centre {window_centre:.0f} vs screen centre {screen_centre:.0f}"
                )
            notes.append(
                f"middle window {centre_window['title']} is widest "
                f"({centre_window['size'][0]}px) and centred "
                f"({abs(window_centre - screen_centre):.0f}px off)"
            )

        shot_path = ""
        if shots:
            shot_path = str(SHOT_DIR / f"{case['name']}.png")
            error = screenshot(monitor, Path(shot_path))
            if error:
                failures.append(error)
                shot_path = ""

        return (not failures), failures, {
            "measurements": measurements,
            "notes": notes,
            "screenshot": shot_path,
            "usable": {"x": ux, "y": uy, "w": uw, "h": uh},
        }
    finally:
        if not KEEP_OPEN:
            kill_windows(procs)
            run_apply("release", str(scratch_ws))


def preflight(scratch_ws: int, allow_reclaim: bool) -> bool:
    """Confirm the layout really resolves before spending time on the cases.

    Hyprland 0.56.2 resolves custom layout names by first-registered, so a Lua
    layout left behind by an earlier experiment (or another plugin) silently
    wins. Better to find that out here, with one window, than in every case.
    """
    procs: list[subprocess.Popen] = []
    try:
        focus_workspace(scratch_ws)
        procs.append(spawn_window(999))
        wait_for_windows(1)
        payload = run_apply("apply", str(scratch_ws), "qhq")
        error = payload.get("error", "")
        if error and "did not resolve" in error and allow_reclaim:
            print(f"! {error}\n  clearing the foreign registration and retrying (apply reclaim)\n")
            reclaimed = run_apply("reclaim")
            if reclaimed.get("error"):
                print(f"visual_test: reclaim failed: {reclaimed['error']}", file=sys.stderr)
                return False
            time.sleep(2.0)
            payload = run_apply("apply", str(scratch_ws), "qhq")
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
    parser.add_argument("--shots", action="store_true", help="save a screenshot per case")
    parser.add_argument("--case", action="append", help="run only this case (repeatable)")
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

    cases = CASES
    if args.case:
        wanted = set(args.case)
        cases = [c for c in CASES if c["name"] in wanted]
        if not cases:
            print(f"visual_test: no such case; known: {', '.join(c['name'] for c in CASES)}", file=sys.stderr)
            return 2

    original_ws = active_workspace()
    original_preset = run_apply("status").get("preset", "qhq")
    results = []
    print(f"Centre Split live check — scratch workspace {args.workspace}, origin workspace {original_ws}")
    print(f"hyprctl reports {len(hyprctl_json('monitors', '-j'))} monitor(s)\n")

    try:
        if not preflight(args.workspace, allow_reclaim=not args.no_reclaim):
            return 2

        for case in cases:
            print(f"▶ {case['name']}  ({case['preset']}, {case['windows']} window(s)) — {case['why']}")
            try:
                ok, failures, detail = check_case(case, args.workspace, args.shots)
            except Failure as error:
                ok, failures, detail = False, [str(error)], {}

            for measurement in detail.get("measurements", []):
                print(
                    "    {window:<10} slot {slot} row {row:<3} "
                    "at ({x:>5},{y:>5}) {w:>5}x{h:<5} | want x={want_x:>7} w={want_w:>7} "
                    "y={want_y:>6} h={want_h:>6}".format(**measurement)
                )
            for note in detail.get("notes", []):
                print(f"    ✓ {note}")
            if detail.get("screenshot"):
                print(f"    · screenshot {detail['screenshot']}")
            for failure in failures:
                print(f"    ✗ {failure}")
            print(f"  {'PASS' if ok else 'FAIL'}\n")
            results.append({"case": case["name"], "ok": ok, "failures": failures, "detail": detail})
    finally:
        if not KEEP_OPEN:
            run_apply("release", str(args.workspace))
            try:
                focus_workspace(original_ws)
            except Failure:
                pass
            if original_preset:
                run_apply("preset", original_preset)

    passed = sum(1 for r in results if r["ok"])
    print(f"{passed}/{len(results)} cases passed")

    if args.json:
        print(json.dumps(results, indent=2))

    return 0 if passed == len(results) else 1


KEEP_OPEN = False

if __name__ == "__main__":
    sys.exit(main())