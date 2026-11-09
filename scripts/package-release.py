#!/usr/bin/env python3
"""Capture clean build provenance and retain verified release files for GitHub.

This tool never uploads, exports signing keys, or reads the personal app library.
Only the named IPA and the two application products/dSYMs enter the package.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import shutil
import stat
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = "https://github.com/briggskellogg/pearls"
PROVENANCE = "ReleaseSource.json"
PRODUCTS = [("Pearls.app", "Pearls"), ("PearlsShare.appex", "PearlsShare")]
PRIVATE_SUFFIXES = {".p8", ".p12", ".key", ".pem", ".keychain", ".keychain-db"}
SYMBOL_NAME = re.compile(r"([A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12})\.symbols")


class ReleaseError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise ReleaseError(message)


def command(*args):
    result = subprocess.run(args, capture_output=True, text=True)
    require(result.returncode == 0, result.stderr.strip() or "Command failed: " + args[0])
    return result.stdout.strip()


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for data in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(data)
    return value.hexdigest()


def now():
    return datetime.now(timezone.utc).isoformat()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def clean_source(root=ROOT):
    require(not command("git", "-C", str(root), "status", "--porcelain", "--untracked-files=all"),
            "Commit all source changes before preparing a release.")
    return {"repository": REPOSITORY,
            "commit": command("git", "-C", str(root), "rev-parse", "HEAD"),
            "tree": command("git", "-C", str(root), "rev-parse", "HEAD^{tree}"), "clean": True}


def check_source(record, root=ROOT):
    require(record.get("source") == clean_source(root), "Source changed after build preparation began.")


def validate_recorded_source(record, root=ROOT):
    source = record.get("source", {})
    require(source.get("repository") == REPOSITORY and source.get("clean") is True, "Invalid recorded build source.")
    for field in ("commit", "tree"):
        require(re.fullmatch(r"[a-f0-9]{40}", source.get(field, "")), "Invalid recorded source " + field)
    commit = source["commit"]
    require(command("git", "-C", str(root), "cat-file", "-t", commit) == "commit", "Recorded source is not a commit.")
    require(command("git", "-C", str(root), "rev-parse", commit + "^{tree}") == source["tree"], "Recorded commit/tree do not match.")
    return source


def safe_relative(name):
    path = PurePosixPath(name)
    require(name and not path.is_absolute() and ".." not in path.parts and "\\" not in name,
            "Unsafe artifact path: " + name)
    require(path.suffix.lower() not in PRIVATE_SUFFIXES, "Signing material cannot enter a release package: " + name)
    return path


def regular_files(directory):
    require(directory.is_dir() and not directory.is_symlink(), "Expected a real artifact directory.")
    files = []
    for path in sorted(directory.rglob("*")):
        require(not path.is_symlink(), "Symlinks cannot enter a release package: " + str(path))
        require(path.is_file() or path.is_dir(), "Non-regular artifact entry: " + str(path))
        if path.is_file():
            safe_relative(path.relative_to(directory).as_posix())
            files.append(path)
    return files


def archive_files(archive):
    files = regular_files(archive)
    allowed_prefixes = ("Products/Applications/Pearls.app/", "dSYMs/Pearls.app.dSYM/", "dSYMs/PearlsShare.appex.dSYM/")
    result = {}
    for path in files:
        name = path.relative_to(archive).as_posix()
        require(name in ("Info.plist", PROVENANCE) or name.startswith(allowed_prefixes),
                "Unrelated file in archive: " + name)
        if name != PROVENANCE:
            result[name] = digest(path)
    require("Info.plist" in result, "Archive Info.plist is missing.")
    for prefix in allowed_prefixes:
        require(any(name.startswith(prefix) for name in result), "Missing archive product: " + prefix)
    return result


def inspect_ipa(ipa, destination):
    require(ipa.is_file() and not ipa.is_symlink(), "Expected a regular IPA file.")
    with zipfile.ZipFile(ipa) as zipped:
        seen = set()
        for entry in zipped.infolist():
            safe_relative(entry.filename)
            require(entry.filename not in seen, "Duplicate IPA entry: " + entry.filename)
            seen.add(entry.filename)
            require(not stat.S_ISLNK(entry.external_attr >> 16), "IPA contains a symlink.")
            symbol = entry.filename.startswith("Symbols/") and SYMBOL_NAME.fullmatch(entry.filename.removeprefix("Symbols/"))
            require(entry.filename in ("Payload/", "Payload/Pearls.app/", "Symbols/") or entry.filename.startswith("Payload/Pearls.app/") or symbol,
                    "Unrelated file in IPA: " + entry.filename)
        zipped.extractall(destination)
    return destination / "Payload/Pearls.app"


def bundle_info(app):
    info = plistlib.loads((app / "Info.plist").read_bytes())
    require(info.get("CFBundleIdentifier") == "com.briggskellogg.pearls", "Unexpected release bundle.")
    require(re.fullmatch(r"[0-9]+(?:\.[0-9]+){1,2}", info.get("CFBundleShortVersionString", "")), "Invalid release version.")
    require(re.fullmatch(r"[1-9][0-9]*", info.get("CFBundleVersion", "")), "Invalid release build.")
    return info


def uuids(path):
    output = command("xcrun", "dwarfdump", "--uuid", str(path))
    values = sorted({(match[0].upper(), match[1]) for match in re.findall(r"UUID: ([A-Fa-f0-9-]+) \(([^)]+)\)", output)})
    require(values, "Missing executable or dSYM UUID: " + str(path))
    return values


def match_symbols(archive, exported_app):
    archived_app = archive / "Products/Applications/Pearls.app"
    result = []
    for product, executable in PRODUCTS:
        relative = Path() if product == "Pearls.app" else Path("PlugIns") / product
        archive_values = uuids(archived_app / relative / executable)
        exported_values = uuids(exported_app / relative / executable)
        symbol_values = uuids(archive / "dSYMs" / (product + ".dSYM") / "Contents/Resources/DWARF" / executable)
        require(archive_values == exported_values == symbol_values, "Archive, IPA, and dSYM UUIDs differ for " + product)
        result.append({"product": product, "uuids": [{"uuid": value, "architecture": arch} for value, arch in archive_values]})
    symbol_directory = exported_app.parent.parent / "Symbols"
    validate_symbol_files(symbol_directory, {value["uuid"] for product in result for value in product["uuids"]})
    return result


def validate_symbol_files(directory, allowed_uuids):
    if not directory.exists():
        return
    seen = set()
    for path in regular_files(directory):
        match = SYMBOL_NAME.fullmatch(path.name)
        require(path.parent == directory and match, "Unexpected IPA Symbols entry: " + path.name)
        value = match[1].upper()
        require(value in allowed_uuids and value not in seen, "IPA symbol UUID does not match its products: " + value)
        seen.add(value)


def zip_files(output, root, files, prefix=""):
    with zipfile.ZipFile(output, "x", compression=zipfile.ZIP_DEFLATED) as zipped:
        for path in files:
            name = prefix + path.relative_to(root).as_posix()
            safe_relative(name)
            zipped.write(path, name)


def capture(args):
    require(not args.output.exists() and not args.output.is_symlink(), "Source record already exists.")
    require(re.fullmatch(r"[1-9][0-9]*", args.build_number), "Invalid build number.")
    record = {"schema": 1, "state": "captured", "source": clean_source(), "build": args.build_number,
              "started_at": now(), "xcode": command("xcodebuild", "-version")}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    write_json(args.output, record)


def finish(args):
    record = json.loads(args.record.read_text())
    require(record.get("schema") == 1 and record.get("state") == "captured", "Invalid initial source record.")
    check_source(record)
    ipa = args.export / "Pearls.ipa"
    info = bundle_info(args.archive / "Products/Applications/Pearls.app")
    require(info["CFBundleVersion"] == record["build"], "Archive build does not match captured source record.")
    record.update({"state": "complete", "finished_at": now(), "version": info["CFBundleShortVersionString"],
                   "ipa_sha256": digest(ipa), "archive_files": archive_files(args.archive)})
    check_source(record)
    for destination in (args.archive / PROVENANCE, args.export / PROVENANCE):
        require(not destination.exists() and not destination.is_symlink(), "Completed source record already exists.")
    write_json(args.archive / PROVENANCE, record)
    write_json(args.export / PROVENANCE, record)
    print("Recorded clean source commit " + record["source"]["commit"] + " for build " + record["build"])


def package(args):
    require(not args.output.exists() and not args.output.is_symlink(), "Release package already exists; it was not replaced.")
    record = json.loads((args.archive / PROVENANCE).read_text())
    require(record.get("schema") == 1 and record.get("state") == "complete", "Archive has no completed build provenance.")
    validate_recorded_source(record)
    packaging_source = clean_source()
    require(archive_files(args.archive) == record["archive_files"], "Archive changed after its source record was completed.")
    ipa = args.export / "Pearls.ipa"
    require(digest(ipa) == record["ipa_sha256"], "IPA changed after its source record was completed.")
    environment = dict(os.environ, TEAM_ID=args.team_id, BUILD_NUMBER=record["build"])
    subprocess.run(["bash", str(ROOT / "scripts/verify-testflight.sh"), str(ipa)], check=True, env=environment)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="pearls-release-", dir=args.output.parent) as temporary:
        staging = Path(temporary)
        extracted = staging / "verify"
        app = inspect_ipa(ipa, extracted)
        info = bundle_info(app)
        require(info["CFBundleVersion"] == record["build"] and info["CFBundleShortVersionString"] == record["version"],
                "Export version/build does not match source record.")
        symbols = match_symbols(args.archive, app)
        retained = staging / "retained"
        retained.mkdir()
        stem = "Pearls-" + record["version"] + "-build-" + record["build"]
        shutil.copyfile(ipa, retained / (stem + ".ipa"))
        zip_files(retained / (stem + "-dSYMs.zip"), args.archive / "dSYMs", regular_files(args.archive / "dSYMs"))
        zip_files(retained / (stem + ".xcarchive.zip"), args.archive, regular_files(args.archive), prefix=stem + ".xcarchive/")
        artifacts = [{"file": path.name, "bytes": path.stat().st_size, "sha256": digest(path)} for path in sorted(retained.iterdir())]
        manifest = {"schema": 1, "repository": REPOSITORY, "source": record["source"], "packaging_source": packaging_source, "version": record["version"],
                    "build": record["build"], "bundle_id": info["CFBundleIdentifier"], "team_id": args.team_id,
                    "app_group": info["PearlsAppGroup"], "xcode": record["xcode"], "packaged_at": now(),
                    "binaries": symbols, "artifacts": artifacts,
                    "distribution": "App Store export; installation is through TestFlight, not direct Windows execution",
                    "signing_keys_included": False, "personal_library_included": False}
        write_json(retained / "release-manifest.json", manifest)
        checksum_lines = [digest(path) + "  " + path.name for path in sorted(retained.iterdir())]
        (retained / "SHA256SUMS").write_text("\n".join(checksum_lines) + "\n")
        require(packaging_source == clean_source(), "Packaging source changed while retaining artifacts.")
        retained.rename(args.output)
    print("Release artifacts retained at " + str(args.output))
    print("Source commit: " + record["source"]["commit"] + "; no upload or Proton backup performed.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="action", required=True)
    operation = commands.add_parser("capture")
    operation.add_argument("--output", type=Path, required=True)
    operation.add_argument("--build-number", required=True)
    operation.set_defaults(run=capture)
    operation = commands.add_parser("finish")
    operation.add_argument("--record", type=Path, required=True)
    operation.add_argument("--archive", type=Path, required=True)
    operation.add_argument("--export", type=Path, required=True)
    operation.set_defaults(run=finish)
    operation = commands.add_parser("package")
    operation.add_argument("--archive", type=Path, required=True)
    operation.add_argument("--export", type=Path, required=True)
    operation.add_argument("--output", type=Path, required=True)
    operation.add_argument("--team-id", required=True)
    operation.set_defaults(run=package)
    args = parser.parse_args()
    if hasattr(args, "team_id"):
        require(re.fullmatch(r"[A-Z0-9]{10}", args.team_id), "Invalid Apple team identifier.")
    args.run(args)


if __name__ == "__main__":
    try:
        main()
    except (ReleaseError, OSError, ValueError, KeyError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        raise SystemExit("Pearls release: " + str(error))
