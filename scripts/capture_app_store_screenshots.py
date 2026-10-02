#!/usr/bin/env python3
"""Capture real RoamStory screens using disposable iPhone and iPad simulators."""

from __future__ import annotations

import argparse
import os
import platform
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent
BUNDLE_ID = "com.infiz.roamstory"
CAPTURES = (
    ("01-trips", "trips"),
    ("02-organize", "organize"),
    ("03-write", "write"),
    ("04-photo", "photo"),
    ("05-gallery", "gallery"),
    ("06-map", "map"),
    ("07-export", "export"),
)


def run(*arguments: str, **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(arguments, check=True, text=True, **kwargs)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, help="Use an existing Debug simulator .app build")
    parser.add_argument("--device", choices=("iphone", "ipad"), default="iphone")
    parser.add_argument("--screen", action="append", choices=[screen for _, screen in CAPTURES],
                        help="Capture only this screen; may be repeated")
    args = parser.parse_args()
    family = "iPhone" if args.device == "iphone" else "iPad"
    device_type = (
        "com.apple.CoreSimulator.SimDeviceType.iPhone-13-Pro-Max"
        if args.device == "iphone"
        else "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M4-8GB"
    )
    output = ROOT / f"AppStoreScreenshots/{family}/Raw"
    output.mkdir(parents=True, exist_ok=True)
    device = run("xcrun", "simctl", "create", f"RoamStory App Store {family} Capture",
                 device_type,
                 capture_output=True).stdout.strip()
    try:
        with tempfile.TemporaryDirectory(prefix="roamstory-appstore-") as temporary:
            if args.app:
                app = args.app.resolve()
            else:
                derived = Path(temporary) / "build"
                log = ROOT / "AppStoreScreenshots/capture-build.log"
                with log.open("w") as handle:
                    run("xcodebuild", "-project", str(ROOT / "RoamStory.xcodeproj"),
                        "-scheme", "RoamStory", "-configuration", "Debug", "-destination",
                        f"platform=iOS Simulator,id={device}", "-derivedDataPath", str(derived),
                        "CODE_SIGNING_ALLOWED=NO", "ONLY_ACTIVE_ARCH=YES",
                        f"ARCHS={platform.machine()}", "build", stdout=handle, stderr=subprocess.STDOUT)
                app = derived / "Build/Products/Debug-iphonesimulator/RoamStory.app"
            # Bind the disposable simulator app to its bundle identifier.
            capture_app = Path(temporary) / "Capture/RoamStory.app"
            shutil.copytree(app, capture_app)
            run("codesign", "--force", "--sign", "-", "--identifier", BUNDLE_ID,
                str(capture_app))
            run("xcrun", "simctl", "boot", device)
            run("xcrun", "simctl", "bootstatus", device, "-b")
            run("xcrun", "simctl", "ui", device, "appearance", "light")
            run("xcrun", "simctl", "ui", device, "content_size", "small")
            run("xcrun", "simctl", "status_bar", device, "override", "--time", "9:41",
                "--dataNetwork", "wifi", "--wifiMode", "active", "--wifiBars", "3",
                "--batteryState", "charged", "--batteryLevel", "100")
            run("xcrun", "simctl", "install", device, str(capture_app))
            photos = sorted((ROOT / "AppStoreScreenshots/Assets/Brazil2026/Photos").glob("*.jpg"))
            if not photos:
                raise RuntimeError("Missing Brazil journey photos")
            container = Path(run("xcrun", "simctl", "get_app_container", device,
                                 BUNDLE_ID, "data", capture_output=True).stdout.strip())
            marker = container / "Documents/screenshot-ready.txt"
            marker.parent.mkdir(parents=True, exist_ok=True)
            photo_directory = marker.parent / "ScreenshotPhotos"
            shutil.copytree(photos[0].parent, photo_directory)
            shutil.copy2(photos[0].parent.parent / "journey.json", marker.parent / "journey.json")
            environment = dict(os.environ, SIMCTL_CHILD_ROAMSTORY_SCREENSHOT_READY_PATH=str(marker),
                               SIMCTL_CHILD_ROAMSTORY_SCREENSHOT_PHOTOS_PATH=str(photo_directory))
            captures = [(name, screen) for name, screen in CAPTURES
                        if not args.screen or screen in args.screen]
            for capture_index, (name, screen) in enumerate(captures):
                marker.unlink(missing_ok=True)
                run("xcrun", "simctl", "launch", "--terminate-running-process", device,
                    BUNDLE_ID, f"--app-store-screenshot={screen}", env=environment)
                deadline = time.monotonic() + 40
                while not marker.exists() and time.monotonic() < deadline:
                    time.sleep(0.25)
                if not marker.exists() or marker.read_text() != screen:
                    run("xcrun", "simctl", "io", device, "screenshot",
                        str(Path(tempfile.gettempdir()) / f"roamstory-capture-error-{family}.png"))
                    raise RuntimeError(f"Screenshot fixture did not load: {screen}")
                # Allow native navigation, thumbnails, and map tiles to settle.
                # A newly booted simulator can show an Apple Intelligence banner.
                time.sleep(20 if capture_index == 0 else (12 if screen == "map" else 4))
                run("xcrun", "simctl", "io", device, "screenshot", str(output / f"{name}.png"))
                print(f"Captured {name}", flush=True)
    finally:
        subprocess.run(["xcrun", "simctl", "shutdown", device], check=False)
        run("xcrun", "simctl", "delete", device)


if __name__ == "__main__":
    main()
