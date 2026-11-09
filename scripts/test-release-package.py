#!/usr/bin/env python3
"""Exercise release provenance and artifact-selection boundaries without signing."""
import importlib.util
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location("release_package", Path(__file__).with_name("package-release.py"))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleasePackageTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="pearls-release-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def git(self, *args):
        subprocess.run(["git", "-C", str(self.root), *args], check=True, capture_output=True)

    def repository(self):
        self.git("init", "-q")
        (self.root / "app.swift").write_text("original")
        self.git("add", "app.swift")
        self.git("-c", "user.name=Release Test", "-c", "user.email=test@example.invalid", "commit", "-qm", "source")

    def archive(self):
        archive = self.root / "Pearls.xcarchive"
        for name in ["Info.plist", "Products/Applications/Pearls.app/Pearls",
                     "dSYMs/Pearls.app.dSYM/Contents/Resources/DWARF/Pearls",
                     "dSYMs/PearlsShare.appex.dSYM/Contents/Resources/DWARF/PearlsShare"]:
            path = archive / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"artifact")
        return archive

    def test_clean_commit_rejects_changed_tracked_and_untracked_source(self):
        self.repository()
        record = {"source": release.clean_source(self.root)}
        release.check_source(record, self.root)
        (self.root / "app.swift").write_text("changed")
        with self.assertRaises(release.ReleaseError):
            release.check_source(record, self.root)
        (self.root / "app.swift").write_text("original")
        (self.root / "uncommitted.swift").write_text("new")
        with self.assertRaises(release.ReleaseError):
            release.check_source(record, self.root)

    def test_clean_new_commit_does_not_match_captured_revision(self):
        self.repository()
        record = {"source": release.clean_source(self.root)}
        (self.root / "app.swift").write_text("changed")
        self.git("add", "app.swift")
        self.git("-c", "user.name=Release Test", "-c", "user.email=test@example.invalid", "commit", "-qm", "new source")
        with self.assertRaises(release.ReleaseError):
            release.check_source(record, self.root)

    def test_archive_only_allows_products_symbols_and_metadata(self):
        archive = self.archive()
        self.assertEqual(len(release.archive_files(archive)), 4)
        (archive / "personal-library.json").write_text("unrelated")
        with self.assertRaises(release.ReleaseError):
            release.archive_files(archive)

    def test_archive_rejects_keys_and_symlinks_inside_product(self):
        archive = self.archive()
        product = archive / "Products/Applications/Pearls.app"
        key = product / "signing.p12"
        key.write_bytes(b"not a real key")
        with self.assertRaises(release.ReleaseError):
            release.archive_files(archive)
        key.unlink()
        (product / "link").symlink_to(archive / "Info.plist")
        with self.assertRaises(release.ReleaseError):
            release.archive_files(archive)

    def test_ipa_rejects_traversal_unrelated_files_and_symlinks(self):
        for index, name in enumerate(["../outside", "Payload/Pearls.app/../../outside", "secret.txt", "Payload/Pearls.app/signing.p8"]):
            ipa = self.root / (str(index) + ".ipa")
            with zipfile.ZipFile(ipa, "w") as zipped:
                zipped.writestr(name, "data")
            with self.assertRaises(release.ReleaseError):
                release.inspect_ipa(ipa, self.root / "extract")
        ipa = self.root / "symlink.ipa"
        with zipfile.ZipFile(ipa, "w") as zipped:
            entry = zipfile.ZipInfo("Payload/Pearls.app/link")
            entry.external_attr = (stat.S_IFLNK | 0o777) << 16
            zipped.writestr(entry, "outside")
        with self.assertRaises(release.ReleaseError):
            release.inspect_ipa(ipa, self.root / "extract")

    def test_archive_bytes_and_retained_zip_are_checksummed(self):
        archive = self.archive()
        original = release.archive_files(archive)
        (archive / "Info.plist").write_bytes(b"different")
        self.assertNotEqual(original, release.archive_files(archive))
        output = self.root / "archive.zip"
        release.zip_files(output, archive, release.regular_files(archive), "Pearls.xcarchive/")
        with zipfile.ZipFile(output) as zipped:
            self.assertEqual(set(zipped.namelist()), {"Pearls.xcarchive/" + name for name in original})
        self.assertEqual(len(release.digest(output)), 64)


if __name__ == "__main__":
    unittest.main()
