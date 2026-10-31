"""Install the verified local artifact alongside official apps, without overwrites."""
import hashlib
import argparse
import json
import os
import pathlib
import plistlib
import subprocess
from datetime import datetime, timezone

root = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--previous-manifest", type=pathlib.Path)
parser.add_argument("--dry-run", action="store_true")
options = parser.parse_args()
record = root / "artifacts/provenance/manifest.json"
manifest = json.loads(record.read_text())
source = pathlib.Path(manifest["artifact"])
destination = pathlib.Path("/Applications/LocalSend Personal.app")
if source != root / "artifacts/LocalSend Personal.app":
    raise SystemExit("Unexpected build artifact path")
if destination.is_symlink():
    raise SystemExit("Refusing a symlink at the installation destination")


def verify(path, expected=manifest):
    files = {
        str(item.relative_to(path)): hashlib.sha256(item.read_bytes()).hexdigest()
        for item in path.rglob("*") if item.is_file() and not item.is_symlink()
    }
    symlinks = {str(item.relative_to(path)): os.readlink(item) for item in path.rglob("*") if item.is_symlink()}
    if files != expected["artifactFiles"] or symlinks != expected["artifactSymlinks"]:
        raise SystemExit(f"Artifact hash or symlink verification failed: {path}")
    with (path / "Contents/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    if info["CFBundleIdentifier"] != "dev.ylagef.localsendPersonal":
        raise SystemExit("Refusing to install an artifact with another app identity")
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(path)], check=True)


verify(source)
backup = None
if destination.exists():
    if options.previous_manifest is None:
        raise SystemExit("Existing installation requires its retained --previous-manifest for a verified upgrade")
    previous = json.loads(options.previous_manifest.read_text())
    verify(destination, previous)
    processes = subprocess.check_output(["ps", "-axo", "pid=,comm="], text=True)
    if any("/Contents/MacOS/LocalSend Personal" in line for line in processes.splitlines()):
        raise SystemExit("Quit LocalSend Personal before upgrading; the installer will not stop a running app")
    backup = options.previous_manifest.resolve().parent.parent / "installed-app-before-upgrade.app"
    if backup.exists() or backup.is_symlink():
        raise SystemExit(f"Preserve the existing upgrade backup first: {backup}")
if options.dry_run:
    print("Preflight passed; artifact, destination identity and previous-build hashes verified; no files changed")
    raise SystemExit(0)
if backup:
    destination.rename(backup)
try:
    subprocess.run(["ditto", str(source), str(destination)], check=True)
    verify(destination)
except BaseException:
    # Preserve the failed candidate and restore the verified original app.
    if destination.exists():
        failed = record.parent / "failed-install.app"
        if failed.exists():
            raise RuntimeError("Failed install and backup retained; failed-install.app is already occupied")
        destination.rename(failed)
    if backup:
        backup.rename(destination)
    raise
receipt = {
    "kind": "verified-local-installation",
    "installedAt": datetime.now(timezone.utc).isoformat(),
    "destination": str(destination),
    "buildManifestSHA256": hashlib.sha256(record.read_bytes()).hexdigest(),
    "verifiedFiles": len(manifest["artifactFiles"]),
    "verifiedSymlinks": len(manifest["artifactSymlinks"]),
    "launched": False,
    "previousInstallationBackup": str(backup) if backup else None,
}
(record.parent / "install.json").write_text(json.dumps(receipt, indent=2) + "\n")
print(f"Installed and verified: {destination}")
print("Quit the official app before opening Personal. The installer does not launch or control any app.")
