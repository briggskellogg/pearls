#!/usr/bin/env python3
"""Local-only regression checks for source mirroring and conflict preservation."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("pearls_sync", Path(__file__).with_name("sync-project.py"))
sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync)


class MirrorTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="pearls-sync-test-")
        self.root = Path(self.temporary.name).resolve()
        self.destination = self.root / "proton" / "pearls"
        self.receipt = self.root / "local" / "receipt.json"
        self.files = {"README.md": (b"hello\n", False), "scripts/run.sh": (b"#!/bin/sh\n", True)}

    def tearDown(self):
        self.temporary.cleanup()

    def publish(self, files=None, commit="a" * 40):
        return sync.mirror(self.destination, commit, files if files is not None else self.files, self.receipt)

    def test_first_copy_and_unchanged_repeat_preserve_executable_bits(self):
        self.assertEqual(self.publish(), (2, 0))
        self.assertEqual(self.publish(), (0, 0))
        self.assertTrue(os.access(self.destination / "scripts/run.sh", os.X_OK))
        remote_receipt = json.loads((self.destination / sync.RECEIPT).read_text())
        self.assertEqual(remote_receipt, json.loads(self.receipt.read_text()))
        self.assertEqual(remote_receipt["files"]["README.md"]["sha256"], sync.fingerprint(b"hello\n")["sha256"])

    def test_existing_identical_files_are_adopted_and_extras_preserved(self):
        self.destination.mkdir(parents=True)
        (self.destination / "README.md").write_bytes(b"hello\n")
        (self.destination / "personal.txt").write_text("keep me")
        self.assertEqual(self.publish(), (1, 0))
        self.assertEqual((self.destination / "personal.txt").read_text(), "keep me")

    def test_existing_different_file_aborts_before_any_copy(self):
        self.destination.mkdir(parents=True)
        (self.destination / "README.md").write_text("other source")
        with self.assertRaisesRegex(sync.SyncError, "Destination edits"):
            self.publish()
        self.assertFalse((self.destination / "scripts").exists())
        self.assertFalse(self.receipt.exists())

    def test_modified_mirror_blocks_overwrite_and_unrelated_write(self):
        self.publish()
        (self.destination / "README.md").write_text("edit in Proton")
        changed = dict(self.files, **{"new.txt": (b"new", False), "README.md": (b"upstream", False)})
        with self.assertRaisesRegex(sync.SyncError, "README.md"):
            self.publish(changed, "b" * 40)
        self.assertEqual((self.destination / "README.md").read_text(), "edit in Proton")
        self.assertFalse((self.destination / "new.txt").exists())

    def test_changed_file_is_never_deleted(self):
        self.publish()
        (self.destination / "README.md").write_text("keep")
        with self.assertRaisesRegex(sync.SyncError, "README.md"):
            self.publish({"scripts/run.sh": self.files["scripts/run.sh"]})
        self.assertEqual((self.destination / "README.md").read_text(), "keep")

    def test_unchanged_removed_source_is_deleted_and_extras_remain(self):
        self.publish()
        (self.destination / "extra.txt").write_text("keep")
        self.assertEqual(self.publish({"README.md": self.files["README.md"]}), (0, 1))
        self.assertFalse((self.destination / "scripts/run.sh").exists())
        self.assertEqual((self.destination / "extra.txt").read_text(), "keep")

    def test_user_deleted_file_is_not_silently_recreated(self):
        self.publish()
        (self.destination / "README.md").unlink()
        with self.assertRaisesRegex(sync.SyncError, "README.md"):
            self.publish()

    def test_incomplete_copy_can_resume_when_written_bytes_match_target(self):
        self.publish()
        changed = dict(self.files, **{"README.md": (b"new content", False), "new.txt": (b"new", False)})
        (self.destination / "README.md").write_bytes(b"new content")
        self.assertEqual(self.publish(changed, "b" * 40), (1, 0))

    def test_symlink_destination_ancestor_and_file_are_rejected(self):
        real = self.root / "real"
        real.mkdir()
        link = self.root / "link"
        link.symlink_to(real, target_is_directory=True)
        with self.assertRaisesRegex(sync.SyncError, "Symlink"):
            sync.preflight(link / "pearls", self.files)
        self.destination.mkdir(parents=True)
        (real / "README.md").write_text("protected")
        (self.destination / "README.md").symlink_to(real / "README.md")
        with self.assertRaisesRegex(sync.SyncError, "Symlink"):
            self.publish()
        self.assertEqual((real / "README.md").read_text(), "protected")

    def test_corrupt_or_traversal_receipt_is_rejected(self):
        self.publish()
        receipt = json.loads(self.receipt.read_text())
        receipt["files"]["../outside"] = sync.fingerprint(b"outside")
        (self.destination / sync.RECEIPT).write_text(json.dumps(receipt))
        with self.assertRaisesRegex(sync.SyncError, "Unsafe project path"):
            self.publish()

    def test_file_blocking_directory_is_rejected(self):
        self.destination.mkdir(parents=True)
        (self.destination / "scripts").write_text("do not overwrite")
        with self.assertRaisesRegex(sync.SyncError, "not a directory"):
            self.publish()
        self.assertFalse((self.destination / "README.md").exists())


class SnapshotTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="pearls-git-test-")
        self.root = Path(self.temporary.name).resolve()
        self.command("init", "-b", "main")
        self.command("config", "user.name", "Local test")
        self.command("config", "user.email", "local@example.invalid")
        self.command("remote", "add", "origin", "https://github.com/briggskellogg/pearls.git")
        (self.root / "source.txt").write_text("original")
        self.commit()

    def tearDown(self):
        self.temporary.cleanup()

    def command(self, *args):
        return subprocess.run(["git", "-C", str(self.root), *args], check=True, capture_output=True).stdout

    def commit(self):
        self.command("add", "-A")
        self.command("commit", "-m", "local fixture")

    def test_reads_only_committed_files_without_network(self):
        (self.root / "untracked.txt").write_text("not committed")
        commit, files = sync.snapshot(self.root)
        self.assertEqual(len(commit), 40)
        self.assertEqual(files, {"source.txt": (b"original", False)})

    def test_dirty_worktree_wrong_remote_and_branch_fail(self):
        (self.root / "source.txt").write_text("modified")
        with self.assertRaisesRegex(sync.SyncError, "Commit tracked"):
            sync.snapshot(self.root)
        self.command("restore", "source.txt")
        self.command("remote", "set-url", "--push", "origin", "https://github.com/another/project.git")
        with self.assertRaisesRegex(sync.SyncError, "origin must"):
            sync.snapshot(self.root)
        self.command("checkout", "-b", "feature")
        with self.assertRaisesRegex(sync.SyncError, "Switch to main"):
            sync.snapshot(self.root)

    def test_committed_symlink_and_signing_key_are_rejected(self):
        (self.root / "link").symlink_to("source.txt")
        self.commit()
        with self.assertRaisesRegex(sync.SyncError, "regular source"):
            sync.snapshot(self.root)
        (self.root / "link").unlink()
        (self.root / "key.p8").write_text("synthetic test string")
        self.commit()
        with self.assertRaisesRegex(sync.SyncError, "private configuration"):
            sync.snapshot(self.root)


if __name__ == "__main__":
    unittest.main()
