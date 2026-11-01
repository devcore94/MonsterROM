#!/usr/bin/env python3
# Copyright (c) 2026 ditternation
# SPDX-License-Identifier: GPL-3.0-or-later
"""Export the real S25+ One UI 9.0 resource APK; never relabel or re-sign it."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import stat
import subprocess
import tempfile
import xml.etree.ElementTree as ET
import zipfile


PROFILE = "pa2qxxx-sdk37"
PACKAGE = "com.samsung.android.wallpaper.res"
APK_PATH = Path("system/priv-app/wallpaper-res/wallpaper-res.apk")
CHUNK_BYTES = 50 * 1024 * 1024
IDENTITY_PROPERTIES = frozenset({
    "ro.product.system.model",
    "ro.build.version.sdk",
    "ro.build.version.oneui",
    "ro.build.version.incremental",
})


def need(condition, message):
    if not condition:
        raise ValueError(message)


def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def no_symlinks(path):
    need(".." not in path.parts, f"Parent traversal is not allowed: {path}")
    for entry in (path, *path.parents):
        need(not entry.is_symlink(), f"Refusing a symlinked path: {entry}")


def regular_file(path):
    no_symlinks(path)
    need(path.is_file(), f"Missing regular file: {path}")


def destination(output):
    need(output.name == PROFILE, "Refusing a non-One UI 9 destination")
    no_symlinks(output)
    if output.exists():
        need(output.is_dir(), "One UI 9 destination is not a directory")
        for entry in output.rglob("*"):
            need(not entry.is_symlink() and (entry.is_dir() or entry.is_file()),
                 f"Refusing a non-regular prebuilt destination: {entry}")


def firmware_version(build):
    need(isinstance(build, str) and re.fullmatch(
        r"S936B[A-Z0-9]{8}/S936B[A-Z0-9]{8}/S936B[A-Z0-9]{8}", build),
        "Missing or mismatched SM-S936B firmware receipt")
    pda = build.split("/")[0]
    # Samsung's rollback bit, then OS generation/year/month/incremental suffix.
    return pda[-5], pda[-4:]


def no_firmware_rollback(build, previous):
    bit, release = firmware_version(build)
    old_bit, old_release = firmware_version(previous)
    need(bit >= old_bit and release >= old_release, "Refusing a firmware downgrade")


def filesystem_metadata():
    entries = ["system", "system/priv-app", "system/priv-app/wallpaper-res"]
    return {
        "fs_config-system": "".join(f"{p} 0 0 755 capabilities=0x0\n" for p in entries)
        + f"{APK_PATH} 0 0 644 capabilities=0x0\n",
        "file_context-system": "".join(f"/{p} u:object_r:system_file:s0\n" for p in entries)
        + "/" + str(APK_PATH).replace(".", r"\.") + " u:object_r:system_file:s0\n",
    }


def read_profile(output):
    """Fail closed on partial/unreceipted output, including extra split parts."""
    destination(output)
    receipt = output / "SOURCES.json"
    if not receipt.exists():
        need(not any((output / p).exists() for p in (
            "system", ".current", *filesystem_metadata())), "Unreceipted One UI 9 payload")
        return None
    previous = json.loads(receipt.read_text())
    need(isinstance(previous, dict) and previous.get("schema") == 1
         and previous.get("model") == "SM-S936B" and previous.get("csc") == "EUX"
         and previous.get("sdk") == 37 and previous.get("oneui") == "90000"
         and previous.get("transformed") is False and previous.get("re_signed") is False,
         "Invalid One UI 9 provenance receipt")
    firmware_version(previous.get("firmware"))
    package = previous.get("package")
    need(isinstance(package, dict) and package.get("name") == PACKAGE
         and package.get("min_sdk") == 37 and package.get("target_sdk") == 37
         and type(package.get("version_code")) is int and package["version_code"] >= 0,
         "Invalid previous wallpaper package identity")
    size = previous.get("chunk_bytes")
    need(type(size) is int and 0 < size <= CHUNK_BYTES, "Invalid previous split size")
    parts = previous.get("parts")
    need(isinstance(parts, list) and 0 < len(parts) <= 100, "Invalid previous split inventory")
    joined = hashlib.sha256()
    expected = set()
    for number, part in enumerate(parts):
        path = Path(f"{APK_PATH}.{number:02}")
        need(isinstance(part, dict) and part.get("path") == str(path),
             "Non-contiguous or unsafe previous split inventory")
        regular_file(output / path)
        length = (output / path).stat().st_size
        need(type(part.get("bytes")) is int and length == part["bytes"]
             and 0 < length <= size and (number == len(parts) - 1 or length == size),
             "Previous split-part size mismatch")
        need(sha(output / path) == part.get("sha256"), "Previous split-part hash mismatch")
        with (output / path).open("rb") as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b""):
                joined.update(block)
        expected.add(output / path)
    need(set((output / APK_PATH.parent).glob("wallpaper-res.apk*")) == expected,
         "Unexpected or stale wallpaper split parts")
    need(joined.hexdigest() == previous.get("apk_sha256"), "Previous APK hash mismatch")
    need((output / ".current").read_text() == previous["firmware"] + "\n",
         "Previous firmware marker mismatch")
    for name, content in filesystem_metadata().items():
        need((output / name).read_text() == content, "Previous filesystem metadata mismatch")
    return previous


def check_update(feed, output):
    """Check Samsung metadata before the large download; no network access here."""
    xml = Path(feed).read_text()
    need("<!DOCTYPE" not in xml and "<!ENTITY" not in xml, "Unsupported firmware XML")
    root = ET.fromstring(xml)
    need([p.text for p in root.findall("./firmware/model")] == ["SM-S936B"]
         and [p.text for p in root.findall("./firmware/cc")] == ["EUX"],
         "Firmware feed model/region mismatch")
    latest = root.findall("./firmware/version/latest")
    need(len(latest) == 1 and latest[0].get("o") == "17", "Firmware feed must report Android 17")
    build = (latest[0].text or "").strip()
    firmware_version(build)
    previous = read_profile(Path(output))
    if previous:
        no_firmware_rollback(build, previous["firmware"])
    return {"firmware": build, "update": not previous or previous["firmware"] != build}


def properties(path):
    """Read donor identity fields, not unrelated repeated stock properties."""
    regular_file(path)
    result = {}
    for line in path.read_text().splitlines():
        if not line.strip() or line.lstrip().startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        if key not in IDENTITY_PROPERTIES:
            continue
        # Equal values are unambiguous; never choose first/last among conflicting
        # identity values. Stock files can repeat unrelated keys like qemu.
        need(key not in result or result[key] == value,
             f"Conflicting firmware identity property: {key}")
        result[key] = value
    return result


def package_info(aapt2, apk):
    result = subprocess.run([str(aapt2), "dump", "badging", str(apk)],
                            capture_output=True, text=True, check=True, timeout=60)
    packages = re.findall(r"^package: (.+)$", result.stdout, re.M)
    need(len(packages) == 1, "Expected one wallpaper package identity")
    pairs = re.findall(r"(\w+)='([^']*)'", packages[0])
    fields = dict(pairs)
    need(len(fields) == len(pairs), "Duplicate wallpaper package fields")
    # Newer aapt2 uses minSdkVersion; older releases spell it sdkVersion.
    sdk = re.findall(r"^(?:minSdkVersion|sdkVersion):'([^']+)'$", result.stdout, re.M)
    target = re.findall(r"^targetSdkVersion:'([^']+)'$", result.stdout, re.M)
    need(fields.get("name") == PACKAGE, "Not the Samsung wallpaper resource package")
    need(sdk == ["37"] and target == ["37"], "Wallpaper APK must itself target/min One UI 9")
    codes = [fields.get("versionCodeMajor", "0"), fields.get("versionCode", "")]
    need(all(re.fullmatch(r"[0-9]+", code) and int(code) <= 0xffffffff for code in codes),
         "Invalid wallpaper package version")
    version = (int(codes[0]) << 32) | int(codes[1])
    return {"name": PACKAGE, "version_code": version,
            "version_name": fields.get("versionName"), "min_sdk": 37, "target_sdk": 37}


def export_wallpaper(firmware, output, aapt2, chunk_bytes=CHUNK_BYTES, expected_firmware=None):
    firmware, output = Path(firmware), Path(output)
    previous = read_profile(output)
    need(firmware.name == "SM-S936B_EUX", "Expected the actual SM-S936B/EUX donor")
    build_prop = firmware / "system/system/build.prop"
    props = properties(build_prop)
    build_prop_sha = sha(build_prop)
    need(props.get("ro.product.system.model") == "SM-S936B", "Firmware model mismatch")
    need(props.get("ro.build.version.sdk") == "37", "Firmware must be One UI 9")
    need(props.get("ro.build.version.oneui") == "90000", "Firmware must be One UI 9.0 (90000)")
    regular_file(firmware / ".extracted")
    build = (firmware / ".extracted").read_text().strip()
    firmware_version(build)
    need(expected_firmware is None or build == expected_firmware,
         "Extracted firmware differs from the checked Samsung feed")
    need(props.get("ro.build.version.incremental") == build.split("/")[0],
         "Firmware properties do not match its extraction receipt")
    apk = firmware / "system" / APK_PATH
    regular_file(apk)
    source_sha = sha(apk)
    with zipfile.ZipFile(apk) as archive:
        names = archive.namelist()
        need(len(names) == len(set(names)), "Duplicate wallpaper ZIP members")
        need({"AndroidManifest.xml", "resources.arsc"}.issubset(names), "Incomplete resource APK")
        need(not any(n.endswith((".dex", ".so")) or n.startswith("lib/")
                     for n in names), "Unexpected executable code in wallpaper resource APK")
        need(not any(n.startswith("/") or "\\" in n or ".." in Path(n).parts for n in names),
             "Unsafe wallpaper ZIP paths")
        need(not any(stat.S_ISLNK(p.external_attr >> 16) for p in archive.infolist()),
             "Symlink in wallpaper ZIP")
        need(archive.testzip() is None, "Wallpaper ZIP CRC failure")
    identity = package_info(aapt2, apk)
    if previous:
        no_firmware_rollback(build, previous["firmware"])
        need(identity["version_code"] >= previous["package"]["version_code"],
             "Refusing a wallpaper package version downgrade")
    need(type(chunk_bytes) is int and 0 < chunk_bytes <= CHUNK_BYTES, "Invalid split size")
    output.parent.mkdir(parents=True, exist_ok=True)
    tmp = Path(tempfile.mkdtemp(prefix=".wallpaper-blobs-", dir=output.parent))
    backup = tmp / "previous"
    promoted = False
    try:
        staged = tmp / PROFILE
        if output.exists():
            shutil.copytree(output, staged)
        else:
            staged.mkdir()
        folder = staged / APK_PATH.parent
        folder.mkdir(parents=True, exist_ok=True)
        for old in folder.glob("wallpaper-res.apk.[0-9][0-9]"):
            old.unlink()
        parts = []
        with apk.open("rb") as source:
            for number in range(100):
                block = source.read(chunk_bytes)
                if not block:
                    break
                path = folder / f"wallpaper-res.apk.{number:02}"
                path.write_bytes(block)
                parts.append({"path": str(path.relative_to(staged)), "bytes": len(block),
                              "sha256": sha(path)})
            need(not source.read(1), "Wallpaper exceeds the supported two-digit split inventory")
        need(parts, "Empty wallpaper APK")
        joined = hashlib.sha256()
        for part in parts:
            with (staged / part["path"]).open("rb") as stream:
                for block in iter(lambda: stream.read(1024 * 1024), b""):
                    joined.update(block)
        need(joined.hexdigest() == source_sha and sha(apk) == source_sha,
             "Wallpaper input changed or split reassembly differs")
        need(properties(build_prop) == props and sha(build_prop) == build_prop_sha
             and (firmware / ".extracted").read_text().strip() == build,
             "Firmware properties or extraction receipt changed during export")
        receipt = {"schema": 1, "model": "SM-S936B", "csc": "EUX", "firmware": build,
                   "sdk": 37, "oneui": "90000", "package": identity,
                   "apk_sha256": source_sha, "chunk_bytes": chunk_bytes, "parts": parts,
                   "build_prop_sha256": build_prop_sha,
                   "transformed": False, "re_signed": False}
        for name, content in filesystem_metadata().items():
            (staged / name).write_text(content)
        (staged / "SOURCES.json").write_text(json.dumps(receipt, indent=2) + "\n")
        (staged / ".current").write_text(build + "\n")
        read_profile(staged)
        # Publish a complete tree, never overwrite individual old parts/links.
        # Keep the old directory until promotion succeeds; restore it on error.
        destination(output)
        if output.exists():
            output.rename(backup)
        try:
            staged.rename(output)
        except BaseException:
            if backup.exists():
                try:
                    backup.rename(output)
                except OSError as error:
                    raise OSError(f"Cannot restore previous profile; retained at {backup}") from error
            raise
        promoted = True
    finally:
        # If even rollback fails, retain the previous tree for recovery instead
        # of letting automatic temporary-directory cleanup erase the backup.
        if promoted or not backup.exists():
            shutil.rmtree(tmp)
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--firmware-dir", type=Path)
    mode.add_argument("--feed", type=Path)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--aapt2", type=Path)
    parser.add_argument("--expected-firmware")
    args = parser.parse_args()
    if args.firmware_dir and not args.aapt2:
        parser.error("--aapt2 is required with --firmware-dir")
    try:
        if args.feed:
            result = check_update(args.feed, args.output_dir)
            print(f"firmware={result['firmware']}\nupdate={str(result['update']).lower()}")
        else:
            result = export_wallpaper(args.firmware_dir, args.output_dir, args.aapt2,
                                      expected_firmware=args.expected_firmware)
            print(f"Validated One UI 9.0 S25+ wallpaper: {result['apk_sha256']}")
    except (OSError, ValueError, ET.ParseError, zipfile.BadZipFile, subprocess.SubprocessError) as error:
        parser.exit(1, f"One UI 9 wallpaper: {error}\n")


if __name__ == "__main__":
    main()
