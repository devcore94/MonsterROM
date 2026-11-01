# Copyright (c) 2026 ditternation
# SPDX-License-Identifier: GPL-3.0-or-later
"""Replay the real NFC preflight before any Settings/firmware mutation."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
OLD = "408f490bf488a6ef364ed0d1d1c249a7546fe6cec1efecfce6552c9192dab597"
CURRENT = "00a29b4a9f83cf07746400613e0fa0910c50836e17ab92928a2c9651ed921ae0"
MANIFEST = """<manifest version="1.0" type="device"><hal format="hidl">
<name>android.hardware.nfc</name><transport>hwbinder</transport><version>1.2</version>
<interface><name>INfc</name><instance>default</instance></interface></hal></manifest>"""


class NfcTests(unittest.TestCase):
    def replay(self, digest=CURRENT, manifest=MANIFEST, missing=None, sdk=37, checked=False):
        source = (ROOT / "unica/patches/nfc/customize.sh").read_text()
        fragment = source.split("    # Settings is outside the NFC APEX.", 1)[0] + "fi\n"
        with tempfile.TemporaryDirectory(prefix="nfc-preflight-") as tmp:
            root = Path(tmp)
            work = root / "work"
            files = {
                "system/system/apex/com.android.nfcservices.capex": "synthetic fixture",
                "vendor/bin/hw/nxp.android.hardware.nfc@1.2-service": "fixture",
                "vendor/lib64/nfc_nci_nxpsn.so": "fixture",
                "vendor/etc/vintf/manifest/nxp.android.hardware.nfc@1.2-service.xml": manifest,
            }
            for name, content in files.items():
                if name == missing or content is None:
                    continue
                path = work / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content)
            firmware = root / "fw/SM-G996B_AUT/system/system/etc/libnfc-nci.conf"
            firmware.parent.mkdir(parents=True)
            firmware.write_text("fixture target configuration")
            script = root / "module.sh"
            script.write_text(fragment)
            trace = root / "mutations"
            harness = r'''
set -e
record() { printf '%s\n' "$*" >> "$TRACE"; }
LOG() { :; }
LOGW() { :; }
ABORT() { printf '%s\n' "$*" >&2; return 1; }
ADD_TO_WORK_DIR() { record "ADD $*"; }
DELETE_FROM_WORK_DIR() { record "DELETE $*"; }
sha256sum() {
    [ -s "$1" ] || return 1
    printf '%s  %s\n' "$DIGEST" "$1"
}
if [ "$CHECKED" = true ]; then
    if source "$FRAGMENT"; then :; else exit "$?"; fi
else
    source "$FRAGMENT"
fi
'''
            env = {key: value for key, value in os.environ.items()
                   if key not in ("BASH_ENV", "ENV", "SHELLOPTS", "BASHOPTS", "PYTHONPATH", "PYTHONHOME")}
            env.update({"WORK_DIR": str(work), "FW_DIR": str(root / "fw"),
                        "TARGET_FIRMWARE": "SM-G996B/AUT/fixture", "DEBUG": "false",
                        "SOURCE_PLATFORM_SDK_VERSION": str(sdk), "DIGEST": digest,
                        "CHECKED": str(checked).lower(), "FRAGMENT": str(script), "TRACE": str(trace)})
            result = subprocess.run(["bash", "--noprofile", "--norc", "-c", harness],
                                    env=env, capture_output=True, text=True, timeout=15)
            calls = trace.read_text().splitlines() if trace.exists() else []
        return result, calls

    def test_both_reviewed_packages_keep_the_target_configuration_path(self):
        for digest in (OLD, CURRENT):
            with self.subTest(digest=digest):
                result, calls = self.replay(digest=digest)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual([call.split()[0] for call in calls], ["ADD", "DELETE"])

    def test_unknown_hash_rejects_before_mutation_even_in_a_checked_source(self):
        for checked in (False, True):
            with self.subTest(checked=checked):
                result, calls = self.replay(digest="f" * 64, checked=checked)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Unreviewed One UI 9 NFC APEX", result.stderr)
                self.assertEqual(calls, [])

    def test_every_missing_required_input_rejects_before_mutation(self):
        for missing in ("system/system/apex/com.android.nfcservices.capex",
                        "vendor/bin/hw/nxp.android.hardware.nfc@1.2-service",
                        "vendor/lib64/nfc_nci_nxpsn.so",
                        "vendor/etc/vintf/manifest/nxp.android.hardware.nfc@1.2-service.xml"):
            with self.subTest(missing=missing):
                result, calls = self.replay(missing=missing)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(calls, [])

    def test_wrong_hardware_contract_rejects_despite_an_unrelated_version_match(self):
        hal = MANIFEST[MANIFEST.index("<hal"):MANIFEST.index("</manifest>")]
        variants = (
            MANIFEST.replace("android.hardware.nfc", "android.hardware.unrelated"),
            MANIFEST.replace("hwbinder", "passthrough"),
            MANIFEST.replace('format="hidl"', 'format="aidl"'),
            MANIFEST.replace("<name>INfc</name>", "<name>IOther</name>"),
            MANIFEST.replace("<instance>default</instance>", "<instance>other</instance>"),
            MANIFEST.replace("<version>1.2</version>", "<version>1.1</version>"),
            MANIFEST.replace('type="device"', 'type="framework"'),
            "<manifest>",
            MANIFEST.replace("</manifest>", hal + "</manifest>"),
        )
        for manifest in variants:
            with self.subTest(manifest=manifest):
                result, calls = self.replay(manifest=manifest, checked=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("incompatible target VINTF manifest", result.stderr)
                self.assertEqual(calls, [])

    def test_equivalent_fqname_declaration_is_accepted(self):
        manifest = """<manifest version="1.0" type="device"><hal format="hidl">
<name>android.hardware.nfc</name><transport>hwbinder</transport>
<fqname>@1.2::INfc/default</fqname></hal></manifest>"""
        result, calls = self.replay(manifest=manifest)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(calls), 2)

    def test_legacy_sdk_does_not_apply_the_modular_cohort_guard(self):
        result, calls = self.replay(sdk=36, digest="f" * 64, manifest=None)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(calls), 2)


if __name__ == "__main__":
    unittest.main()
