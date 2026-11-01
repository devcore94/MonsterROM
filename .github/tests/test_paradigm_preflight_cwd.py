# Copyright (c) 2026 ditternation
# SPDX-License-Identifier: GPL-3.0-or-later
"""Git must check every hunk even when a validator is called below repo root."""
from contextlib import chdir
from pathlib import Path
import tempfile
import unittest

import test_capture_actions_sources as capture
import test_recording_sources as recording
import test_subject_preview_sources as subject
import test_usb_permission_sources as usb


def corrupt_context(patch):
    lines = patch.read_text().splitlines(keepends=True)
    index = next(i for i, line in enumerate(lines) if line.startswith(" "))
    lines[index] = " deliberately incompatible source context\n"
    patch.write_text("".join(lines))


class ParadigmPreflightCwdTests(unittest.TestCase):
    def test_capture_version_and_context_from_repo_subdirectory(self):
        with tempfile.TemporaryDirectory() as tmp, chdir(capture.ROOT / ".github/tests"):
            module, _, decoded, expected = capture.fixture(Path(tmp))
            self.assertEqual(capture.VERIFY.verify_sources(module, decoded), expected)
            corrupt_context(module / "patches/SmartCapture.apk" / capture.VERIFY.MAIN_PATCHES[0])
            with self.assertRaisesRegex(ValueError, "patch preflight"):
                capture.VERIFY.verify_sources(module, decoded)

    def test_recording_version_and_context_from_repo_subdirectory(self):
        with tempfile.TemporaryDirectory() as tmp, chdir(recording.ROOT / ".github/tests"):
            module, decoded, expected = recording.fixture(Path(tmp))
            self.assertEqual(recording.VERIFY.verify_sources(module, decoded), expected)
            app, name = recording.VERIFY.MAIN_PATCHES[0]
            corrupt_context(module / "patches" / name)
            with self.assertRaisesRegex(ValueError, "patch preflight"):
                recording.VERIFY.verify_sources(module, decoded)

    def test_usb_context_from_repo_subdirectory(self):
        with tempfile.TemporaryDirectory() as tmp, chdir(usb.ROOT / ".github/tests"):
            module, decoded, _ = usb.fixture(Path(tmp))
            usb.VERIFY.verify_sources(module, decoded)
            corrupt_context(module / "patches/SecSettings.apk" / usb.VERIFY.PATCH_NAMES[0])
            with self.assertRaisesRegex(ValueError, "patch preflight"):
                usb.VERIFY.verify_sources(module, decoded)

    def test_subject_context_from_repo_subdirectory(self):
        with tempfile.TemporaryDirectory() as tmp, chdir(subject.ROOT / ".github/tests"):
            module, apk, decoded = subject.fixture(Path(tmp))
            subject.VERIFY.verify_sources(module, apk, decoded, check_patch=True)
            corrupt_context(module / subject.VERIFY.PATCH)
            with self.assertRaisesRegex(ValueError, "patch preflight"):
                subject.VERIFY.verify_sources(module, apk, decoded, check_patch=True)


if __name__ == "__main__":
    unittest.main()
