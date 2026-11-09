#!/usr/bin/env python3
"""Publish committed Pearls source to GitHub and its local Proton Drive folder.

This copies project source, not the app's library. Proton's own client performs
the cloud upload; a matching local folder is not proof of remote upload.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import subprocess
import sys
import tempfile
from datetime import datetime, timezone

# Script execution and importlib-based safety tests share this sibling module.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from private_data_guard import PrivateDataError, ensure_public_file, ensure_public_tree

REPOSITORY = "briggskellogg/pearls"
RECEIPT = ".pearls-project-sync.json"
ALLOWED_ORIGINS = {
    "https://github.com/briggskellogg/pearls",
    "https://github.com/briggskellogg/pearls.git",
    "git@github.com:briggskellogg/pearls.git",
    "ssh://git@github.com/briggskellogg/pearls.git",
}


class SyncError(Exception):
    pass


def git(root, *args):
    result = subprocess.run(["git", "-C", str(root), *args], capture_output=True)
    if result.returncode:
        raise SyncError(result.stderr.decode(errors="replace").strip() or "Git command failed")
    return result.stdout


def safe_relative(name):
    path = PurePosixPath(name)
    if not name or path.is_absolute() or str(path) != name or any(
        part in (".", "..", ".git") for part in path.parts
    ):
        raise SyncError(f"Unsafe project path: {name!r}")
    return path


def safe_path(path):
    """Do not traverse any existing symlink, including a destination ancestor."""
    path = Path(os.path.abspath(path))
    for part in reversed((path, *path.parents)):
        if part.is_symlink():
            raise SyncError(f"Symlink not allowed in sync path: {part}")
        if part != path and part.exists() and not part.is_dir():
            raise SyncError(f"Sync parent is not a directory: {part}")
    return path


def fingerprint(data, executable=False):
    return {"sha256": hashlib.sha256(data).hexdigest(), "executable": executable}


def current_file(path):
    safe_path(path)
    if not path.exists():
        return None
    if not path.is_file():
        raise SyncError(f"Expected a regular file: {path}")
    return fingerprint(path.read_bytes(), bool(path.stat().st_mode & 0o111))


def snapshot(root):
    if git(root, "branch", "--show-current").decode().strip() != "main":
        raise SyncError("Switch to main before syncing.")
    if git(root, "status", "--porcelain", "--untracked-files=no").strip():
        raise SyncError("Commit tracked source changes before syncing.")
    for options in [("--all",), ("--push", "--all")]:
        urls = git(root, "remote", "get-url", *options, "origin").decode().splitlines()
        if len(urls) != 1 or urls[0] not in ALLOWED_ORIGINS:
            raise SyncError(f"origin must point only to {REPOSITORY} on GitHub.")
    commit = git(root, "rev-parse", "HEAD").decode().strip()
    files = {}
    for entry in git(root, "ls-tree", "-rz", "--full-tree", commit).split(b"\0"):
        if not entry:
            continue
        metadata, raw_name = entry.split(b"\t", 1)
        mode, kind, blob = metadata.decode().split()
        name = raw_name.decode("utf-8")
        path = safe_relative(name)
        if mode not in ("100644", "100755") or kind != "blob":
            raise SyncError(f"Only regular source files may be mirrored: {name}")
        if (name in (RECEIPT, ".pearls-sync.local.json", "Configuration/Local.xcconfig")
                or any(p in (".build", "build", "DerivedData", "xcuserdata") for p in path.parts)
                or path.suffix.lower() in (".p8", ".p12", ".mobileprovision", ".provisionprofile", ".ipa")
                or any(p.endswith(".xcarchive") for p in path.parts)):
            raise SyncError(f"Remove private configuration or build output from Git: {name}")
        data = git(root, "cat-file", "blob", blob)
        try:
            ensure_public_file(name, data)
        except PrivateDataError as error:
            raise SyncError(str(error)) from error
        files[name] = (data, mode == "100755")
    return commit, files


def validate_public_history(root, commit):
    """A removed private file still leaks when its earlier commit is pushed."""
    checked = set()
    for revision in git(root, "rev-list", commit).decode().splitlines():
        for entry in git(root, "ls-tree", "-rz", "--full-tree", revision).split(b"\0"):
            if not entry:
                continue
            metadata, raw_name = entry.split(b"\t", 1)
            mode, kind, blob = metadata.decode().split()
            name = raw_name.decode("utf-8")
            if kind != "blob" or (name, blob) in checked:
                continue
            checked.add((name, blob))
            try:
                ensure_public_file(name, git(root, "cat-file", "blob", blob))
            except PrivateDataError as error:
                raise SyncError(f"{error}; reachable Git history must be reconciled before publication.") from error


def read_receipt(destination):
    path = safe_path(destination / RECEIPT)
    if not path.exists():
        return None
    try:
        receipt = json.loads(path.read_text())
        if receipt["schema"] != 1 or receipt["repository"] != REPOSITORY:
            raise ValueError("different schema or repository")
        if not isinstance(receipt["files"], dict):
            raise ValueError("invalid file manifest")
        for name, value in receipt["files"].items():
            safe_relative(name)
            if name == RECEIPT or set(value) != {"sha256", "executable"}:
                raise ValueError("invalid file fingerprint")
            if (not isinstance(value["sha256"], str) or len(value["sha256"]) != 64
                    or any(c not in "0123456789abcdef" for c in value["sha256"])
                    or type(value["executable"]) is not bool):
                raise ValueError("invalid file fingerprint")
        return receipt
    except (ValueError, KeyError, TypeError, AttributeError) as error:
        raise SyncError(f"Invalid sync receipt at {path}: {error}") from error


def preflight(destination, files):
    try:
        ensure_public_tree(files)
    except PrivateDataError as error:
        raise SyncError(str(error)) from error
    destination = safe_path(destination)
    if destination.exists() and not destination.is_dir():
        raise SyncError("Destination must be a directory.")
    previous = read_receipt(destination)
    old = previous["files"] if previous else {}
    expected = {name: fingerprint(*value) for name, value in files.items()}
    writes, removals, conflicts = [], [], []
    for name in sorted(set(old) | set(expected)):
        actual = current_file(destination / name)
        wanted = expected.get(name)
        # Already-current files are safe, including an interrupted prior copy.
        if actual == wanted:
            continue
        if name in old:
            if actual != old[name]:
                conflicts.append(name)
                continue
        elif actual is not None:
            conflicts.append(name)
            continue
        if wanted is None:
            removals.append(name)
        else:
            writes.append(name)
    if conflicts:
        raise SyncError("Destination edits need reconciliation; nothing was published:\n  " + "\n  ".join(conflicts))
    return previous, expected, writes, removals


def atomic_write(path, data, executable=False):
    safe_path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=".pearls-sync-", dir=path.parent)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
            os.fchmod(stream.fileno(), 0o755 if executable else 0o644)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def mirror(destination, commit, files, local_receipt):
    previous, expected, writes, removals = preflight(destination, files)
    old = previous["files"] if previous else {}
    destination.mkdir(parents=True, exist_ok=True)
    for name in writes:
        if current_file(destination / name) not in (old.get(name), expected[name]):
            raise SyncError(f"Destination changed during sync: {name}")
        atomic_write(destination / name, *files[name])
    for name in removals:
        if current_file(destination / name) != old[name]:
            raise SyncError(f"Destination changed during sync: {name}")
        (destination / name).unlink()
    # Verify every published byte and permission before recording success.
    for name, wanted in expected.items():
        if current_file(destination / name) != wanted:
            raise SyncError(f"Verification failed after copying {name}.")
    receipt = {
        "schema": 1, "repository": REPOSITORY, "commit": commit,
        "verified_at": datetime.now(timezone.utc).isoformat(), "files": expected,
    }
    encoded = (json.dumps(receipt, indent=2, sort_keys=True) + "\n").encode()
    atomic_write(destination / RECEIPT, encoded)
    atomic_write(local_receipt, encoded)
    return len(writes), len(removals)


def remote_commit(root):
    result = git(root, "ls-remote", "--heads", "origin", "refs/heads/main").decode().strip()
    return result.split()[0] if result else None


def unchanged_checkout(root, commit):
    if (git(root, "rev-parse", "HEAD").decode().strip() != commit
            or git(root, "branch", "--show-current").decode().strip() != "main"
            or git(root, "status", "--porcelain", "--untracked-files=no").strip()):
        raise SyncError("The local checkout changed during sync; reconcile it and rerun.")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--destination", type=Path, help="Proton project folder (or use .pearls-sync.local.json)")
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--check", action="store_true", help="Check without changing GitHub or the mirror (default)")
    modes.add_argument("--push", action="store_true", help="Push current main, verify GitHub, then update the mirror")
    modes.add_argument("--sync", action="store_true", help="Update the mirror only if GitHub already matches")
    modes.add_argument("--mirror-only", action="store_true", help="Update only the local mirror; do not contact or verify GitHub")
    args = parser.parse_args(argv)
    root = Path(__file__).resolve().parents[1]
    destination = args.destination
    if destination is None:
        config = root / ".pearls-sync.local.json"
        try:
            destination = Path(json.loads(config.read_text())["destination"]).expanduser()
        except (OSError, ValueError, KeyError, TypeError) as error:
            raise SyncError("Provide --destination or set destination in .pearls-sync.local.json.") from error
    destination = safe_path(destination.expanduser())
    if destination == root or root in destination.parents or destination in root.parents:
        raise SyncError("The destination and Git checkout must be separate folders.")
    commit, files = snapshot(root)
    validate_public_history(root, commit)
    previous, expected, writes, removals = preflight(destination, files)
    if args.mirror_only:
        unchanged_checkout(root, commit)
        local_receipt = Path(git(root, "rev-parse", "--absolute-git-dir").decode().strip()) / RECEIPT
        copied, removed = mirror(destination, commit, files, local_receipt)
        unchanged_checkout(root, commit)
        print(f"Local mirror only: {commit} — {len(files)} verified source files; {copied} updated, {removed} removed.")
        print(f"Proton folder: {destination}")
        print("GitHub was not contacted or verified. This does not establish GitHub synchronization.")
        print("Proton cloud upload is managed separately by the Proton Drive app.")
        return 0
    remote = remote_commit(root)
    is_current = (remote == commit and previous is not None and previous.get("commit") == commit
                  and previous["files"] == expected and not writes and not removals)
    if not args.push and not args.sync:
        unchanged_checkout(root, commit)
        if is_current:
            print(f"Synced: {commit} — {len(files)} source files match GitHub and {destination}")
            print("Proton cloud upload is managed separately by the Proton Drive app.")
            return 0
        print(f"Pending: local {commit}; GitHub {remote or '(empty)'}; mirror {len(writes)} writes, {len(removals)} removals.")
        return 1
    unchanged_checkout(root, commit)
    if args.push and remote != commit:
        git(root, "push", "origin", f"{commit}:refs/heads/main")
    if remote_commit(root) != commit:
        raise SyncError("GitHub main differs from the local commit. Reconcile it before mirroring.")
    # Recheck immediately before writing: push and network access take time.
    unchanged_checkout(root, commit)
    local_receipt = Path(git(root, "rev-parse", "--absolute-git-dir").decode().strip()) / RECEIPT
    copied, removed = mirror(destination, commit, files, local_receipt)
    if remote_commit(root) != commit:
        raise SyncError("The mirror was written, but GitHub advanced during sync. Reconcile and rerun.")
    unchanged_checkout(root, commit)
    print(f"Synced: {commit} — {len(files)} verified source files; {copied} updated, {removed} removed.")
    print(f"Proton folder: {destination}")
    print("Proton cloud upload is managed separately by the Proton Drive app.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (SyncError, OSError, UnicodeError) as error:
        print(f"Pearls sync: {error}", file=sys.stderr)
        sys.exit(2)
