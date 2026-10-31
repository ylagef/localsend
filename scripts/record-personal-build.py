"""Retain source and artifact provenance for a development build, including dirty files."""
import hashlib
import json
import os
import pathlib
import subprocess
import sys
import tarfile
from datetime import datetime, timezone

root = pathlib.Path(__file__).resolve().parents[1]
app = pathlib.Path(sys.argv[1]).resolve()
records = root / "artifacts/provenance"
records.mkdir(parents=True, exist_ok=False)


def git(*args):
    return subprocess.check_output(["git", *args], cwd=root)


paths = git("ls-files", "--cached", "--others", "--exclude-standard", "-z").decode().split("\0")
source_hashes = {}
source_symlinks = {}
with tarfile.open(records / "source.tar.gz", "w:gz") as archive:
    for relative in sorted(set(paths) - {""}):
        path = root / relative
        if path.is_file():
            source_hashes[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
            if path.is_symlink():
                source_symlinks[relative] = os.readlink(path)
            archive.add(path, arcname=relative, recursive=False)
(records / "source.patch").write_bytes(git("diff", "--binary", "HEAD"))
artifact_hashes = {
    str(path.relative_to(app)): hashlib.sha256(path.read_bytes()).hexdigest()
    for path in sorted(app.rglob("*")) if path.is_file() and not path.is_symlink()
}
manifest = {
    "kind": "local-development-build",
    "createdAt": datetime.now(timezone.utc).isoformat(),
    "baseCommit": git("rev-parse", "HEAD").decode().strip(),
    "branch": git("branch", "--show-current").decode().strip(),
    "dirty": bool(git("status", "--porcelain")),
    "origin": git("remote", "get-url", "origin").decode().strip(),
    "flutterCommit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root / "support/submodules/flutter", text=True).strip(),
    "sourceFiles": source_hashes,
    "sourceSymlinks": source_symlinks,
    "artifact": str(app),
    "artifactFiles": artifact_hashes,
    "artifactSymlinks": {str(path.relative_to(app)): os.readlink(path) for path in app.rglob("*") if path.is_symlink()},
    "signing": "ad-hoc; not notarized or distributed through a store",
}
(records / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(f"Development build provenance: {records / 'manifest.json'}")
