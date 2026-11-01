# Copyright (c) 2026 ditternation
# SPDX-License-Identifier: GPL-3.0-or-later
"""Patch application must not silently skip files when invoked below the repo root."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
PATCH = "Subject: [PATCH] Change fixture\n\n--- a/fixture.txt\n+++ b/fixture.txt\n@@ -1 +1 @@\n-old\n+new\n"


class ModulePatchCwdTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="module-patch-cwd-", dir=ROOT / "out")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.patch = self.root / "change.patch"
        self.patch.write_text(PATCH)
        self.env = dict(os.environ, SRC_DIR=str(ROOT), TARGET_OS_SINGLE_SYSTEM_IMAGE="essi")
        self.env.update(FIXTURE_PATCH=str(self.patch))

    def test_real_apk_patch_helper_applies_and_rejects_wrong_context(self):
        decoded = self.root / "apktool/system/priv-app/Example/Example.apk"
        decoded.mkdir(parents=True)
        fixture = decoded / "fixture.txt"
        self.env["APKTOOL_DIR"] = str(self.root / "apktool")
        script = '''source "$SRC_DIR/scripts/utils/module_utils.sh"
APPLY_PATCH system system/priv-app/Example/Example.apk "$FIXTURE_PATCH"
'''
        for cwd in (ROOT, ROOT / "scripts", ROOT / "unica/mods/setupwizard"):
            for content, expected_status, expected_content in (("old\n", 0, "new\n"), ("wrong\n", 1, "wrong\n")):
                with self.subTest(cwd=cwd, content=content):
                    fixture.write_text(content)
                    result = subprocess.run(["bash", "--noprofile", "--norc", "-c", script], cwd=cwd,
                                            env=self.env, capture_output=True, text=True, timeout=20)
                    self.assertEqual(result.returncode, expected_status, result.stderr)
                    self.assertEqual(fixture.read_text(), expected_content)

    def test_real_module_runner_applies_direct_git_calls_from_subdirectory(self):
        modules = self.root / "modules"
        module = modules / "fixture"
        module.mkdir(parents=True)
        (module / "module.prop").write_text("id=fixture\nname=fixture\nauthor=test\n")
        (module / "customize.sh").write_text('''SKIPUNZIP=1
LC_ALL=C git apply --check --unsafe-paths --directory="$FIXTURE_DEST" "$FIXTURE_PATCH"
LC_ALL=C git apply --unsafe-paths --directory="$FIXTURE_DEST" "$FIXTURE_PATCH"
''')
        dest = self.root / "destination"
        dest.mkdir()
        fixture = dest / "fixture.txt"
        self.env["FIXTURE_DEST"] = str(dest)
        cwd = ROOT / "scripts"
        for content, succeeds, expected in (("old\n", True, "new\n"), ("wrong\n", False, "wrong\n")):
            with self.subTest(content=content):
                fixture.write_text(content)
                result = subprocess.run(["bash", str(ROOT / "scripts/internal/apply_modules.sh"),
                                         os.path.relpath(modules, cwd)], cwd=cwd, env=self.env,
                                        capture_output=True, text=True, timeout=20)
                self.assertEqual(result.returncode == 0, succeeds, result.stderr)
                self.assertEqual(fixture.read_text(), expected)

    def test_build_cache_hash_tracks_builder_scripts_for_both_platform_routes(self):
        source = self.root / "source"
        for path in ("buildenv.sh", "scripts/utils/module_utils.sh", "unica/patch.patch",
                     "target/t2s/config.sh", "platform/exynos2100/patches/example.patch"):
            file = source / path
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text("original\n")
        make_rom = (ROOT / "scripts/make_rom.sh").read_text()
        function = make_rom.split("GET_WORK_DIR_HASH()\n", 1)[1].split("\nPREPARE_SCRIPT()", 1)[0]
        env = {k: v for k, v in self.env.items() if not k.startswith("UN1CA_QPR2_")}
        env.update(SRC_DIR=str(source), TARGET_CODENAME="t2s")
        selectors = {
            "UN1CA_QPR2_CAMERA_METADATA": ("true", "false"),
            "UN1CA_QPR2_CAMERA_PATH": ("true", "false"),
            "UN1CA_QPR2_SUBJECT_CPU_PREVIEW": ("true", "false"),
            "UN1CA_QPR2_MAINLINE": ("true", "false"),
            "UN1CA_QPR2_SWCODEC": ("false", "true"),
            "UN1CA_QPR2_RUNTIME_COHORT": ("off", "trial-r15"),
            "UN1CA_QPR2_CPU_LEAVES": ("true", "false"),
            "UN1CA_QPR2_GSI_DIR": (str(source / "prebuilts/qpr2"), str(source / "other")),
        }
        for platform in ("exynos2100", "none"):
            env["TARGET_PLATFORM"] = platform
            def digest():
                return subprocess.run(["bash", "-c", "GET_WORK_DIR_HASH()\n" + function + "\nGET_WORK_DIR_HASH"],
                                      env=env, check=True, capture_output=True, text=True).stdout.strip()
            with self.subTest(platform=platform):
                before = digest()
                for name in ("buildenv.sh", "scripts/utils/module_utils.sh"):
                    path = source / name
                    path.write_text("changed\n")
                    self.assertNotEqual(digest(), before, name)
                    path.write_text("original\n")
                    self.assertEqual(digest(), before, name)
                for name, (default, alternate) in selectors.items():
                    env[name] = default
                    self.assertEqual(digest(), before, name)
                    env[name] = alternate
                    self.assertNotEqual(digest(), before, name)
                    del env[name]


if __name__ == "__main__":
    unittest.main()
