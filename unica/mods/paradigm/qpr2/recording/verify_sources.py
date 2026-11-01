#!/usr/bin/env python3
# Copyright (c) 2026 ditternation
# SPDX-License-Identifier: GPL-3.0-or-later
"""Check the complete recording group before applying any ordinary APK patch."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

# git apply silently filters paths when invoked from a repository subdirectory.
# Run the absolute-path preflight outside the checkout so every hunk is checked.


SETTINGS = "system/priv-app/SecSettings/SecSettings.apk"
SYSTEMUI = "system_ext/priv-app/SystemUI/SystemUI.apk"
CAPTURE = "system/app/SmartCapture/SmartCapture.apk"
REQUIRED_INPUTS = {
    f"{SETTINGS}/res/xml/as_sound_vibration_settings_v2.xml",
    *(f"{SYSTEMUI}/smali_classes3/com/android/systemui/screenrecord/{name}.smali"
      for name in ("ScreenMediaRecorder", "ScreenInternalAudioRecorder", "ScreenRecordingAudioSource")),
    *(f"{CAPTURE}/smali_classes3/com/samsung/android/app/smartcapture/screenrecorder/recorder/core/{name}.smali"
      for name in ("BaseAudioRecorder", "MP4Recorder")),
}
MAIN_PATCHES = (
    (SETTINGS, "SecSettings.apk/0001-Expose-opt-in-QPR2-recording-microphone-routing.patch"),
    (SYSTEMUI, "SystemUI.apk/0001-Port-QPR2-recording-microphone-routing.patch"),
    (CAPTURE, "SmartCapture.apk/0001-Port-QPR2-recording-microphone-routing.patch"),
)
IDENTIFICATION_PATCHES = (
    "0099-Identify-reviewed-QPR2-backport.patch",
    "0099-Identify-reviewed-QPR2-backport-6.2.44.32.patch",
)


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"Duplicate recording contract path: {key}")
        result[key] = value
    return result


def read_contract(path):
    data = json.loads(path.read_text(), object_pairs_hook=unique_object)
    if not isinstance(data, dict) or set(data) != REQUIRED_INPUTS:
        raise ValueError("Incomplete/unexpected recording source contract paths")
    for relative, digests in data.items():
        if (not isinstance(digests, list) or not digests
                or any(not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest)
                       for digest in digests) or len(digests) != len(set(digests))):
            raise ValueError(f"Malformed recording source digests: {relative}")
    return data


def check_patch(folder, patch):
    return subprocess.run(
        ["git", "apply", "--check", "--unsafe-paths", f"--directory={folder}", str(patch)],
        cwd="/", capture_output=True, text=True, check=False,
    )


def verify_sources(module_dir, apktool_dir):
    module_dir, apktool_dir = Path(module_dir).resolve(), Path(apktool_dir).resolve()
    contract = read_contract(module_dir / "sources.json")
    for relative, digests in contract.items():
        path = apktool_dir / relative
        if not path.is_file():
            raise ValueError(f"Missing recording input: {relative}")
        actual = hashlib.sha256(path.read_bytes()).hexdigest()
        if actual not in digests:
            raise ValueError(f"Unreviewed recording source: {relative} (SHA-256: {actual})")
        if "/smali_classes3/" in relative:
            app, tail = relative.split("/smali_classes3/", 1)
            if list((apktool_dir / app).glob(f"smali*/{tail}")) != [path]:
                raise ValueError(f"Duplicate/moved recording class: {relative}")
    for app, name in ((SETTINGS, "Qpr2RecordingAudioPreferenceController"),
                      (SYSTEMUI, "Qpr2RecordingAudio"), (CAPTURE, "Qpr2RecordingAudio")):
        if list((apktool_dir / app).glob(f"smali*/io/mesalabs/unica/recording/{name}.smali")):
            raise ValueError(f"Recording helper already present: {app}/{name}")
    patch_dir = module_dir / "patches"
    expected = {name for _, name in MAIN_PATCHES}
    expected.update(f"SmartCapture.apk/{name}" for name in IDENTIFICATION_PATCHES)
    actual = {str(path.relative_to(patch_dir)) for path in patch_dir.rglob("*.patch") if path.is_file()}
    if actual != expected or any(not (patch_dir / name).stat().st_size for name in expected):
        raise ValueError("Incomplete/unexpected recording patch set")
    for name in sorted(expected):
        result = subprocess.run(["git", "apply", "--numstat", "--", str(patch_dir / name)],
                                cwd="/", capture_output=True, text=True, check=False)
        if result.returncode:
            raise ValueError(f"Malformed recording patch: {name}\n{result.stderr}")
    for app, name in MAIN_PATCHES:
        result = check_patch(apktool_dir / app, patch_dir / name)
        if result.returncode:
            raise ValueError(f"Recording patch preflight failed: {name}\n{result.stderr}")
    admitted = [name for name in IDENTIFICATION_PATCHES
                if not check_patch(apktool_dir / CAPTURE, patch_dir / "SmartCapture.apk" / name).returncode]
    if len(admitted) != 1:
        raise ValueError("Unreviewed/ambiguous SmartCapture version metadata; no recording patches applied")
    return admitted[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("module_dir", type=Path)
    parser.add_argument("apktool_dir", type=Path)
    args = parser.parse_args()
    try:
        selected = verify_sources(args.module_dir, args.apktool_dir)
    except (OSError, ValueError) as error:
        parser.exit(1, f"QPR2 recording source validation: {error}\n")
    print(selected)


if __name__ == "__main__":
    main()
