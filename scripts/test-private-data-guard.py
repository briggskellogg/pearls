#!/usr/bin/env python3
"""Synthetic-only checks that public artifacts cannot contain Pearls libraries."""
from io import BytesIO
import json
import sys
import unittest
import zipfile

sys.dont_write_bytecode = True
from private_data_guard import PrivateDataError, ensure_public_file


class PublicInputTests(unittest.TestCase):
    def reject(self, name, data):
        with self.assertRaises(PrivateDataError) as caught:
            ensure_public_file(name, data)
        # Errors identify the candidate path/type, never its saved contents.
        self.assertNotIn("synthetic-private-note", str(caught.exception))

    def test_renamed_library_archive_and_sync_json_are_rejected(self):
        for format_name in ("com.pearls.library", "com.pearls.archive", "com.pearls.sync", "com.pearls.sync.version"):
            with self.subTest(format=format_name):
                data = json.dumps({"format": format_name, "schemaVersion": 1, "items": [], "text": "synthetic-private-note"}).encode()
                self.reject("unrelated-name.txt", data)

    def test_utf16_private_document_and_individual_record_are_rejected(self):
        self.reject("report.txt", json.dumps({"format": "com.pearls.library"}).encode("utf-16"))
        self.reject("report.json", json.dumps({"id": "synthetic", "kind": "note", "title": "note", "text": "synthetic-private-note"}).encode())

    def test_malformed_renamed_json_retains_private_header_detection(self):
        truncated = '{"format":"com.pearls.library","items":[{"text":"synthetic-private-note'
        for encoding in ("utf-8", "utf-8-sig", "utf-16", "utf-16-le", "utf-32", "utf-32-be"):
            with self.subTest(encoding=encoding):
                self.reject("innocent-name.dat", truncated.encode(encoding))
        self.reject("wrong-name.txt", b'{"format": "com.pearls.sync.version", bad JSON after the header')
        self.reject("broken.txt", b'{"format": "com.pearls.library\nmissing quote and remaining object')

    def test_source_containing_private_format_examples_is_not_json_data(self):
        ensure_public_file("Example.swift", b'import Foundation\nlet example = #"{"format":"com.pearls.library"}"#')
        ensure_public_file("test_example.py", b'ARCHIVE = {"format": "com.pearls.archive", "items": []}')
        ensure_public_file("example.txt", b'A document about the {"format":"com.pearls.sync"} marker.')

    def test_reserved_private_paths_block_even_truncated_data(self):
        for name in ("library.json", "copy/library.previous.json", "Recovery/library-damaged-test.json",
                     "snapshot.pearlsarchive", "snapshot.pearls", "elsewhere/capture.json",
                     "cloud/pearls-sync.json", "DataBackups/readme.txt", "Pearls Data/arbitrary.bin",
                     "attachments/123/photo.png", "originals/abc/document.pdf", "SharedInbox/123/item.txt",
                     "versions/00000000-0000-0000-0000-000000000001/abc.json",
                     ".pearls-release.local.json", "Configuration/Local.xcconfig"):
            with self.subTest(name=name):
                self.reject(name, b"synthetic-private-note")

    def test_regular_code_artwork_and_fonts_are_allowed(self):
        for name, data in (
            ("Pearls/Resources/Assets.xcassets/PearlsMark.imageset/pearls.png", b"\x89PNG\r\nsynthetic artwork"),
            ("Pearls/Resources/Fonts/PPNeueMontreal-Regular.ttf", b"\x00\x01\x00\x00synthetic font"),
            ("Pearls/Resources/Fonts/PPNeueYork-NormalLight.otf", b"OTTOsynthetic font"),
            ("Packages/PearlsCore/Sources/PearlsCore/PearlDocuments.swift", b'let format = "com.pearls.library"'),
            ("docs/versions/v1.md", b"Public API history"),
            ("release-manifest.json", json.dumps({"version": "0.1.0", "build": "4", "personal_library_included": False}).encode()),
        ):
            with self.subTest(name=name):
                ensure_public_file(name, data)

    def test_key_material_is_blocked_even_when_renamed(self):
        marker = b"-----BEGIN " + b"PRIVATE KEY-----"
        self.reject("accidental.txt", marker + b"\nsynthetic-not-a-real-key\n")
        self.reject("signing.p8", b"synthetic-not-a-real-key")

    def test_renamed_zip_backup_is_scanned_without_extraction(self):
        container = BytesIO()
        with zipfile.ZipFile(container, "w") as archive:
            archive.writestr("renamed.txt", json.dumps({"format": "com.pearls.archive", "items": []}))
        self.reject("download.bin", container.getvalue())

    def test_nested_originals_tree_and_broken_zip_are_rejected(self):
        inner = BytesIO()
        with zipfile.ZipFile(inner, "w") as archive:
            archive.writestr("originals/synthetic/photo.png", b"synthetic-private-note")
        outer = BytesIO()
        with zipfile.ZipFile(outer, "w") as archive:
            archive.writestr("backup.zip", inner.getvalue())
        self.reject("nested.zip", outer.getvalue())
        self.reject("broken.zip", b"PK\x03\x04truncated")

    def test_release_resources_zip_is_allowed(self):
        container = BytesIO()
        with zipfile.ZipFile(container, "w") as archive:
            archive.writestr("Payload/Pearls.app/PPNeueMontreal-Regular.ttf", b"\x00\x01font")
            archive.writestr("Payload/Pearls.app/Pearls", b"synthetic executable")
        ensure_public_file("Pearls.ipa", container.getvalue())


if __name__ == "__main__":
    unittest.main()
