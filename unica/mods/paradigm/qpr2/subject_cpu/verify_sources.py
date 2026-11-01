#!/usr/bin/env python3
# Copyright (c) 2026 ditternation
# SPDX-License-Identifier: GPL-3.0-or-later
"""Check the complete subject-preview inputs before copying or patching."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

# git apply silently filters paths when invoked from a repository subdirectory.
# Run the absolute-path preflight outside the checkout so every hunk is checked.


PAYLOADS = {
    "files/arm64-v8a/libunica_subject_cpu.so": "lib/arm64-v8a/libunica_subject_cpu.so",
    "files/arm64-v8a/libtensorflowlite_c.2.16.1.camera.samsung.so":
        "lib/arm64-v8a/libtensorflowlite_c.2.16.1.camera.samsung.so",
    "files/assets/unica/subject-humanseg.tflite": "assets/unica/subject-humanseg.tflite",
}
PATCH = "patches/CameraExtensionsProxy.apk/0001-Add-real-humanseg-CPU-preview-without-advertising-a-live-extension.patch"


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"Duplicate subject-preview contract key: {key}")
        result[key] = value
    return result


def safe_path(path):
    if any(parent.is_symlink() for parent in (path, *path.parents)):
        raise ValueError(f"Unsafe subject-preview path: {path}")
    if any(parent.exists() and not parent.is_dir() for parent in path.parents):
        raise ValueError(f"Unsafe subject-preview parent: {path}")


def digest(path):
    safe_path(path)
    if not path.is_file():
        raise ValueError(f"Missing subject-preview input: {path}")
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify_sources(module_dir, apk, decoded_dir, check_patch=False):
    module_dir, apk, decoded_dir = Path(module_dir).absolute(), Path(apk).absolute(), Path(decoded_dir).absolute()
    safe_path(module_dir / "apks.json")
    safe_path(module_dir / "payload.sha256")
    contract = json.loads((module_dir / "apks.json").read_text(), object_pairs_hook=unique_object)
    if not isinstance(contract, dict) or set(contract) != {"CameraExtensionsProxy.apk"} or apk.name != "CameraExtensionsProxy.apk":
        raise ValueError("Incomplete/unexpected subject-preview APK contract")
    accepted = contract["CameraExtensionsProxy.apk"]
    if (not isinstance(accepted, list) or not accepted
            or any(not isinstance(value, str) or not re.fullmatch(r"[0-9a-f]{64}", value) for value in accepted)
            or len(set(accepted)) != len(accepted)):
        raise ValueError("Malformed subject-preview APK identities")
    if digest(apk) not in accepted:
        raise ValueError("Unreviewed CameraExtensionsProxy baseline")
    payloads = {}
    for number, line in enumerate((module_dir / "payload.sha256").read_text().splitlines(), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        parts = line.split()
        if len(parts) != 2 or not re.fullmatch(r"[0-9a-f]{64}", parts[0]):
            raise ValueError(f"Malformed subject-preview payload contract: line {number}")
        value, name = parts
        if name not in PAYLOADS or name in payloads:
            raise ValueError(f"Unexpected/duplicate subject-preview payload path: {name}")
        payloads[name] = value
    if set(payloads) != PAYLOADS.keys():
        raise ValueError("Incomplete subject-preview payload contract")
    nodes = list((module_dir / "files").rglob("*"))
    if any(path.is_symlink() for path in nodes):
        raise ValueError("Unsafe subject-preview payload inventory")
    actual = {str(path.relative_to(module_dir)) for path in nodes if not path.is_dir()}
    if actual != PAYLOADS.keys():
        raise ValueError("Incomplete/unexpected subject-preview payload inventory")
    safe_path(decoded_dir)
    if decoded_dir.exists() and not decoded_dir.is_dir():
        raise ValueError("Unsafe subject-preview decoded destination")
    for name, value in payloads.items():
        if digest(module_dir / name) != value:
            raise ValueError(f"Unreviewed subject-preview payload: {name}")
        destination = decoded_dir / PAYLOADS[name]
        safe_path(destination)
        if destination.exists():
            raise ValueError(f"Refusing existing subject-preview asset: {PAYLOADS[name]}")
    patches = {str(path.relative_to(module_dir)) for path in (module_dir / "patches").rglob("*.patch")}
    if patches != {PATCH} or not (module_dir / PATCH).is_file() or not (module_dir / PATCH).stat().st_size:
        raise ValueError("Incomplete/unexpected subject-preview patch set")
    safe_path(module_dir / PATCH)
    if check_patch:
        if not decoded_dir.is_dir():
            raise ValueError("Missing subject-preview decoded APK")
        result = subprocess.run(
            ["git", "apply", "--check", "--unsafe-paths", f"--directory={decoded_dir}", str(module_dir / PATCH)],
            cwd="/", capture_output=True, text=True, check=False,
        )
        if result.returncode:
            raise ValueError(f"Subject-preview patch preflight failed:\n{result.stderr}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("module_dir", type=Path)
    parser.add_argument("apk", type=Path)
    parser.add_argument("decoded_dir", type=Path)
    parser.add_argument("--check-patch", action="store_true")
    args = parser.parse_args()
    try:
        verify_sources(args.module_dir, args.apk, args.decoded_dir, args.check_patch)
    except (OSError, ValueError) as error:
        parser.exit(1, f"QPR2 subject-preview validation: {error}\n")


if __name__ == "__main__":
    main()
