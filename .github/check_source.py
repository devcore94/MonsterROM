#!/usr/bin/env python3
"""Firmware-free checks; these do not claim a ROM build or device validation."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys


def main():
    root = Path(__file__).resolve().parent.parent
    names = subprocess.check_output(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
        cwd=root,
    ).decode().split("\0")
    counts = {"shell": 0, "patch": 0, "json": 0, "payload": 0}
    errors = []

    def check_payload(path, expected):
        counts["payload"] += 1
        try:
            digest = hashlib.sha256()
            with path.open("rb") as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(chunk)
            if digest.hexdigest() != expected:
                errors.append(f"{path.relative_to(root)}: payload checksum mismatch")
        except OSError as error:
            errors.append(f"{path.relative_to(root)}: {error}")

    for name in sorted(set(names) - {""}):
        path = root / name
        if not path.is_file() or path.is_symlink():
            continue
        if path.stat().st_size >= 100 * 1024 * 1024:
            errors.append(f"{name}: exceeds GitHub's 100 MiB file limit")
        if path.suffix == ".sh":
            counts["shell"] += 1
            command = ["bash", "-n", name]
        elif path.suffix == ".patch":
            counts["patch"] += 1
            command = ["git", "apply", "--numstat", "--", name]
        elif path.suffix == ".json":
            counts["json"] += 1
            try:
                # Retained Samsung resource JSON can legitimately carry a BOM.
                json.loads(path.read_text(encoding="utf-8-sig"))
            except (ValueError, UnicodeError) as error:
                errors.append(f"{name}: {error}")
            continue
        else:
            continue
        result = subprocess.run(command, cwd=root, capture_output=True, text=True)
        if result.returncode:
            errors.append(f"{name}: {result.stdout}{result.stderr}")

    # These manifests describe shipped repository bytes, not external firmware
    # or decoded class contracts. In particular, a text-normalized TFLite file
    # must fail in a clean checkout rather than reach the ROM builder corrupted.
    manifests = [
        ("unica/mods/paradigm/qpr2/subject_cpu/payload.sha256", "."),
        ("unica/mods/paradigm/qpr2/webcam_native/libraries.sha256", "files/arm64-v8a"),
        ("unica/mods/prophide/SHA256SUMS", "."),
    ]
    for name, subdir in manifests:
        manifest = root / name
        base = manifest.parent / subdir
        try:
            lines = manifest.read_text().splitlines()
            if not lines:
                errors.append(f"{name}: empty payload manifest")
            for line in lines:
                expected, relative = line.split()
                check_payload(base / relative, expected)
        except (OSError, ValueError) as error:
            errors.append(f"{name}: {error}")
    for name in ["prebuilts/qpr2/SOURCES.json", "prebuilts/qpr2-runtime/SOURCES.json"]:
        try:
            manifest = json.loads((root / name).read_text())
            entries = manifest.get("inputs", manifest.get("components", []))
            if not entries:
                errors.append(f"{name}: empty component manifest")
            for entry in entries:
                check_payload(root / entry["repository_path"],
                              entry.get("sha256", entry.get("new_sha256")))
        except (OSError, ValueError, KeyError, TypeError) as error:
            errors.append(f"{name}: {error}")
    for error in errors:
        print(error, file=sys.stderr)
    print(
        f"{'FAIL' if errors else 'PASS'}: {counts['shell']} shell files, "
        f"{counts['patch']} ordinary patches, {counts['json']} JSON documents, "
        f"{counts['payload']} pinned payloads"
    )
    return bool(errors)


if __name__ == "__main__":
    sys.exit(main())
