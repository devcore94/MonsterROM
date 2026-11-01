#!/usr/bin/env python3
# Copyright (c) 2026 ditternation
# SPDX-License-Identifier: GPL-3.0-or-later
"""Check capture actions and select exactly one reviewed version-label patch."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

# git apply silently filters paths when invoked from a repository subdirectory.
# Run the absolute-path preflight outside the checkout so every hunk is checked.


REQUIRED_INPUTS = {
    "AndroidManifest.xml", "res/values/strings.xml",
    "smali_classes3/com/samsung/android/app/smartcapture/baseutil/notification/ScreenRecorderNotification.smali",
    "smali_classes3/com/samsung/android/app/smartcapture/screenrecorder/notification/NotificationActivity.smali",
}
MAIN_PATCHES = (
    "0001-Expose-QPR2-post-recording-edit-action.patch",
    "0002-Keep-recording-actions-without-preview-bitmap.patch",
)
IDENTIFICATION_PATCHES = ("0099-Identify-QPR2-r13.patch", "0099-Identify-QPR2-r13-6.2.44.32.patch")


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"Duplicate capture-actions contract path: {key}")
        result[key] = value
    return result


def check_patch(folder, patch):
    return subprocess.run(
        ["git", "apply", "--check", "--unsafe-paths", f"--directory={folder}", str(patch)],
        cwd="/", capture_output=True, text=True, check=False,
    )


def verify_sources(module_dir, decoded_dir):
    module_dir, decoded_dir = Path(module_dir).resolve(), Path(decoded_dir).resolve()
    contract = json.loads((module_dir / "sources.json").read_text(), object_pairs_hook=unique_object)
    if not isinstance(contract, dict) or set(contract) != REQUIRED_INPUTS:
        raise ValueError("Incomplete/unexpected capture-actions source contract")
    for relative, accepted in contract.items():
        if (not isinstance(accepted, list) or not accepted
                or any(not isinstance(value, str) or not re.fullmatch(r"[0-9a-f]{64}", value) for value in accepted)
                or len(set(accepted)) != len(accepted)):
            raise ValueError(f"Malformed capture-actions source identities: {relative}")
        path = decoded_dir / relative
        if not path.is_file() or path.is_symlink():
            raise ValueError(f"Missing/unsafe capture-actions input: {relative}")
        if hashlib.sha256(path.read_bytes()).hexdigest() not in accepted:
            raise ValueError(f"Unreviewed capture-actions input: {relative}")
        if relative.startswith("smali_classes3/") and list(decoded_dir.glob(f"smali*/{relative.split('/', 1)[1]}")) != [path]:
            raise ValueError(f"Duplicate/moved capture-actions class: {relative}")
    if list(decoded_dir.glob("smali*/io/mesalabs/unica/capture/Qpr2RecordingActions.smali")):
        raise ValueError("Capture-actions helper already present")
    patch_dir = module_dir / "patches/SmartCapture.apk"
    expected = {*MAIN_PATCHES, *IDENTIFICATION_PATCHES}
    actual = {str(path.relative_to(module_dir / "patches")) for path in (module_dir / "patches").rglob("*.patch")}
    if actual != {"SmartCapture.apk/" + name for name in expected}:
        raise ValueError("Incomplete/unexpected capture-actions patch set")
    for name in sorted(expected):
        path = patch_dir / name
        if path.is_symlink() or not path.is_file() or not path.stat().st_size:
            raise ValueError("Incomplete/unsafe capture-actions patch set")
        result = subprocess.run(["git", "apply", "--numstat", "--", str(path)], cwd="/", capture_output=True, text=True, check=False)
        if result.returncode:
            raise ValueError(f"Malformed capture-actions patch: {name}\n{result.stderr}")
    for name in MAIN_PATCHES:
        result = check_patch(decoded_dir, patch_dir / name)
        if result.returncode:
            raise ValueError(f"Capture-actions patch preflight failed: {name}\n{result.stderr}")
    admitted = [name for name in IDENTIFICATION_PATCHES if not check_patch(decoded_dir, patch_dir / name).returncode]
    if len(admitted) != 1:
        raise ValueError("Unreviewed/ambiguous SmartCapture capture-actions version metadata")
    return admitted[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("module_dir", type=Path)
    parser.add_argument("decoded_dir", type=Path)
    args = parser.parse_args()
    try:
        selected = verify_sources(args.module_dir, args.decoded_dir)
    except (OSError, ValueError) as error:
        parser.exit(1, f"QPR2 capture-actions validation: {error}\n")
    print(selected)


if __name__ == "__main__":
    main()
