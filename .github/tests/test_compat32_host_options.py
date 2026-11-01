# Copyright (c) 2026 ditternation
# SPDX-License-Identifier: GPL-3.0-or-later
"""Quiet modern host warnings without altering APEX signing or copy semantics."""
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "unica/patches/vndk/compat32/build-apex.sh"


def environment(values):
    env = {key: value for key, value in os.environ.items()
           if key not in ("BASH_ENV", "ENV", "SHELLOPTS", "BASHOPTS")}
    return {**env, **values}


class Compat32HostOptionTests(unittest.TestCase):
    def test_jvm_permission_keeps_both_original_certificate_paths_and_signing_options(self):
        script = SCRIPT.read_text()
        command = "signapk " + script.split("    signapk ", 1)[1].split("\nfi\n", 1)[0]
        with tempfile.TemporaryDirectory(prefix="compat32-host-") as tmp:
            folder = Path(tmp)
            trace = folder / "arguments"
            for cert in ("aosp", "unica"):
                with self.subTest(cert=cert):
                    env = environment({"CERT": cert, "SRC_DIR": str(folder / "source with spaces"),
                                       "TEMP": str(folder / "temporary with spaces"),
                                       "NAME": "com.android.runtime.apex", "TRACE": str(trace),
                                       "OUTPUT": str(folder / "signed output.apex")})
                    harness = "signapk() { printf '%s\\0' \"$@\" > \"$TRACE\"; }\n"
                    result = subprocess.run(["bash", "--noprofile", "--norc", "-e", "-u",
                                             "-o", "pipefail", "-c", harness + command],
                                            env=env, capture_output=True, text=True, timeout=10)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    args = trace.read_bytes().decode().split("\0")[:-1]
                    self.assertEqual(args, [
                        "-J-enable-native-access=ALL-UNNAMED", "-a", "4096", "--align-file-size",
                        f"{env['SRC_DIR']}/security/{cert}_platform.x509.pem",
                        f"{env['SRC_DIR']}/security/{cert}_platform.pk8",
                        f"{env['TEMP']}/apex/dist/{env['NAME']}", env["OUTPUT"],
                    ])

    def test_icu_copy_retains_existing_nodes_and_metadata_without_a_deprecation_warning(self):
        command = next(line.strip() for line in SCRIPT.read_text().splitlines()
                       if line.strip().startswith("sudo cp ") and '"$TEMP/arm32/etc/icu/."' in line)
        with tempfile.TemporaryDirectory(prefix="compat32-icu-copy-") as tmp:
            folder = Path(tmp)
            source, target = (folder / path for path in ("arm32/etc/icu", "payload/etc/icu"))
            source.mkdir(parents=True)
            target.mkdir(parents=True)
            (source / "existing.dat").write_bytes(b"must not overwrite original")
            original = target / "existing.dat"
            original.write_bytes(b"original One UI 9 data")
            original.chmod(0o640)
            os.utime(original, ns=(1000000000, 2000000000))
            before = original.stat()
            (source / "added.dat").write_bytes(b"ARM32 addition")
            (source / "added.dat").chmod(0o640)
            (source / ".hidden.dat").write_bytes(b"retained hidden addition")
            (source / "link.dat").symlink_to("added.dat")
            (source / "existing-link.dat").symlink_to("added.dat")
            (target / "existing-link.dat").symlink_to("existing.dat")
            result = subprocess.run(["bash", "--noprofile", "--norc", "-e", "-u", "-o", "pipefail",
                                     "-c", 'sudo() { "$@"; }\n' + command],
                                    env=environment({"TEMP": str(folder)}),
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn("warning", result.stderr.lower())
            self.assertEqual(original.read_bytes(), b"original One UI 9 data")
            self.assertEqual(stat.S_IMODE(original.stat().st_mode), stat.S_IMODE(before.st_mode))
            self.assertEqual(original.stat().st_mtime_ns, before.st_mtime_ns)
            self.assertEqual((target / "added.dat").read_bytes(), b"ARM32 addition")
            self.assertEqual(stat.S_IMODE((target / "added.dat").stat().st_mode), 0o640)
            self.assertEqual((target / ".hidden.dat").read_bytes(), b"retained hidden addition")
            self.assertEqual(os.readlink(target / "link.dat"), "added.dat")
            self.assertEqual(os.readlink(target / "existing-link.dat"), "existing.dat")


if __name__ == "__main__":
    unittest.main()
