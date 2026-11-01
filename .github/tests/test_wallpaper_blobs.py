# Copyright (c) 2026 ditternation
# SPDX-License-Identifier: GPL-3.0-or-later
"""Host-only checks with synthetic firmware/ZIPs; no real firmware or network."""
import hashlib
import importlib.util
import json
from pathlib import Path
import stat
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
import warnings
import zipfile


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / ".github/update_wallpaper_blobs.py"
SPEC = importlib.util.spec_from_file_location("wallpaper_blobs", SCRIPT)
BOT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BOT)
BUILD = "S936BXXSDDZJ1/S936BOXMDDZJ1/S936BXXSDDZJ1"
OLDER = "S936BXXUCDZIF/S936BOXMCDZIF/S936BXXUCDZIF"
NEWER = "S936BXXSDDZJ2/S936BOXMDDZJ2/S936BXXSDDZJ2"


def badging(version=37, minimum="37", target="37", sdk_label="minSdkVersion"):
    return (f"package: name='{BOT.PACKAGE}' versionCode='{version}' versionName='17'\n"
            f"{sdk_label}:'{minimum}'\ntargetSdkVersion:'{target}'\n")


def snapshot(path):
    if path.is_symlink():
        return {".": ("link", str(path.readlink()))}
    if not path.exists():
        return None
    return {str(p.relative_to(path)): ("link", str(p.readlink())) if p.is_symlink()
            else ("dir",) if p.is_dir() else ("file", p.read_bytes())
            for p in path.rglob("*")}


class WallpaperBlobsTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="wallpaper-blobs-test-")
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        self.firmware = self.root / "firmware donors/SM-S936B_EUX"
        self.output = self.root / "prebuilts/pa2qxxx-sdk37"
        self.apk = self.firmware / "system" / BOT.APK_PATH
        self.apk.parent.mkdir(parents=True)
        self.props = self.firmware / "system/system/build.prop"
        self.write_firmware()
        self.write_apk()

    def write_firmware(self, build=BUILD, **overrides):
        props = {"ro.product.system.model": "SM-S936B", "ro.build.version.sdk": "37",
                 "ro.build.version.oneui": "90000", "ro.build.version.incremental": build.split("/")[0]}
        props.update(overrides)
        self.props.write_text("".join(f"{k}={v}\n" for k, v in props.items()))
        (self.firmware / ".extracted").write_text(build)

    def write_apk(self, size=1600, extra=(), omit=()):
        entries = [("AndroidManifest.xml", b"synthetic manifest"),
                   ("resources.arsc", b"synthetic resource table"),
                   ("res/raw/resources_info.json", b"{}"),
                   ("assets/video_001.mp4", b"\r\n\0\xff" * (size // 4))]
        with warnings.catch_warnings(), zipfile.ZipFile(self.apk, "w") as archive:
            warnings.simplefilter("ignore", UserWarning)
            for name, data in [*entries, *extra]:
                if name not in omit:
                    info = name if isinstance(name, zipfile.ZipInfo) else zipfile.ZipInfo(name)
                    archive.writestr(info, data)

    def export(self, text=None, **kwargs):
        result = subprocess.CompletedProcess([], 0, text if text is not None else badging(), "")
        with mock.patch.object(BOT.subprocess, "run", return_value=result) as process:
            receipt = BOT.export_wallpaper(self.firmware, self.output, "mock-aapt2",
                                           chunk_bytes=128, **kwargs)
        self.assertEqual(process.call_args.args[0], ["mock-aapt2", "dump", "badging", str(self.apk)])
        return receipt

    def reject(self, text=None, **kwargs):
        before = snapshot(self.output)
        with self.assertRaises((ValueError, OSError, zipfile.BadZipFile, subprocess.SubprocessError)):
            self.export(text=text, **kwargs)
        self.assertEqual(snapshot(self.output), before, "Rejected input changed the previous profile")
        self.assertEqual(list(self.output.parent.glob(".wallpaper-blobs-*")), [])

    def feed(self, model="SM-S936B", csc="EUX", android="17", build=BUILD, extra=""):
        path = self.root / "version.xml"
        path.write_text(f"<versioninfo><firmware><model>{model}</model><cc>{csc}</cc>"
                        f"<version><latest o='{android}'>{build}</latest>{extra}</version>"
                        "</firmware></versioninfo>")
        return path

    def test_exact_unmodified_reassembly_and_receipts(self):
        original = self.apk.read_bytes()
        receipt = self.export(expected_firmware=BUILD)
        parts = [(self.output / p["path"]).read_bytes() for p in receipt["parts"]]
        self.assertGreater(len(parts), 1)
        self.assertEqual(b"".join(parts), original)
        self.assertEqual(receipt["apk_sha256"], hashlib.sha256(original).hexdigest())
        self.assertEqual(receipt, BOT.read_profile(self.output))
        self.assertFalse(receipt["transformed"])
        self.assertFalse(receipt["re_signed"])
        self.assertEqual((self.output / ".current").read_text(), BUILD + "\n")
        self.assertFalse((self.output / BOT.APK_PATH).exists())
        self.assertEqual(self.apk.read_bytes(), original)
        self.assertEqual(BOT.CHUNK_BYTES, 50 * 1024 * 1024)

    def test_both_real_aapt2_minimum_sdk_spellings(self):
        for label in ("sdkVersion", "minSdkVersion"):
            with self.subTest(label=label):
                self.assertEqual(self.export(badging(sdk_label=label))["package"]["min_sdk"], 37)

    def test_default_split_crosses_real_50mib_boundary(self):
        with zipfile.ZipFile(self.apk, "a") as archive:
            with archive.open("assets/full-size.mp4", "w") as asset:
                block = b"\r\n\0\xff" * (1024 * 1024 // 4)
                for _ in range(50):
                    asset.write(block)
        with mock.patch.object(BOT.subprocess, "run", return_value=subprocess.CompletedProcess(
                [], 0, badging(), "")):
            receipt = BOT.export_wallpaper(self.firmware, self.output, "mock-aapt2")
        self.assertEqual(len(receipt["parts"]), 2)
        self.assertEqual(receipt["parts"][0]["bytes"], 50 * 1024 * 1024)
        self.assertEqual(sum(p["bytes"] for p in receipt["parts"]), self.apk.stat().st_size)
        self.assertEqual(BOT.read_profile(self.output)["apk_sha256"], BOT.sha(self.apk))

    def test_wrong_firmware_identity_rejects_before_mutation(self):
        self.export()
        for key, value in (("ro.product.system.model", "SM-S942B"),
                           ("ro.build.version.sdk", "36"), ("ro.build.version.sdk", "38"),
                           ("ro.build.version.oneui", "80500"), ("ro.build.version.oneui", "90500")):
            with self.subTest(property=key, value=value):
                self.write_firmware(**{key: value})
                self.reject()

    def test_conflicting_or_missing_firmware_properties_reject(self):
        self.props.write_text(self.props.read_text() + "ro.build.version.sdk=36\n")
        self.reject()
        self.write_firmware()
        self.props.write_text(self.props.read_text().replace("ro.build.version.oneui=90000\n", ""))
        self.reject()

    def test_stock_duplicate_non_identity_properties_are_ignored(self):
        expected = BOT.properties(self.props)
        for value in ("0", "1"):
            with self.subTest(repeated_qemu=value):
                self.write_firmware()
                self.props.write_text(self.props.read_text() +
                                      f"ro.kernel.qemu=0\nro.kernel.qemu={value}\n"
                                      "persist.example.flag=first\npersist.example.flag=second\n")
                receipt = self.export(expected_firmware=BUILD)
                self.assertEqual(BOT.properties(self.props), expected)
                self.assertEqual(receipt["build_prop_sha256"], BOT.sha(self.props))

    def test_identical_identity_duplicates_are_unambiguous(self):
        expected = BOT.properties(self.props)
        for key, value in expected.items():
            with self.subTest(property=key):
                self.write_firmware()
                self.props.write_text(self.props.read_text() + f"{key}={value}\n")
                self.assertEqual(self.export()["firmware"], BUILD)
                self.assertEqual(BOT.properties(self.props), expected)

    def test_conflicting_identity_values_reject_in_both_orders(self):
        expected = BOT.properties(self.props)
        invalid = {"ro.product.system.model": "SM-S942B", "ro.build.version.sdk": "36",
                   "ro.build.version.oneui": "80500", "ro.build.version.incremental": OLDER.split("/")[0]}
        self.assertEqual(set(expected), set(invalid))
        self.export()
        for key, bad in invalid.items():
            for first, last in ((expected[key], bad), (bad, expected[key])):
                with self.subTest(property=key, first=first, last=last):
                    self.write_firmware(**{key: first})
                    self.props.write_text(self.props.read_text() + f"{key}={last}\n")
                    self.reject()

    def test_unrelated_property_change_during_export_is_detected(self):
        self.props.write_text(self.props.read_text() + "ro.kernel.qemu=0\nro.kernel.qemu=0\n")
        self.export()
        original = BOT.package_info

        def changed_property(aapt2, apk):
            identity = original(aapt2, apk)
            self.props.write_text(self.props.read_text().replace("ro.kernel.qemu=0", "ro.kernel.qemu=1"))
            return identity

        with mock.patch.object(BOT, "package_info", side_effect=changed_property):
            self.reject()

    def test_missing_foreign_and_inconsistent_extraction_receipts(self):
        marker = self.firmware / ".extracted"
        marker.unlink()
        self.reject()
        for value in ("", "invented", BUILD.replace("S936B", "S942B"), OLDER):
            with self.subTest(receipt=value):
                marker.write_text(value)
                self.reject()

    def test_extracted_build_must_match_preflight(self):
        self.reject(expected_firmware=OLDER)

    def test_aapt2_failure_and_input_changes_preserve_profile(self):
        self.export()
        before = snapshot(self.output)
        with mock.patch.object(BOT.subprocess, "run", side_effect=subprocess.CalledProcessError(1, "aapt2")):
            with self.assertRaises(subprocess.CalledProcessError):
                BOT.export_wallpaper(self.firmware, self.output, "mock-aapt2")
        self.assertEqual(snapshot(self.output), before)
        original = BOT.package_info

        def changed_input(aapt2, apk):
            identity = original(aapt2, apk)
            self.apk.write_bytes(self.apk.read_bytes() + b"changed during export")
            return identity

        with mock.patch.object(BOT, "package_info", side_effect=changed_input):
            self.reject()
        self.write_apk()

        def changed_properties(aapt2, apk):
            identity = original(aapt2, apk)
            self.write_firmware(OLDER)
            return identity

        with mock.patch.object(BOT, "package_info", side_effect=changed_properties):
            self.reject()

    def test_wrong_donor_directory_and_legacy_destination_reject(self):
        old_output = self.root / "prebuilts/pa2qxxx"
        old_output.mkdir(parents=True)
        (old_output / ".current").write_text("preserve SDK36")
        before = snapshot(old_output)
        with self.assertRaises(ValueError):
            BOT.export_wallpaper(self.firmware, old_output, "unused")
        self.assertEqual(snapshot(old_output), before)
        with self.assertRaises(ValueError):
            BOT.export_wallpaper(self.firmware.parent / "SM-S942B_INS", self.output, "unused")

    def test_bad_apk_identity_sdk_and_versions_reject(self):
        self.export()
        variants = [badging(minimum="36"), badging(target="36"), badging(minimum="38"),
                    badging(target="38"), badging().replace(BOT.PACKAGE, "another.package"),
                    badging(version="-1"), badging(version="bad"), badging(version=2**32),
                    badging().replace(" versionCode='37'", ""),
                    badging() + "sdkVersion:'37'\n", badging() + badging(),
                    badging().replace(" versionName", " versionCode='37' versionName")]
        for text in variants:
            with self.subTest(badging=text):
                self.reject(text)

    def test_long_version_code_is_not_truncated(self):
        text = badging().replace(" versionName=", " versionCodeMajor='1' versionName=")
        receipt = self.export(text)
        self.assertEqual(receipt["package"]["version_code"], (1 << 32) + 37)
        self.reject(badging(version=38))

    def test_code_and_unsafe_zip_members_reject(self):
        self.export()
        for name in ("classes.dex", "classes2.dex", "assets/hidden.dex", "lib/arm64-v8a/x.so",
                     "assets/native.so", "../outside", "/absolute", "res\\escape"):
            with self.subTest(member=name):
                self.write_apk(extra=[(name, b"not resource data")])
                self.reject()
        info = zipfile.ZipInfo("assets/link")
        info.create_system = 3
        info.external_attr = (stat.S_IFLNK | 0o777) << 16
        self.write_apk(extra=[(info, b"../../outside")])
        self.reject()

    def test_duplicate_incomplete_and_corrupt_zips_reject(self):
        self.export()
        self.write_apk(extra=[("AndroidManifest.xml", b"duplicate")])
        self.reject()
        for member in ("AndroidManifest.xml", "resources.arsc"):
            self.write_apk(omit=[member])
            self.reject()
        self.apk.write_bytes(b"not a ZIP")
        self.reject()
        self.write_apk()
        with zipfile.ZipFile(self.apk) as archive:
            offset = archive.getinfo("assets/video_001.mp4").header_offset
        data = bytearray(self.apk.read_bytes())
        name_length, extra_length = struct.unpack_from("<HH", data, offset + 26)
        data[offset + 30 + name_length + extra_length] ^= 1
        self.apk.write_bytes(data)
        self.reject()

    def test_package_and_firmware_rollbacks_reject(self):
        self.export()
        self.reject(badging(version=36))
        self.write_firmware(OLDER)
        self.reject()
        self.write_firmware(BUILD.replace("XXSDD", "XXSCD").replace("OXMDD", "OXMCD"))
        self.reject()

    def test_split_shrink_growth_and_idempotence_preserve_unrelated_files(self):
        self.output.mkdir(parents=True)
        (self.output / "README.md").write_text("preserved profile description")
        (self.output / "notes.txt").write_text("preserve unrelated notes")
        counts = []
        for size in (6000, 400, 4000):
            self.write_apk(size=size)
            receipt = self.export()
            counts.append(len(receipt["parts"]))
            self.assertEqual(b"".join((self.output / p["path"]).read_bytes()
                                     for p in receipt["parts"]), self.apk.read_bytes())
            before = snapshot(self.output)
            self.export()
            self.assertEqual(snapshot(self.output), before)
        self.assertGreater(counts[0], counts[1])
        self.assertGreater(counts[2], counts[1])
        self.assertEqual((self.output / "notes.txt").read_text(), "preserve unrelated notes")
        self.assertEqual((self.output / "README.md").read_text(), "preserved profile description")

    def test_missing_and_stale_existing_parts_reject(self):
        self.export()
        first = self.output / f"{BOT.APK_PATH}.00"
        original = first.read_bytes()
        first.unlink()
        self.reject()
        first.write_bytes(original)
        stale = self.output / f"{BOT.APK_PATH}.99"
        stale.write_bytes(b"unreceipted part")
        self.reject()
        stale.unlink()
        unsplit = self.output / BOT.APK_PATH
        unsplit.write_bytes(self.apk.read_bytes())
        self.reject()

    def test_invalid_previous_provenance_and_split_manifests_reject(self):
        receipt = self.export()
        path = self.output / "SOURCES.json"
        variants = [{**receipt, "sdk": 36}, {**receipt, "oneui": "80500"},
                    {**receipt, "model": "SM-S942B"}, {**receipt, "re_signed": True},
                    {**receipt, "package": {**receipt["package"], "version_code": "37"}},
                    {**receipt, "parts": []}, {**receipt, "apk_sha256": "bad"},
                    {**receipt, "parts": [{**receipt["parts"][0], "path": "../../outside"}]},
                    {**receipt, "parts": list(reversed(receipt["parts"]))}]
        for data in variants:
            with self.subTest(receipt=data):
                path.write_text(json.dumps(data))
                self.reject()
        path.write_text("not JSON")
        self.reject()

    def test_unreceipted_existing_payload_rejects(self):
        self.output.mkdir(parents=True)
        (self.output / ".current").write_text(BUILD)
        self.reject()

    def test_symlinked_destinations_and_metadata_are_never_followed(self):
        for relative in (".", "system", "system/priv-app", str(BOT.APK_PATH.parent),
                         f"{BOT.APK_PATH}.00", "SOURCES.json", ".current", "fs_config-system",
                         "file_context-system"):
            with self.subTest(path=relative), tempfile.TemporaryDirectory(dir=self.root) as tmp:
                output = Path(tmp) / BOT.PROFILE
                with mock.patch.object(self, "output", output):
                    self.export()
                    victim = output if relative == "." else output / relative
                    saved = Path(tmp) / "outside"
                    victim.rename(saved)
                    victim.symlink_to(saved, target_is_directory=saved.is_dir())
                    outside_before = snapshot(saved) if saved.is_dir() else saved.read_bytes()
                    self.reject()
                    self.assertEqual(snapshot(saved) if saved.is_dir() else saved.read_bytes(), outside_before)

    def test_symlinked_parent_and_input_files_reject(self):
        real_parent = self.root / "real output"
        real_parent.mkdir()
        alias = self.root / "alias"
        alias.symlink_to(real_parent, target_is_directory=True)
        with self.assertRaises(ValueError):
            BOT.export_wallpaper(self.firmware, alias / BOT.PROFILE, "unused")
        for original in (self.apk, self.props, self.firmware / ".extracted"):
            with self.subTest(input=original):
                saved = original.with_name(original.name + ".saved")
                original.rename(saved)
                original.symlink_to(saved)
                self.reject()
                original.unlink()
                saved.rename(original)

    def test_failed_staging_and_promotion_restore_previous_tree(self):
        self.export()
        self.write_apk(size=5000)
        before = snapshot(self.output)
        write = Path.write_bytes
        rename = Path.rename

        def failed_write(path, data):
            if path.name == "wallpaper-res.apk.01":
                raise OSError("synthetic full disk")
            return write(path, data)

        def failed_rename(path, target):
            if path.name == BOT.PROFILE and Path(target) == self.output:
                raise OSError("synthetic promotion failure")
            return rename(path, target)

        for method, failure in (("write_bytes", failed_write), ("rename", failed_rename)):
            with self.subTest(operation=method), mock.patch.object(Path, method, failure):
                self.reject()
                self.assertEqual(snapshot(self.output), before)

    def test_failed_rollback_retains_recoverable_backup(self):
        self.export()
        before = snapshot(self.output)
        rename = Path.rename

        def failure(path, target):
            if Path(target) == self.output:
                raise OSError("synthetic promotion and rollback failure")
            return rename(path, target)

        with mock.patch.object(Path, "rename", failure), self.assertRaises(OSError):
            self.export()
        backups = list(self.output.parent.glob(".wallpaper-blobs-*/previous"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(snapshot(backups[0]), before)

    def test_split_overflow_and_invalid_sizes_preserve_output(self):
        self.export()
        before = snapshot(self.output)
        for size in (0, -1, BOT.CHUNK_BYTES + 1, 1):
            with self.subTest(chunk_bytes=size), mock.patch.object(
                BOT.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, badging(), "")):
                with self.assertRaises(ValueError):
                    BOT.export_wallpaper(self.firmware, self.output, "mock-aapt2", chunk_bytes=size)
                self.assertEqual(snapshot(self.output), before)

    def test_feed_checks_android17_same_model_and_region(self):
        for args in ({"android": "16"}, {"android": "18"}, {"model": "SM-S942B"},
                     {"csc": "INS"}, {"build": ""}, {"build": "not a build"},
                     {"extra": f"<latest o='17'>{BUILD}</latest>"}):
            with self.subTest(feed=args), self.assertRaises(ValueError):
                BOT.check_update(self.feed(**args), self.output)
            self.assertIsNone(snapshot(self.output))
        self.assertEqual(BOT.check_update(self.feed(), self.output), {"firmware": BUILD, "update": True})

    def test_current_feed_skips_only_verified_payloads(self):
        self.export()
        self.assertEqual(BOT.check_update(self.feed(), self.output), {"firmware": BUILD, "update": False})
        self.assertEqual(BOT.check_update(self.feed(build=NEWER), self.output),
                         {"firmware": NEWER, "update": True})
        with self.assertRaises(ValueError):
            BOT.check_update(self.feed(build=OLDER), self.output)
        (self.output / f"{BOT.APK_PATH}.00").write_bytes(b"corrupt")
        with self.assertRaises(ValueError):
            BOT.check_update(self.feed(), self.output)

    def test_cli_outputs_and_actual_subprocess_boundary(self):
        feed = self.feed()
        result = subprocess.run([sys.executable, "-B", str(SCRIPT), "--feed", str(feed),
                                 "--output-dir", str(self.output)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, f"firmware={BUILD}\nupdate=true\n")
        aapt2 = self.root / "mock aapt2"
        aapt2.write_text(f"#!{sys.executable}\nimport sys\n"
                         "assert sys.argv[1:3] == ['dump', 'badging']\n"
                         f"print({badging()!r}, end='')\n")
        aapt2.chmod(0o755)
        result = subprocess.run([sys.executable, "-B", str(SCRIPT), "--firmware-dir", str(self.firmware),
                                 "--output-dir", str(self.output), "--aapt2", str(aapt2),
                                 "--expected-firmware", BUILD], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(BOT.read_profile(self.output)["apk_sha256"], BOT.sha(self.apk))


if __name__ == "__main__":
    unittest.main()
