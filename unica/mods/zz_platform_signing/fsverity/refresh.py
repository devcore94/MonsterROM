#!/usr/bin/env python3
import filecmp
import os
import posixpath
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path
from zipfile import ZipFile

from fsverity_digests_pb2 import FSVerityDigests


def measure(path, directory):
    descriptor = directory / "descriptor"
    tree = directory / "tree"
    result = subprocess.check_output([
        "fsverity", "digest", "--compact", "--hash-alg=sha256", "--block-size=4096",
        f"--out-descriptor={descriptor}", f"--out-merkle-tree={tree}", path
    ], text=True)
    # AOSP FSVerityMetadata version 1, unsigned descriptor, page-aligned Merkle tree.
    output = directory / "metadata"
    with output.open("wb") as dst:
        dst.write(struct.pack("<I", 1))
        dst.write(descriptor.read_bytes())
        dst.write(struct.pack("<II", 0, 0))
        dst.seek(4096)
        with tree.open("rb") as src:
            shutil.copyfileobj(src, dst)
    return bytes.fromhex(result.strip()), output


def refresh(root, partition, manifest_apk, temp):
    with ZipFile(manifest_apk) as stock:
        manifest = FSVerityDigests.FromString(stock.read("assets/build_manifest.pb"))
    keys = set(manifest.digests)
    keys.update(f"{partition}/framework/{jar.name}" for jar in (root / "framework").glob("*.jar"))
    links = {}
    added = []
    removed = []
    changed = 0
    for key in sorted(keys):
        prefix, relative = key.split("/", 1)
        if prefix != partition or Path(relative).is_absolute() or ".." in Path(relative).parts:
            raise ValueError(f"Invalid fs-verity manifest path {key}")
        path = root / relative
        sidecar = path.with_name(path.name + ".fsv_meta")
        if path.is_symlink():
            target = posixpath.normpath(posixpath.join(posixpath.dirname(key), os.readlink(path))).lstrip("/")
            links[key] = target
            continue
        if not path.is_file():
            if key in manifest.digests:
                del manifest.digests[key]
            if os.path.lexists(sidecar):
                removed.append(relative + ".fsv_meta")
            continue
        digest, metadata = measure(path, temp)
        item = manifest.digests[key]
        item.digest = digest
        item.hash_alg = "sha256"
        if sidecar.is_symlink() or not sidecar.is_file() or not filecmp.cmp(metadata, sidecar, shallow=False):
            if not sidecar.exists():
                added.append(relative + ".fsv_meta")
            with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as output:
                with metadata.open("rb") as data:
                    shutil.copyfileobj(data, output)
            new = Path(output.name)
            new.chmod(0o644)
            new.replace(sidecar)
            changed += 1
    for key, target in links.items():
        if target not in manifest.digests or target in links:
            raise ValueError(f"Unresolved fs-verity link {key} -> {target}")
        manifest.digests[key].CopyFrom(manifest.digests[target])
        path = root / key.split("/", 1)[1]
        sidecar = path.with_name(path.name + ".fsv_meta")
        expected = os.readlink(path) + ".fsv_meta"
        if not sidecar.is_symlink() or os.readlink(sidecar) != expected:
            raise ValueError(f"Unexpected fs-verity link for {key}")
    with ZipFile(manifest_apk) as old, ZipFile(temp / "manifest-unsigned.apk", "w") as new:
        for entry in old.infolist():
            if entry.filename.startswith(("META-INF/", "SEC-INF/")):
                continue
            data = manifest.SerializeToString(deterministic=True) if entry.filename == "assets/build_manifest.pb" else old.read(entry)
            new.writestr(entry, data)
    for name, paths in [("added", added), ("removed", removed)]:
        (temp / name).write_text("".join(path + "\n" for path in paths))
    print(f"{partition}: {len(manifest.digests)} file digests, {changed} updated sidecars")


if __name__ == "__main__":
    refresh(Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3]), Path(sys.argv[4]))
