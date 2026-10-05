#!/usr/bin/env python3
"""Import a folder's photos and videos into an iOS Simulator Photos library."""

import argparse
import errno
import json
from pathlib import Path
import shlex
import shutil
import subprocess
import sys


MEDIA_EXTENSIONS = {
    ".jpg", ".jpeg", ".jpe", ".jfif", ".heic", ".heif", ".png", ".gif",
    ".tif", ".tiff", ".bmp", ".jp2", ".j2k", ".webp", ".avif",
    ".dng", ".cr2", ".cr3", ".nef", ".arw", ".raf", ".orf", ".rw2",
    ".mov", ".mp4", ".m4v", ".avi", ".mpg", ".mpeg", ".3gp", ".3g2",
    ".mts", ".m2ts", ".webm", ".mkv", ".mxf",
}


def describe(device):
    return "{} — {} ({})".format(device["name"], device["udid"], device["runtime"])


def select_device(xcrun, requested):
    result = subprocess.run(
        [xcrun, "simctl", "list", "devices", "available", "--json"],
        check=True, capture_output=True, text=True,
    )
    devices = [
        dict(device, runtime=runtime)
        for runtime, entries in json.loads(result.stdout)["devices"].items()
        if ".iOS-" in runtime
        for device in entries
        if device.get("isAvailable", False)
    ]
    if requested:
        matches = [device for device in devices if requested.casefold() in (
            device["udid"].casefold(), device["name"].casefold()
        )]
    else:
        matches = [device for device in devices if device["state"] == "Booted"]
    if len(matches) == 1:
        return matches[0]
    choices = "\n".join("  " + describe(device) for device in (matches or devices))
    if len(matches) > 1:
        raise ValueError("Multiple simulators match. Select one with --device UUID:\n" + choices)
    if requested:
        raise ValueError("No available iOS simulator matches {!r}. Available devices:\n{}".format(requested, choices))
    raise ValueError("No iOS simulator is booted. Open Simulator, or select one with --device UUID:\n" + choices)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder", type=Path, help="Folder containing photos and videos")
    parser.add_argument("--device", help="Simulator UUID or exact name; otherwise use the only booted iOS simulator")
    parser.add_argument("--recursive", action="store_true", help="Include files in subfolders")
    parser.add_argument("--dry-run", action="store_true", help="List the import command without booting or modifying a simulator")
    args = parser.parse_args()

    folder = args.folder.expanduser().resolve(strict=True)
    if not folder.is_dir():
        raise ValueError("Not a folder: {}".format(folder))
    paths = folder.rglob("*") if args.recursive else folder.iterdir()
    files = sorted(
        (path for path in paths if path.is_file() and path.suffix.lower() in MEDIA_EXTENSIONS),
        key=lambda path: str(path).casefold(),
    )
    if not files:
        raise ValueError("No recognized photo or video files found in {}".format(folder))
    xcrun = shutil.which("xcrun")
    if not xcrun:
        raise ValueError("xcrun was not found. Install Xcode and select its developer directory.")
    device = select_device(xcrun, args.device)
    print("Simulator: {}".format(describe(device)), flush=True)
    print("Media files: {}".format(len(files)), flush=True)
    command = [xcrun, "simctl", "addmedia", device["udid"]] + [str(path) for path in files]
    if args.dry_run:
        if device["state"] != "Booted":
            print("Would boot the selected simulator and wait until it is ready.")
        print(" ".join(shlex.quote(argument) for argument in command))
        return 0
    if device["state"] != "Booted":
        subprocess.run([xcrun, "simctl", "boot", device["udid"]], check=True)
    subprocess.run([xcrun, "simctl", "bootstatus", device["udid"], "-b"], check=True)
    # Keep paired Live Photo image/video resources in the same addmedia call.
    result = subprocess.run(command)
    if result.returncode:
        print("Import failed. Some files may already have been added; review Photos before retrying.", file=sys.stderr)
        return 1
    print("Import complete. Open Photos in the simulator to view the media.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except subprocess.CalledProcessError as error:
        print("Simulator command failed: {}".format((error.stderr or str(error)).strip()), file=sys.stderr)
        sys.exit(1)
    except OSError as error:
        if error.errno == errno.E2BIG:
            print("Too many file paths for one import. Split the files into smaller folders, keeping Live Photo pairs together.", file=sys.stderr)
        else:
            print("Error: {}".format(error), file=sys.stderr)
        sys.exit(1)
    except (ValueError, KeyError) as error:
        print("Error: {}".format(error), file=sys.stderr)
        sys.exit(1)
