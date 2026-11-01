# Copyright (c) 2026 ditternation
# SPDX-License-Identifier: GPL-3.0-or-later
"""Synthetic optical cohort gates; real native build/ELF review are separate."""
import hashlib
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "unica/patches/product_feature/customize.sh"
RUNTIME = "system/system/lib64/libandroid_runtime.so"
COHORT = {
    RUNTIME: ("4a21077a466d05232d8fc521455a3b9e1b036793e3a91bb32ac51252f6beb6b9",
              "7e7d3c0ecb6adc789e02d8d76e8defa0fc003651f514ec22b15efdb446c3f755"),
    "system/system/lib64/libgui.so": ("aff919fec79a2636533d8026a07ccaa31b3c92673142f68f64e0b60570329b04",),
    "system/system/lib64/libui.so": ("466dffbd2087a5a0c18b84717437e7204128af9343a9ec42657ba9839a309d0f",),
    "vendor/lib64/hw/android.hardware.graphics.allocator@4.0-impl.so": ("789d49fbcf3620160855e89b17323adf4366f0dff65cf8d1258153e0a6fe01d0",),
    "vendor/lib64/hw/android.hardware.graphics.mapper@4.0-impl.so": ("7859d7e6596127a32b178650a37219146615e5c324cd508b2ac5fb05c72bbcb4",),
    "vendor/lib64/libexynosgraphicbuffer.so": ("177570fe889185ea8834a2f4c55b513a4941e660328a43d452ad81fce1e58e54",),
    "vendor/lib64/libexynosdisplay.so": ("21ec8cf91ba79c838b04f2dedaf7af9192c194757a462549d8c9caa1dc7d1955",),
    "vendor/etc/vintf/manifest.xml": ("e292660d39a886d2a83b7f7e63b1c43b854760a3e1c9dd356c3acb3a7134f875",),
}


def fixture(folder, current=True, root_gate=False):
    # Only this private test copy substitutes explicitly synthetic digests.
    text = SCRIPT.read_text()
    end = text.index("# SEC_PRODUCT_FEATURE_BUILD_MAINLINE_API_LEVEL") if root_gate else text.index("PRODUCT_ENABLE_OPTICAL()")
    fragment = text[:end]
    platform = folder / "work"
    for relative, identities in COHORT.items():
        payloads = [("Synthetic optical cohort: " + relative + str(index)).encode() for index in range(len(identities))]
        for identity, payload in zip(identities, payloads):
            fragment = fragment.replace(identity, hashlib.sha256(payload).hexdigest())
        path = platform / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(payloads[int(current)] if relative == RUNTIME else payloads[0])
    script = folder / "gate.sh"
    script.write_text(fragment)
    return script, platform


def run_gate(script, platform, checked=False, root_gate=False, output=None, **options):
    harness = r'''
set -e
ABORT() { printf '%s\n' "$*" >&2; return 1; }
SET_FLOATING_FEATURE_CONFIG() { printf 'UNEXPECTED MUTATION\n' >&2; return 9; }
if [ "$CHECKED" = true ]; then
    if source "$GATE"; then :; else exit "$?"; fi
else
    source "$GATE"
fi
if [ "$ROOT_GATE" != true ]; then
    if [ -n "$OUTPUT" ]; then PRODUCT_OPTICAL native --platform "$WORK_DIR" --output "$OUTPUT";
    else PRODUCT_OPTICAL native --platform "$WORK_DIR"; fi
fi
'''
    env = {key: value for key, value in os.environ.items()
           if key not in ("BASH_ENV", "ENV", "SHELLOPTS", "BASHOPTS")}
    env.update(SRC_DIR=str(ROOT), WORK_DIR=str(platform), GATE=str(script), CHECKED=str(checked).lower(),
               ROOT_GATE=str(root_gate).lower(), OUTPUT=str(output) if output else "", SOURCE_PLATFORM_SDK_VERSION="37",
               TARGET_CODENAME="r9s", TARGET_PLATFORM_SDK_VERSION="36", TARGET_OS_SINGLE_SYSTEM_IMAGE="essi",
               SOURCE_COMMON_SUPPORT_DYN_RESOLUTION_CONTROL="false", TARGET_COMMON_SUPPORT_DYN_RESOLUTION_CONTROL="false",
               SOURCE_FINGERPRINT_CONFIG_SENSOR="google_touch_display_ultrasonic",
               TARGET_FINGERPRINT_CONFIG_SENSOR="google_touch_display_optical,settings=3")
    env.update(options)
    return subprocess.run(["bash", "--noprofile", "--norc", "-c", harness], cwd=ROOT, env=env,
                          capture_output=True, text=True, timeout=20)


class OpticalNativeCohortTests(unittest.TestCase):
    def test_production_native_table_retains_exact_eight_paths_and_nine_identities(self):
        text = SCRIPT.read_text()
        table = text.split("my %cohort=(", 1)[1].split("my %measured;", 1)[0]
        self.assertEqual(set(re.findall(r"'([0-9a-f]{64})'", table)), {value for values in COHORT.values() for value in values})
        self.assertEqual(set(re.findall(r"'([^']+)'=>", table)) | {"system/system/lib64/libui.so"}, set(COHORT))
        self.assertIn("input_sha256=>\\%measured", text)

    def test_both_exact_runtime_variants_pass_read_only(self):
        for current in (False, True):
            with self.subTest(current=current), tempfile.TemporaryDirectory(prefix="optical-cohort-") as tmp:
                script, platform = fixture(Path(tmp), current=current)
                before = {p: p.read_bytes() for p in platform.rglob("*") if p.is_file()}
                result = run_gate(script, platform)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual({p: p.read_bytes() for p in platform.rglob("*") if p.is_file()}, before)

    def test_every_unmeasured_native_input_rejects_before_output_creation(self):
        for relative in COHORT:
            with self.subTest(relative=relative), tempfile.TemporaryDirectory(prefix="optical-unknown-") as tmp:
                folder = Path(tmp)
                script, platform = fixture(folder)
                (platform / relative).write_bytes(b"unreviewed native bytes")
                output = folder / "not-created"
                result = run_gate(script, platform, output=output)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Unmeasured One UI 9/r9s optical native cohort: " + relative, result.stderr)
                self.assertFalse(output.exists())

    def test_missing_and_symlink_native_inputs_reject(self):
        for relative in COHORT:
            for symlink in (False, True):
                with self.subTest(relative=relative, symlink=symlink), tempfile.TemporaryDirectory(prefix="optical-missing-") as tmp:
                    folder = Path(tmp)
                    script, platform = fixture(folder)
                    path = platform / relative
                    content = path.read_bytes()
                    path.unlink()
                    if symlink:
                        target = folder / "outside-input"
                        target.write_bytes(content)
                        path.symlink_to(target)
                    result = run_gate(script, platform, output=folder / "not-created")
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("Missing/unsafe One UI 9/r9s optical native input", result.stderr)
                    self.assertFalse((folder / "not-created").exists())

    def test_existing_native_output_is_never_overwritten(self):
        with tempfile.TemporaryDirectory(prefix="optical-existing-") as tmp:
            folder = Path(tmp)
            script, platform = fixture(folder)
            output = folder / "existing"
            output.mkdir()
            (output / "sentinel").write_bytes(b"keep this output")
            result = run_gate(script, platform, output=output)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Refusing existing optical native outputs", result.stderr)
            self.assertEqual((output / "sentinel").read_bytes(), b"keep this output")

    def test_root_checks_both_variants_even_under_conditional_sourcing(self):
        for current in (False, True):
            for checked in (False, True):
                with self.subTest(current=current, checked=checked), tempfile.TemporaryDirectory(prefix="optical-root-") as tmp:
                    script, platform = fixture(Path(tmp), current=current, root_gate=True)
                    result = run_gate(script, platform, checked=checked, root_gate=True)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    (platform / RUNTIME).write_bytes(b"unreviewed runtime")
                    rejected = run_gate(script, platform, checked=checked, root_gate=True)
                    self.assertNotEqual(rejected.returncode, 0)
                    self.assertIn("Unmeasured One UI 9/r9s optical native cohort", rejected.stderr)
                    self.assertNotIn("UNEXPECTED MUTATION", rejected.stderr)

    def test_unsupported_optical_transition_still_rejects_before_mutation(self):
        for options in ({"TARGET_CODENAME": "t2s"}, {"TARGET_PLATFORM_SDK_VERSION": "35"}, {"TARGET_OS_SINGLE_SYSTEM_IMAGE": "qssi"}):
            with self.subTest(options=options), tempfile.TemporaryDirectory(prefix="optical-route-") as tmp:
                script, platform = fixture(Path(tmp), root_gate=True)
                result = run_gate(script, platform, checked=True, root_gate=True, **options)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Unreviewed One UI 9 fingerprint sensor-type transition", result.stderr)
                self.assertNotIn("UNEXPECTED MUTATION", result.stderr)

    def test_sdk36_and_unaffected_t2s_paths_do_not_read_optical_inputs(self):
        for options in ({"SOURCE_PLATFORM_SDK_VERSION": "36"},
                        {"TARGET_CODENAME": "t2s", "TARGET_PLATFORM_SDK_VERSION": "35",
                         "TARGET_FINGERPRINT_CONFIG_SENSOR": "google_touch_display_ultrasonic"}):
            with self.subTest(options=options), tempfile.TemporaryDirectory(prefix="optical-unaffected-") as tmp:
                script, platform = fixture(Path(tmp), root_gate=True)
                for relative in COHORT:
                    (platform / relative).unlink()
                result = run_gate(script, platform, checked=True, root_gate=True, **options)
                self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
