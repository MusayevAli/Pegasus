#!/usr/bin/env python3
"""Package source and an existing successful simulator build using only Python stdlib."""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import stat
import tempfile
import zipfile

EXCLUDED_DIRS = {
    "work", "node_modules", ".build", ".swiftpm", "dist", "data", "cache", ".cache",
    "xcuserdata", ".git", ".svn", "__pycache__", ".pytest_cache", "coverage", ".DS_Store",
}
EXCLUDED_SUFFIXES = {
    ".db", ".sqlite", ".sqlite3", ".db-wal", ".db-shm", ".sqlite-wal", ".sqlite-shm",
    ".sqlite3-wal", ".sqlite3-shm", ".pem", ".key", ".p8", ".p12", ".pfx", ".cer",
    ".crt", ".der", ".mobileprovision", ".provisionprofile", ".zip", ".pyc", ".tsbuildinfo",
}
EXCLUDED_NAMES = {".ds_store", ".envrc", "id_rsa", "id_ed25519", "id_ecdsa", "credentials", "credentials.json"}
# Construct prefixes in parts so this audit's own source is not a false positive.
CREDENTIAL_PATTERNS = (
    re.compile(rb"\bs" + rb"k-(?:proj-|svcacct-)?[A-Za-z0-9_-]{20,}\b"),
    re.compile(rb"\b(?:ghp|gho|ghu|ghs|github_pat)_[A-Za-z0-9_]{20,}\b"),
    re.compile(rb"\bAKIA[0-9A-Z]{16}\b"),
    re.compile(rb"-----BEGIN (?:RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----"),
)

INSTALL_README = """Pegasus TripFit — iOS Simulator build

This .app is for an iOS Simulator on a compatible Mac. It is not an IPA,
physical-iPhone installation or App Store release. Built with Xcode 26.3 for
arm64 and x86_64 simulators; verified on iPhone 17 Pro / iOS 26.2. Rebuild
from the companion source archive if your host/runtime is incompatible.

1. Extract this ZIP, preserving its PegasusTripFit.app folder and permissions.
2. Start the backend from the companion source archive (Node 22.13+):
     cd PegasusTripFit/backend
     npm ci
     cp .env.example .env   # only if .env does not already exist
     npm start
3. Open Xcode > Open Developer Tool > Simulator and boot an iPhone.
4. From the folder containing PegasusTripFit.app:
     DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl install booted PegasusTripFit.app
     DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl launch booted com.hackathon.PegasusTripFit
5. In the app's top-right profile menu > App settings > Developer diagnostics, use
   http://127.0.0.1:3001 as the backend URL (or your configured server URL).

The current booking flow requires the backend for search, prices and checkout.
AI additionally needs a server-side OpenAI key. No credentials are in this ZIP.
Without AI, use manual fields. Live Pegasus mode returns official flight search
results and an official booking continuation. Demo booking mode uses separate
sample prices and simulated checkout: no payment is taken and no ticket is issued.
Travel memory is optional and has its own collection/export/delete controls.
For setup, dashboard, physical-device builds and integration limits, read the
companion source archive's README.md. Do not put API keys into the app bundle.
"""


def excluded(relative: Path) -> bool:
    if any(part.lower() in {name.lower() for name in EXCLUDED_DIRS} for part in relative.parts):
        return True
    name = relative.name.lower()
    if name in EXCLUDED_NAMES:
        return True
    if name == ".env" or (name.startswith(".env.") and name != ".env.example"):
        return True
    return any(name.endswith(suffix) for suffix in EXCLUDED_SUFFIXES)


def entries(root: Path, filter_source: bool):
    for directory, dirs, files in os.walk(root, followlinks=False):
        dirs.sort()
        files.sort()
        parent = Path(directory)
        for name in list(dirs):
            path = parent / name
            relative = path.relative_to(root)
            if filter_source and excluded(relative):
                dirs.remove(name)
                continue
            yield path, relative
            if path.is_symlink():
                dirs.remove(name)
        for name in files:
            path = parent / name
            relative = path.relative_to(root)
            if not filter_source or not excluded(relative):
                yield path, relative


def scan_credentials(payload: bytes, label: str):
    if any(pattern.search(payload) for pattern in CREDENTIAL_PATTERNS):
        # Never print the matched content, even on failure.
        raise ValueError("Credential-like content detected in " + label)


def zip_info(name: str, metadata: os.stat_result) -> zipfile.ZipInfo:
    date = dt.datetime.fromtimestamp(metadata.st_mtime)
    if not 1980 <= date.year <= 2107:
        date = dt.datetime(1980, 1, 1)
    info = zipfile.ZipInfo(name, date.timetuple()[:6])
    info.create_system = 3
    info.external_attr = (metadata.st_mode & 0xFFFF) << 16
    info.compress_type = zipfile.ZIP_DEFLATED
    if stat.S_ISDIR(metadata.st_mode):
        info.external_attr |= 0x10
    return info


def add_path(archive: zipfile.ZipFile, path: Path, relative: Path, root: Path, prefix: str):
    metadata = path.lstat()
    name = prefix + "/" + relative.as_posix() if relative.parts else prefix
    if stat.S_ISDIR(metadata.st_mode):
        archive.writestr(zip_info(name.rstrip("/") + "/", metadata), b"")
    elif stat.S_ISLNK(metadata.st_mode):
        target = os.readlink(path)
        try:
            (path.parent / target).resolve().relative_to(root.resolve())
        except ValueError:
            raise ValueError("Refusing a link outside the package root: " + name) from None
        payload = target.encode("utf-8")
        scan_credentials(payload, name)
        archive.writestr(zip_info(name, metadata), payload)
    elif stat.S_ISREG(metadata.st_mode):
        payload = path.read_bytes()
        scan_credentials(payload, name)
        archive.writestr(zip_info(name, metadata), payload)
    else:
        raise ValueError("Unsupported special file: " + name)


def verify(archive_path: Path, source: bool, executable: str | None = None) -> dict:
    count = 0
    total = 0
    with zipfile.ZipFile(archive_path) as archive:
        if archive.testzip() is not None:
            raise ValueError("ZIP integrity check failed")
        for item in archive.infolist():
            name = Path(item.filename)
            if name.is_absolute() or ".." in name.parts:
                raise ValueError("Unsafe archive path")
            if source and excluded(Path(*name.parts[1:])):
                raise ValueError("Excluded source path reached the archive: " + item.filename)
            payload = archive.read(item)
            scan_credentials(payload, item.filename)
            if not item.is_dir():
                count += 1
                total += item.file_size
        if executable:
            info = archive.getinfo(executable)
            if not (info.external_attr >> 16) & 0o111:
                raise ValueError("App executable permission was not preserved")
    return {"files": count, "uncompressedBytes": total, "archiveBytes": archive_path.stat().st_size,
            "sha256": hashlib.sha256(archive_path.read_bytes()).hexdigest(),
            "credentialScan": "passed", "zipIntegrity": "passed", "unixPermissions": "preserved"}


def build_archive(root: Path, output: Path, source: bool, executable: str | None = None) -> dict:
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(prefix=output.stem + "-", suffix=".tmp", dir=output.parent, delete=False) as file:
            temporary = Path(file.name)
        with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            add_path(archive, root, Path(), root, root.name)
            for path, relative in entries(root, source):
                add_path(archive, path, relative, root, root.name)
            if not source:
                info = zipfile.ZipInfo("README-Install.txt")
                info.create_system = 3
                info.external_attr = (stat.S_IFREG | 0o644) << 16
                info.compress_type = zipfile.ZIP_DEFLATED
                archive.writestr(info, INSTALL_README.encode("utf-8"))
        report = verify(temporary, source, executable)
        os.replace(temporary, output)
        report["archive"] = output.name
        return report
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    project = args.project.resolve()
    app = project / "work/DerivedData/Build/Products/Debug-iphonesimulator/PegasusTripFit.app"
    build_log = project / "work/ios-v2-build.log"
    if not app.is_dir() or not build_log.is_file() or "** BUILD SUCCEEDED **" not in build_log.read_text(errors="replace")[-8192:]:
        raise ValueError("A successful existing simulator build is required before packaging")
    with (app / "Info.plist").open("rb") as file:
        info = plistlib.load(file)
    if "iPhoneSimulator" not in info.get("CFBundleSupportedPlatforms", []):
        raise ValueError("Refusing to label a non-simulator app as a simulator build")
    executable_name = info["CFBundleExecutable"]
    if not (app / executable_name).is_file():
        raise ValueError("App executable is missing")
    binary_date = max(path.stat().st_mtime for path in app.iterdir() if path.is_file())
    for path in (project / "ios").rglob("*.swift"):
        if not excluded(path.relative_to(project)) and path.stat().st_mtime > binary_date:
            raise ValueError("Swift source changed after the simulator build; rebuild before packaging")
    source_report = build_archive(project, project.parent / "PegasusTripFit-Source.zip", True)
    app_report = build_archive(app, project.parent / "PegasusTripFit-iOS-Simulator.zip", False,
                               app.name + "/" + executable_name)
    print(json.dumps({"source": source_report, "simulator": app_report}, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
