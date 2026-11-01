# Copyright (c) 2026 ditternation
# SPDX-License-Identifier: GPL-3.0-or-later
"""Exercise the real shallow-push pack limit with small, disposable Git repos."""
import os
from pathlib import Path
import random
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
STEP = "      - name: Negotiate blob publication\n"


def publication_step():
    workflow = (ROOT / ".github/workflows/blobs.yml").read_text()
    return workflow.split(STEP, 1)[1].split("\n      - name:", 1)[0]


class BlobPublicationTests(unittest.TestCase):
    def test_negotiation_is_local_and_runs_before_the_guarded_pr_action(self):
        workflow = (ROOT / ".github/workflows/blobs.yml").read_text()
        step = publication_step()
        self.assertIn("        if: steps.blobs.outputs.update != 'false'\n", step)
        self.assertIn("        run: git config --local push.negotiate true\n", step)
        self.assertLess(workflow.index(STEP), workflow.index("      - name: Create Pull Request\n"))

    def test_negotiated_shallow_push_preserves_payload_under_the_pack_cap(self):
        with tempfile.TemporaryDirectory(prefix="blob-push-") as tmp:
            root = Path(tmp)
            server, seed, client = (root / name for name in ("server.git", "seed", "client"))
            # Neither caller Git config/hooks nor shell startup files may alter
            # the expected rejection or write outside these disposable repos.
            env = {key: value for key, value in os.environ.items()
                   if not key.startswith(("GIT_", "BASH_FUNC_"))
                   and key not in ("BASH_ENV", "ENV", "SHELLOPTS", "BASHOPTS")}
            env.update({"HOME": str(root), "XDG_CONFIG_HOME": str(root / "config"),
                        "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull,
                        "GIT_TERMINAL_PROMPT": "0", "LC_ALL": "C"})

            def git(args, cwd=root, check=True):
                result = subprocess.run(["git", *args], cwd=cwd, env=env,
                                        capture_output=True, text=True, timeout=30)
                if check:
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                return result

            def identity(repo):
                for key, value in (("user.name", "Blob Fixture"),
                                   ("user.email", "fixture@example.invalid"),
                                   ("commit.gpgsign", "false")):
                    git(["config", "--local", key, value], repo)

            git(["init", "--bare", "--template=", "--initial-branch=main", str(server)])
            git(["init", "--template=", "--initial-branch=main", str(seed)])
            identity(seed)
            (seed / ".gitattributes").write_text("*.bin binary\n")
            # Incompressible base bytes exceed the server cap; the new payload
            # fits comfortably. No firmware or external network is involved.
            (seed / "base.bin").write_bytes(random.Random(19).randbytes(512 * 1024))
            git(["add", "."], seed)
            git(["commit", "-m", "fixture base"], seed)
            git(["remote", "add", "origin", server.as_uri()], seed)
            git(["push", "origin", "main"], seed)
            git(["clone", "--template=", "--depth=1", "--branch=main",
                 server.as_uri(), str(client)])
            identity(client)
            self.assertEqual(git(["rev-parse", "--is-shallow-repository"], client).stdout.strip(),
                             "true")
            shallow = (client / ".git/shallow").read_bytes()
            stale_base = git(["rev-parse", "origin/main"], client).stdout.strip()

            # Mirror the long extraction window: the remote base advances after
            # checkout, so the push cannot simply exclude its advertised tip.
            (seed / "marker").write_text("remote base advanced during extraction\n")
            git(["add", "marker"], seed)
            git(["commit", "-m", "advance remote base"], seed)
            git(["push", "origin", "main"], seed)
            remote_base = git(["rev-parse", "refs/heads/main"], server).stdout.strip()
            self.assertNotEqual(stale_base, remote_base)
            git(["config", "--local", "receive.maxInputSize", "100000"], server)
            branch = "refs/heads/prebuilts/fixture"
            git(["switch", "-c", "prebuilts/fixture"], client)
            payload = random.Random(20).randbytes(8192)
            (client / "new.bin").write_bytes(payload)
            git(["add", "new.bin"], client)
            git(["commit", "-m", "fixture payload"], client)
            tip = git(["rev-parse", "HEAD"], client).stdout.strip()
            tree = git(["rev-parse", "HEAD^{tree}"], client).stdout.strip()
            payload_oid = git(["hash-object", "new.bin"], client).stdout.strip()

            rejected = git(["push", "origin", "HEAD:" + branch], client, check=False)
            self.assertNotEqual(rejected.returncode, 0)
            self.assertIn("pack exceeds maximum allowed size", rejected.stderr)
            self.assertEqual(git(["ls-remote", "origin", branch], client).stdout.strip(), "")

            # Replay the workflow command, not a separate test-only fix.
            script = publication_step().split("        run: ", 1)[1].strip()
            result = subprocess.run(["bash", "--noprofile", "--norc", "-e", "-o", "pipefail",
                                     "-c", script], cwd=client, env=env,
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(git(["config", "--local", "--get", "push.negotiate"],
                                 client).stdout.strip(), "true")
            git(["push", "origin", "HEAD:" + branch], client)

            self.assertEqual(git(["rev-parse", branch], server).stdout.strip(), tip)
            self.assertEqual(git(["rev-parse", branch + "^{tree}"], server).stdout.strip(), tree)
            self.assertEqual(git(["rev-parse", branch + ":new.bin"], server).stdout.strip(),
                             payload_oid)
            self.assertEqual((client / "new.bin").read_bytes(), payload)
            self.assertEqual(git(["rev-parse", "refs/heads/main"], server).stdout.strip(),
                             remote_base)
            self.assertEqual(git(["config", "--local", "--get", "receive.maxInputSize"],
                                 server).stdout.strip(), "100000")
            self.assertEqual((client / ".git/shallow").read_bytes(), shallow)


if __name__ == "__main__":
    unittest.main()
