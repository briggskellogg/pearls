#!/usr/bin/env python3
"""Reject identifiable private Pearls data from public source/release inputs.

Only bytes explicitly passed by a source/release caller are inspected. This
module never searches app containers, connected libraries, or private folders.
"""
from io import BytesIO
import json
from pathlib import PurePosixPath
import re
import zipfile


class PrivateDataError(Exception):
    pass


PRIVATE_SUFFIXES = {".pearlsarchive", ".pearls", ".p8", ".p12", ".key", ".pem", ".keychain", ".keychain-db"}
PRIVATE_DIRECTORIES = {
    "attachments", "originals", "sharedinbox", "pearlsdata", "pearlslibrary",
    "privatedata", "privatelibrary", "personallibrary", "databackups",
}
PRIVATE_BASENAMES = {"library.json", "library.previous.json", "capture.json", "pearls-sync.json"}
UUID_COMPONENT = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")
PEM_PRIVATE_KEY = re.compile(rb"(?m)^-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED )?PRIVATE KEY-----\r?$")
PRIVATE_JSON_HEADER = re.compile(r'(?<!\\)"format"\s*:\s*"com\.pearls\.(?:library|archive|sync)')
MAX_ZIP_BYTES = 512 * 1024 * 1024
MAX_ZIP_FILES = 20_000
MAX_ZIP_DEPTH = 3


def private_path_reason(name):
    path = PurePosixPath(name.replace("\\", "/"))
    parts = tuple(part.casefold() for part in path.parts)
    basename = parts[-1] if parts else ""
    normalized = {re.sub(r"[ _-]", "", part) for part in parts[:-1]}
    if path.is_absolute() or ".." in parts:
        return "unsafe input path"
    if path.suffix.casefold() in PRIVATE_SUFFIXES:
        return "private archive or signing material"
    if PRIVATE_DIRECTORIES & normalized:
        return "private library, original-attachment, or backup tree"
    if any(part == "versions" and index + 1 < len(parts) and UUID_COMPONENT.fullmatch(parts[index + 1])
           for index, part in enumerate(parts)):
        return "private synchronized record-version tree"
    if basename in PRIVATE_BASENAMES or (basename.startswith("library-damaged-") and basename.endswith(".json")):
        return "private library or capture document"
    if (basename.startswith(".pearls") and ".local." in basename) or parts[-2:] == ("configuration", "local.xcconfig"):
        return "private local configuration"
    return None


def private_json(value):
    """Recognize actual data objects, not Swift/Python source describing them."""
    pending = [value]
    while pending:
        item = pending.pop()
        if isinstance(item, dict):
            format_name = item.get("format")
            if isinstance(format_name, str) and (
                format_name in {"com.pearls.library", "com.pearls.archive"}
                or format_name.startswith("com.pearls.sync")
            ):
                return True
            if ({"id", "kind", "title", "text"} <= item.keys()
                    and isinstance(item.get("kind"), str)
                    and item["kind"] in {"note", "link", "image", "file"}):
                return True
            relative = item.get("relativePath")
            if isinstance(relative, str) and relative.replace("\\", "/").startswith("attachments/"):
                return True
            pending.extend(item.values())
        elif isinstance(item, list):
            pending.extend(item)
    return False


def json_looking_text(data):
    """Keep a recognizable private header effective after a damaged JSON tail."""
    if data.startswith((b"\xff\xfe\x00\x00", b"\x00\x00\xfe\xff")):
        encoding = "utf-32"
    elif data.startswith((b"\xff\xfe", b"\xfe\xff")):
        encoding = "utf-16"
    elif len(data) >= 4 and data[:3] == b"\x00\x00\x00":
        encoding = "utf-32-be"
    elif len(data) >= 4 and data[1:4] == b"\x00\x00\x00":
        encoding = "utf-32-le"
    elif len(data) >= 2 and data[0] == 0:
        encoding = "utf-16-be"
    elif len(data) >= 2 and data[1] == 0:
        encoding = "utf-16-le"
    else:
        encoding = "utf-8-sig"
    text = data.decode(encoding, errors="replace").lstrip()
    return text if text.startswith(("{", "[")) else None


def ensure_public_file(name, data, *, _depth=0, _budget=None):
    """Raise without printing document contents if candidate bytes are private."""
    reason = private_path_reason(name)
    if reason:
        raise PrivateDataError(f"Public publication blocked: {reason}: {name}")
    if PEM_PRIVATE_KEY.search(data):
        raise PrivateDataError(f"Public publication blocked: private-key content in {name}")
    prefix = data.lstrip()[:4]
    if prefix.startswith((b"{", b"[", b"\xef\xbb\xbf", b"\xff\xfe", b"\xfe\xff", b"\x00")):
        text = json_looking_text(data)
        if text is not None and PRIVATE_JSON_HEADER.search(text):
            raise PrivateDataError(f"Public publication blocked: private Pearls document header in {name}")
        try:
            document = json.loads(data)
        except (ValueError, UnicodeError, RecursionError):
            document = None
        if document is not None and private_json(document):
            raise PrivateDataError(f"Public publication blocked: private Pearls data document in {name}")
    # Detect renamed or nested backups, without extracting them onto disk.
    stream = BytesIO(data)
    is_zip = zipfile.is_zipfile(stream)
    if is_zip or data.startswith((b"PK\x03\x04", b"PK\x05\x06", b"PK\x07\x08")):
        if not is_zip or _depth >= MAX_ZIP_DEPTH:
            raise PrivateDataError(f"Public publication blocked: archive cannot be safely inspected: {name}")
        budget = _budget if _budget is not None else {"bytes": MAX_ZIP_BYTES, "files": MAX_ZIP_FILES}
        try:
            with zipfile.ZipFile(stream) as archive:
                for entry in archive.infolist():
                    budget["files"] -= 1
                    if budget["files"] < 0 or entry.flag_bits & 1:
                        raise PrivateDataError(f"Public publication blocked: encrypted or excessive archive entries in {name}")
                    reason = private_path_reason(entry.filename)
                    if reason:
                        raise PrivateDataError(f"Public publication blocked: {reason} inside {name}")
                    if entry.is_dir():
                        continue
                    if entry.file_size > budget["bytes"]:
                        raise PrivateDataError(f"Public publication blocked: archive inspection size limit reached in {name}")
                    budget["bytes"] -= entry.file_size
                    ensure_public_file(entry.filename, archive.read(entry), _depth=_depth + 1, _budget=budget)
        except (zipfile.BadZipFile, NotImplementedError, RuntimeError) as error:
            raise PrivateDataError(f"Public publication blocked: unreadable archive in {name}") from error


def ensure_public_tree(files):
    """Validate a snapshot mapping paths to (bytes, executable) tuples."""
    for name, value in files.items():
        ensure_public_file(name, value[0])
