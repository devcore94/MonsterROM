#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Export a mounted Android partition and UN1CA's two filesystem manifests."""
import errno
import os
from pathlib import Path
import re
import stat
import struct
import subprocess
import sys


def capabilities(path):
    try:
        raw = os.getxattr(path, "security.capability", follow_symlinks=False)
    except OSError as error:
        if error.errno == errno.ENODATA:
            return 0
        raise
    revision = int.from_bytes(raw[:4], "little") >> 24
    if (revision, len(raw)) not in ((1, 12), (2, 20), (3, 24)):
        raise ValueError(f"Unknown capability xattr on {path}")
    low = struct.unpack_from("<I", raw, 4)[0]
    high = struct.unpack_from("<I", raw, 12)[0] if revision > 1 else 0
    return high << 32 | low


def export_partition(mount, partition, output):
    if not os.path.ismount(mount):
        raise ValueError(f"Expected a mounted image at {mount}")
    # Android system-as-root stores /system and the early root directory together.
    system_root = partition == "system" and (mount / "system").is_dir()
    destination = output / partition
    destination.mkdir(exist_ok=True)
    subprocess.run(["rsync", "-aH", "--delete", "--no-owner", "--no-group",
                    "--chmod=Du+rwx,Fu+rw", "--exclude=/lost+found",
                    f"{mount}/", f"{destination}/"], check=True)

    def paths():
        yield mount
        for directory, dirs, files in os.walk(mount):
            if Path(directory) == mount and "lost+found" in dirs:
                dirs.remove("lost+found")
            dirs.sort()
            for name in sorted(dirs + files):
                yield Path(directory) / name

    with (output / f"fs_config-{partition}").open("w") as config, \
         (output / f"file_context-{partition}").open("w") as contexts:
        for path in paths():
            rel = path.relative_to(mount).as_posix()
            name = "" if rel == "." else rel
            prefix = "" if system_root else partition
            absolute = "/" + "/".join(filter(None, (prefix, name)))
            entry = absolute[1:] if name else ""
            metadata = path.lstat()
            mode = stat.S_IMODE(metadata.st_mode)
            cap = capabilities(path)
            print(f"{entry} {metadata.st_uid} {metadata.st_gid} {mode:o} capabilities={cap:#x}", file=config)
            label = os.getxattr(path, "security.selinux", follow_symlinks=False).rstrip(b"\0").decode()
            escaped = re.sub(r"([\\.^$*+?{}\[\]()|\s])", r"\\\1", absolute)
            print(f"{escaped} {label}", file=contexts)


if __name__ == "__main__":
    export_partition(Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3]))
