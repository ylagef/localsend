"""Package the accepted local macOS build against an exact clean release commit."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import stat
import subprocess
import tempfile

REPOSITORY = "https://github.com/ylagef/localsend.git"
RELEASE_FILES = {
    ".release-local.json", "fork-version.json", "CHANGELOG.personal.md",
    ".github/workflows/ci.yml", "scripts/package-personal-release.py",
    "scripts/test-personal-release.py",
}


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def release_metadata(name):
    return name in RELEASE_FILES or name.startswith("docs/")


def verify_source(root, manifest, source_paths):
    """Product/build inputs must match the accepted build; only release metadata may differ."""
    expected = manifest["sourceFiles"]
    for name in set(expected) | set(source_paths):
        if release_metadata(name):
            continue
        path = root / name
        links = manifest.get("sourceSymlinks", {})
        if path.is_symlink() != (name in links) or (name in links and os.readlink(path) != links[name]):
            raise ValueError(f"Source symlink differs from the accepted build: {name}")
        if name not in expected or not path.is_file() or sha256(path) != expected[name]:
            raise ValueError(f"Source differs from the accepted build: {name}")


def verify_bundle(app, manifest):
    files = {str(p.relative_to(app)): sha256(p) for p in app.rglob("*") if p.is_file() and not p.is_symlink()}
    links = {str(p.relative_to(app)): os.readlink(p) for p in app.rglob("*") if p.is_symlink()}
    if files != manifest["artifactFiles"] or links != manifest["artifactSymlinks"]:
        raise ValueError("App files or symlinks differ from the accepted build")


def verify_permissions(original, unpacked):
    def modes(directory):
        entries = [directory, *directory.rglob("*")]
        return {str(p.relative_to(directory)): stat.S_IMODE(p.stat().st_mode) for p in entries if not p.is_symlink()}
    if modes(original) != modes(unpacked):
        raise ValueError("Extracted app permissions differ from the accepted build")


def run(root, *args):
    return subprocess.check_output(args, cwd=root, text=True).strip()


def main():
    root = Path(__file__).resolve().parents[1]
    if run(root, "git", "status", "--porcelain", "--untracked-files=all"):
        raise ValueError("Release packaging requires a clean committed tree")
    if run(root, "git", "branch", "--show-current") != "main":
        raise ValueError("Release packaging requires main")
    if run(root, "git", "remote", "get-url", "origin") != REPOSITORY:
        raise ValueError("Unexpected release repository")
    version = json.loads((root / "fork-version.json").read_text())["version"]
    manifest = json.loads((root / "artifacts/provenance/manifest.json").read_text())
    if manifest["origin"] != REPOSITORY:
        raise ValueError("Accepted build belongs to a different repository")
    subprocess.run(["git", "merge-base", "--is-ancestor", manifest["baseCommit"], "HEAD"], cwd=root, check=True)
    names = run(root, "git", "ls-files", "-z").split("\0")
    # Git submodule entries are directories; their pinned commit is recorded separately below.
    names = [name for name in names if name and not (root / name).is_dir()]
    verify_source(root, manifest, names)
    flutter = run(root / "support/submodules/flutter", "git", "rev-parse", "HEAD")
    pinned_flutter = run(root, "git", "rev-parse", "HEAD:support/submodules/flutter")
    if flutter != manifest["flutterCommit"] or pinned_flutter != flutter:
        raise ValueError("Flutter revision differs from the accepted build")
    app = root / "artifacts/LocalSend Personal.app"
    verify_bundle(app, manifest)
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    executable = app / "Contents/MacOS" / info["CFBundleExecutable"]
    architecture = run(root, "lipo", "-archs", str(executable))
    if info["CFBundleIdentifier"] != "dev.ylagef.localsendPersonal" or architecture != "arm64":
        raise ValueError("Unexpected app identity or architecture")
    output = root / ".release-local/github"
    if output.exists():
        raise FileExistsError("Preserve the previous .release-local/github output before packaging")
    output.parent.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="personal-release-", dir=output.parent) as temporary:
        stage = Path(temporary)
        source = stage / "LocalSend-Personal-source.tar.gz"
        run(root, "git", "archive", "--format=tar.gz", "--prefix=LocalSend-Personal/", f"--output={source}", "HEAD")
        zipped = stage / "LocalSend-Personal-macos-arm64.zip"
        subprocess.run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app), str(zipped)], check=True)
        # Verify actual decoded ZIP contents, not only the input bundle.
        unpacked = stage / "unpacked"
        subprocess.run(["ditto", "-x", "-k", str(zipped), str(unpacked)], check=True)
        verify_bundle(unpacked / app.name, manifest)
        verify_permissions(app, unpacked / app.name)
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(unpacked / app.name)], check=True)
        shutil.rmtree(unpacked)
        receipt = {
            "kind": "verified-retained-build-release", "forkVersion": version,
            "repository": REPOSITORY, "releaseCommit": run(root, "git", "rev-parse", "HEAD"),
            "compiledProductMatchesReleaseSource": True,
            "appVersion": info["CFBundleShortVersionString"], "appBuild": info["CFBundleVersion"],
            "bundleId": info["CFBundleIdentifier"], "architecture": architecture,
            "signing": manifest["signing"], "flutterCommit": flutter,
            "acceptedBuildBaseCommit": manifest["baseCommit"],
            "acceptedBuildManifestSHA256": sha256(root / "artifacts/provenance/manifest.json"),
            "executableSHA256": sha256(executable),
            "verifiedAppFiles": len(manifest["artifactFiles"]), "verifiedAppSymlinks": len(manifest["artifactSymlinks"]),
            "assets": {source.name: sha256(source), zipped.name: sha256(zipped)},
            "note": "Retained user-accepted local build; release packaging version is independent from app version. No notarization or store delivery.",
        }
        (stage / "release-provenance.json").write_text(json.dumps(receipt, indent=2) + "\n")
        assets = sorted(p for p in stage.iterdir() if p.is_file())
        (stage / "SHA256SUMS").write_text("".join(f"{sha256(p)}  {p.name}\n" for p in assets))
        stage.rename(output)
    print(f"Verified release assets: {output}")


if __name__ == "__main__":
    main()
