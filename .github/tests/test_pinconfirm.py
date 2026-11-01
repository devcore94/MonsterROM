# Copyright (c) 2026 ditternation
# SPDX-License-Identifier: GPL-3.0-or-later
"""Check the PIN confirmation module's SDK-specific patch dispatch."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SERVICES = Path("system/framework/services.jar")
SETTINGS = Path("system/priv-app/SecSettings/SecSettings.apk")
CONTROLLER = Path("com/android/settings/security/screenlock/AutoPinConfirmPreferenceController.smali")


def method(name, instruction):
    return f".method public {name}\n    .locals 16\n\n    {instruction}\n\n.end method\n"


class PinConfirmTests(unittest.TestCase):
    def run_module(self, sdk, corrupt=False):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            smali = "smali_classes2" if sdk == 37 else "smali"
            files = {
                SERVICES / smali / "com/android/server/locksettings/LockSettingsService.smali":
                    method("refreshStoredPinLength(I)Z", "const/4 v0, 0x6"),
                SERVICES / smali / "com/android/server/locksettings/SyntheticPasswordManager.smali":
                    method("createLskfBasedProtector(Landroid/service/gatekeeper/IGateKeeperService;Lcom/android/internal/widget/LockscreenCredential;JLcom/android/internal/widget/LockscreenCredential;Lcom/android/server/locksettings/SyntheticPasswordManager$SyntheticPassword;I)J", "const/4 v12, 0x6"),
                SETTINGS / smali / "com/android/settings/password/ChooseLockPassword$ChooseLockPasswordFragment.smali":
                    method("handleNext$2()V", "const/4 v4, 0x6") +
                    method("setAutoPinConfirmOption(IZ)V", "const/4 p2, 0x6"),
            }
            if sdk == 37:
                files[SETTINGS / smali / CONTROLLER] = (
                    ".method public final isAvailable()Z\n    .locals 3\n"
                    "    invoke-virtual {v0, v1}, Lx;->getCredentialTypeForUser(I)I\n"
                    "    if-ne v0, v2, :cond_0\n"
                    "    invoke-virtual {p0, v1}, Lx;->getPinLength(I)I\n"
                    f"    const/4 v0, 0x{5 if corrupt else 6}\n"
                    "    if-lt p0, v0, :cond_0\n    return p0\n.end method\n"
                )
            for path, content in files.items():
                target = base / path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(content)
            env = os.environ | {"SRC_DIR": str(ROOT), "APKTOOL_DIR": str(base),
                                "SOURCE_PLATFORM_SDK_VERSION": str(sdk)}
            script = '''set -e
source "$SRC_DIR/scripts/utils/smali_utils.sh"
DECODE_APK() { :; }
IS_VALID_PARTITION_NAME() { [ "$1" = system ]; }
LOG() { :; }
MODPATH="$SRC_DIR/unica/mods/pinconfirm"
source "$MODPATH/customize.sh"
'''
            result = subprocess.run(["bash", "-c", script], env=env,
                                    text=True, capture_output=True)
            output = {path: (base / path).read_text() for path in files}
            return result, files, output

    def test_patches_all_thresholds_without_removing_checks(self):
        result, before, after = self.run_module(37)
        self.assertEqual(result.returncode, 0, result.stderr)
        controller = SETTINGS / "smali_classes2" / CONTROLLER
        self.assertEqual(after[controller], before[controller].replace("const/4 v0, 0x6", "const/4 v0, 0x4"))
        for path in before:
            self.assertNotIn("0x6", after[path])
            self.assertIn("0x4", after[path])

    def test_older_layout_does_not_require_controller(self):
        result, _, _ = self.run_module(36)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_unexpected_controller_fails_closed(self):
        result, _, _ = self.run_module(37, corrupt=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Failed to replace value", result.stderr)


if __name__ == "__main__":
    unittest.main()
