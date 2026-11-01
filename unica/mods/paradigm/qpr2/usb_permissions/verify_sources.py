#!/usr/bin/env python3
# Copyright (c) 2026 ditternation
# SPDX-License-Identifier: GPL-3.0-or-later
"""Validate reviewed USB permission inputs before any ordinary patch or status."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

# git apply silently filters paths when invoked from a repository subdirectory.
# Run the absolute-path preflight outside the checkout so every hunk is checked.


REQUIRED_INPUTS = {
    *(f"smali/com/android/settings/connecteddevice/usb/{name}.smali" for name in (
        "UsbDetailsConnectedDevicesController", "UsbDetailsFragment", "UsbDetailsController", "UsbBackend")),
    "res/xml/sec_connections_settings.xml",
}
PATCH_NAMES = (
    "0001-Port-QPR2-USB-app-permission-management.patch",
    "0002-Expose-USB-app-access-on-Samsung-Connections-page.patch",
    "0099-Identify-reviewed-QPR2-backport.patch",
)


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"Duplicate USB permission contract path: {key}")
        result[key] = value
    return result


def read_contract(path):
    data = json.loads(path.read_text(), object_pairs_hook=unique_object)
    if not isinstance(data, dict) or set(data) != REQUIRED_INPUTS:
        raise ValueError("Incomplete/unexpected USB permission source contract paths")
    for relative, digests in data.items():
        if (not isinstance(digests, list) or not digests
                or any(not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest)
                       for digest in digests) or len(digests) != len(set(digests))):
            raise ValueError(f"Malformed USB permission source digests: {relative}")
    return data


def verify_sources(module_dir, decoded_dir):
    module_dir, decoded_dir = Path(module_dir).resolve(), Path(decoded_dir).resolve()
    contract = read_contract(module_dir / "sources.json")
    for relative, digests in contract.items():
        path = decoded_dir / relative
        if not path.is_file():
            raise ValueError(f"Missing USB permission input: {relative}")
        actual = hashlib.sha256(path.read_bytes()).hexdigest()
        if actual not in digests:
            raise ValueError(f"Unreviewed USB permission source: {relative} (SHA-256: {actual})")
        if relative.startswith("smali/") and list(decoded_dir.glob(f"smali*/{relative[6:]}")) != [path]:
            raise ValueError(f"Duplicate/moved USB permission class: {relative}")
    if list(decoded_dir.glob("smali*/io/mesalabs/unica/usb/Qpr2UsbPermissions*.smali")):
        raise ValueError("USB permission helper already present")
    patch_root = module_dir / "patches"
    expected = {f"SecSettings.apk/{name}" for name in PATCH_NAMES}
    actual = {str(path.relative_to(patch_root)) for path in patch_root.rglob("*.patch") if path.is_file()}
    if actual != expected or any(not (patch_root / name).stat().st_size for name in expected):
        raise ValueError("Incomplete/unexpected USB permission patch set")
    for name in PATCH_NAMES:
        patch = patch_root / "SecSettings.apk" / name
        result = subprocess.run(
            ["git", "apply", "--check", "--unsafe-paths", f"--directory={decoded_dir}", str(patch)],
            cwd="/", capture_output=True, text=True, check=False,
        )
        if result.returncode:
            raise ValueError(f"USB permission patch preflight failed: {name}\n{result.stderr}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("module_dir", type=Path)
    parser.add_argument("decoded_dir", type=Path)
    args = parser.parse_args()
    try:
        verify_sources(args.module_dir, args.decoded_dir)
    except (OSError, ValueError) as error:
        parser.exit(1, f"QPR2 USB permission source validation: {error}\n")


if __name__ == "__main__":
    main()
