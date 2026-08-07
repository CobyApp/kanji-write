#!/usr/bin/env python3
"""App Store screenshot harness: devices, languages, capture, verification.

App Store Connect wants one set at iPhone 6.9" (1320×2868) and, for an app that
runs on iPad, one at iPad 13" (2064×2752). Every smaller size is derived by Apple
from those, so those two are all that has to be produced.

The app's language is its own setting rather than the device's, and it has to be
changed through the app's own Settings screen. Writing `appLanguage` straight into
the container's plist does not work: the file changes, but cfprefsd serves the app
from its own cache and the app keeps the old value — the first attempt here
produced a "Japanese" set whose explanations were all still Korean.

What this does NOT do is walk the app: simctl has no tap injection and there is no
idb here. Navigation and the language taps are done by whoever runs it; this
handles the parts that can be made deterministic, and refuses a screenshot that
comes out at the wrong size.

    app/Scripts/store_shots.py prepare                # create, boot, install, tidy
    app/Scripts/store_shots.py shot phone ko 01-home  # capture into <device>/<lang>/
    app/Scripts/store_shots.py verify                 # every file's real size
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from pathlib import Path

BUNDLE = "com.cobyapp.kanjiwrite"
OUT = Path(os.environ.get("SHOT_OUT", Path.home() / "Desktop/kanji-store-screenshots"))
RUNTIME = "com.apple.CoreSimulator.SimRuntime.iOS-26-5"

DEVICES = {
    "phone": ("Shot-iPhone-6.9", "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max",
              "iphone-6.9", (1320, 2868)),
    "pad": ("Shot-iPad-13", "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M4-8GB",
            "ipad-13", (2064, 2752)),
}
LANGS = ("ko", "ja", "zh", "en")


def sh(*args: str, check: bool = True) -> str:
    result = subprocess.run(args, capture_output=True, text=True)
    if check and result.returncode != 0:
        raise SystemExit(f"{' '.join(args)}\n{result.stderr.strip()}")
    return result.stdout.strip()


def udid(key: str) -> str:
    name, device_type, _, _ = DEVICES[key]
    listing = json.loads(sh("xcrun", "simctl", "list", "devices", "-j"))
    for devices in listing["devices"].values():
        for device in devices:
            if device["name"] == name:
                return device["udid"]
    # Reused rather than recreated per run: each boot costs the better part of a
    # minute and stale simulators pile up fast.
    return sh("xcrun", "simctl", "create", name, device_type, RUNTIME)


def app_path() -> str:
    derived = Path.home() / "Library/Developer/Xcode/DerivedData"
    found = list(derived.glob("KanjiWrite-*/Build/Products/Debug-iphonesimulator/KanjiApp.app"))
    if not found:
        raise SystemExit("no simulator build — build the KanjiWrite scheme first")
    return str(found[0])


def prepare() -> None:
    for key in DEVICES:
        device = udid(key)
        sh("xcrun", "simctl", "boot", device, check=False)
        sh("xcrun", "simctl", "bootstatus", device, "-b", check=False)
        sh("xcrun", "simctl", "install", device, app_path())
        # A still status bar: fixed clock, full battery, no carrier text.
        sh("xcrun", "simctl", "status_bar", device, "override",
           "--time", "9:41", "--batteryState", "charged", "--batteryLevel", "100",
           "--wifiBars", "3", check=False)
        print(f"{key}: ready ({device})")


def set_defaults(device: str, **values: str) -> None:
    """Only useful before the app's first launch — see the note at the top about
    cfprefsd ignoring container plist edits for a running app."""
    container = sh("xcrun", "simctl", "get_app_container", device, BUNDLE, "data")
    plist = Path(container) / "Library/Preferences" / f"{BUNDLE}.plist"
    for key, value in values.items():
        add = subprocess.run(
            ["/usr/libexec/PlistBuddy", "-c", f"Set :{key} {value}", str(plist)],
            capture_output=True)
        if add.returncode != 0:
            subprocess.run(
                ["/usr/libexec/PlistBuddy", "-c", f"Add :{key} string {value}", str(plist)],
                capture_output=True)


def shot(key: str, code: str, name: str) -> None:
    _, _, slug, expected = DEVICES[key]
    if code not in LANGS:
        raise SystemExit(f"language must be one of {LANGS}")
    target = OUT / slug / code
    target.mkdir(parents=True, exist_ok=True)
    path = target / f"{name}.png"
    sh("xcrun", "simctl", "io", udid(key), "screenshot", str(path))
    size = png_size(path)
    if size != expected:
        raise SystemExit(f"{path} is {size}, expected {expected}")
    print(f"{slug}/{code}/{name}.png  {size[0]}x{size[1]}")


def png_size(path: Path) -> tuple[int, int]:
    raw = path.read_bytes()
    return (int.from_bytes(raw[16:20], "big"), int.from_bytes(raw[20:24], "big"))


def verify() -> None:
    problems = 0
    by_set: dict[tuple[str, str], int] = {}
    for path in sorted(OUT.rglob("*.png")):
        slug, code = path.parent.parent.name, path.parent.name
        expected = next((d[3] for d in DEVICES.values() if d[2] == slug), None)
        size = png_size(path)
        ok = size == expected
        problems += 0 if ok else 1
        by_set[(slug, code)] = by_set.get((slug, code), 0) + 1
        print(f"{'ok ' if ok else 'BAD'} {size[0]}x{size[1]}  {path.relative_to(OUT)}")
    print()
    for (slug, code), count in sorted(by_set.items()):
        print(f"{slug}/{code}: {count} screenshots")
    if problems:
        raise SystemExit(f"{problems} file(s) at the wrong size")
    missing = [f"{d[2]}/{code}" for d in DEVICES.values() for code in LANGS
               if (d[2], code) not in by_set]
    if missing:
        print("\nnot captured yet: " + ", ".join(missing))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    command, *rest = sys.argv[1:]
    {"prepare": prepare, "shot": shot, "verify": verify}[command](*rest)
