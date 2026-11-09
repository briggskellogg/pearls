#!/usr/bin/env python3
"""Exercise release provenance and artifact-selection boundaries without signing."""
import importlib.util
import json
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
        # Packaging may consume an older completed build without relabeling it.
        self.assertEqual(release.validate_recorded_source(record, self.root), record["source"])

    def test_recorded_build_source_requires_existing_matching_commit_and_tree(self):
        self.repository()
        source = release.clean_source(self.root)
        for field in ("commit", "tree"):
            invalid = dict(source, **{field: "a" * 40})
            with self.assertRaises(release.ReleaseError):
                release.validate_recorded_source({"source": invalid}, self.root)
        with self.assertRaises(release.ReleaseError):
            release.validate_recorded_source({"source": dict(source, commit="--help")}, self.root)

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
        for index, name in enumerate(["../outside", "Payload/Pearls.app/../../outside", "secret.txt", "Payload/Pearls.app/signing.p8", "Symbols/not-a-uuid.symbols"]):
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

    def test_ipa_symbols_must_match_product_uuids(self):
        identifier = "FC650333-BE8B-389F-B972-D0342DC85778"
        ipa = self.root / "symbols.ipa"
        with zipfile.ZipFile(ipa, "w") as zipped:
            zipped.writestr("Symbols/", "")
            zipped.writestr("Symbols/" + identifier + ".symbols", "symbols")
        extracted = self.root / "extract"
        release.inspect_ipa(ipa, extracted)
        release.validate_symbol_files(extracted / "Symbols", {identifier})
        with self.assertRaises(release.ReleaseError):
            release.validate_symbol_files(extracted / "Symbols", {"4FD4E09F-9C68-342D-B868-B4DC1BEE7001"})

    def test_ipa_rejects_private_documents_inside_plausible_app_resources(self):
        for index, format_name in enumerate(("com.pearls.library", "com.pearls.archive", "com.pearls.sync", "com.pearls.sync.version")):
            with self.subTest(format=format_name):
                ipa = self.root / ("private-resource-" + str(index) + ".ipa")
                destination = self.root / ("private-extract-" + str(index))
                with zipfile.ZipFile(ipa, "w") as zipped:
                    zipped.writestr("Payload/Pearls.app/Pearls", b"synthetic executable")
                    zipped.writestr("Payload/Pearls.app/Resources/ordinary-name.dat", json.dumps({
                        "format": format_name, "schemaVersion": 1,
                        "items": [{"text": "synthetic-private-note"}],
                    }))
                with self.assertRaisesRegex(release.ReleaseError, "Public publication blocked") as caught:
                    release.inspect_ipa(ipa, destination)
                self.assertNotIn("synthetic-private-note", str(caught.exception))
                self.assertFalse(destination.exists(), "Private IPA must be rejected before extraction")

    def test_ipa_rejects_truncated_private_json_before_extraction(self):
        ipa = self.root / "damaged-resource.ipa"
        destination = self.root / "damaged-extract"
        with zipfile.ZipFile(ipa, "w") as zipped:
            zipped.writestr("Payload/Pearls.app/Resources/cache.bin", b'{"format":"com.pearls.library","items":[')
        with self.assertRaisesRegex(release.ReleaseError, "private Pearls document header"):
            release.inspect_ipa(ipa, destination)
        self.assertFalse(destination.exists())

    def test_ipa_allows_legitimate_artwork_fonts_and_public_manifest(self):
        ipa = self.root / "public-resources.ipa"
        destination = self.root / "public-extract"
        resources = {
            "Payload/Pearls.app/Pearls": b"synthetic executable",
            "Payload/Pearls.app/Resources/mark.png": b"\x89PNG\r\nsynthetic artwork",
            "Payload/Pearls.app/Resources/PPNeueMontreal-Regular.ttf": b"\x00\x01\x00\x00synthetic font",
            "Payload/Pearls.app/Resources/PPNeueYork-NormalLight.otf": b"OTTOsynthetic font",
            "Payload/Pearls.app/Resources/build.json": b'{"version":"0.1.0","build":"4","personal_library_included":false}',
        }
        with zipfile.ZipFile(ipa, "w") as zipped:
            for name, data in resources.items():
                zipped.writestr(name, data)
        self.assertEqual(release.inspect_ipa(ipa, destination), destination / "Payload/Pearls.app")
        for name, data in resources.items():
            self.assertEqual((destination / name).read_bytes(), data)

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
