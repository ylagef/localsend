"""Publish the retained verified Android APK with exact committed fork source."""
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

spec = importlib.util.spec_from_file_location("personal_release", Path(__file__).with_name("package-personal-release.py"))
common = importlib.util.module_from_spec(spec)
spec.loader.exec_module(common)
common.RELEASE_FILES.update({"AGENTS.md", "scripts/package-android-release.py", "scripts/test-android-release.py"})
APK = "LocalSend-Personal-android-arm64.apk"


def verify_apk(root, receipt):
    apk = root / "artifacts" / APK
    if receipt.get("package") != "org.localsend.localsend_app" or receipt.get("abi") != "arm64-v8a":
        raise ValueError("Unexpected Android package or ABI")
    if receipt.get("signatureVerified") is not True or receipt.get("retainedKeyMatched") is not True:
        raise ValueError("Missing retained signing verification")
    if common.sha256(apk) != receipt["sha256"] or apk.stat().st_size != receipt["bytes"]:
        raise ValueError("APK differs from the verified delivery")
    certificate = (apk.with_name(apk.name + ".certificate.txt")).read_text()
    match = re.search(r"Signer #1 certificate SHA-256 digest: ([0-9a-fA-F]{64})", certificate)
    if match is None or match[1].lower() != receipt["signingCertificateSha256"].lower():
        raise ValueError("Retained signing certificate differs")
    package = (apk.with_name(apk.name + ".package.txt")).read_text()
    expected = f"package: name='{receipt['package']}' versionCode='{receipt['versionCode']}' versionName='{receipt['versionName']}'"
    if not package.startswith(expected + " ") or re.findall(r"^native-code: (.+)$", package, re.M) != ["'arm64-v8a'"]:
        raise ValueError("Retained Android identity differs")
    return apk


def source_paths(root, names):
    # Git submodules are real directories; symlinks to directories are source and must be checked.
    return [name for name in names if name and ((root / name).is_symlink() or not (root / name).is_dir())]


def main():
    root = Path(__file__).resolve().parents[1]
    run = lambda *args: common.run(root, *args)
    if run("git", "status", "--porcelain", "--untracked-files=all"):
        raise ValueError("Android release packaging requires a clean committed tree")
    if run("git", "branch", "--show-current") != "main" or run("git", "remote", "get-url", "origin") != common.REPOSITORY:
        raise ValueError("Unexpected Android release branch or repository")
    receipt = json.loads((root / "artifacts/android-personal-delivery.json").read_text())
    subprocess.run(["git", "merge-base", "--is-ancestor", receipt["sourceBaseCommit"], "HEAD"], cwd=root, check=True)
    expected = json.loads(Path(receipt["sourceManifest"]).read_text())
    paths = source_paths(root, run("git", "ls-files", "-z").split("\0"))
    # The accepted source inventory hashes symlink contents. Bind link targets to its base commit too.
    links = {}
    for entry in run("git", "ls-tree", "-r", receipt["sourceBaseCommit"]).splitlines():
        if entry.startswith("120000 "):
            name = entry.split("\t", 1)[1]
            links[name] = run("git", "show", f"{receipt['sourceBaseCommit']}:{name}")
    common.verify_source(root, {"sourceFiles": expected, "sourceSymlinks": links}, paths)
    pinned_flutter = run("git", "rev-parse", "HEAD:support/submodules/flutter")
    if run("git", "-C", "support/submodules/flutter", "rev-parse", "HEAD") != pinned_flutter:
        raise ValueError("Flutter checkout differs from the committed pin")
    apk = verify_apk(root, receipt)
    version = json.loads((root / "fork-version.json").read_text())["version"]
    output = root / ".release-local/github-android"
    if output.exists():
        raise FileExistsError("Preserve previous github-android release assets before packaging")
    output.parent.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="android-release-", dir=output.parent) as temporary:
        stage = Path(temporary)
        source = stage / "LocalSend-Personal-source.tar.gz"
        run("git", "archive", "--format=tar.gz", "--prefix=LocalSend-Personal/", f"--output={source}", "HEAD")
        shutil.copy2(apk, stage / APK)
        if common.sha256(stage / APK) != receipt["sha256"]:
            raise ValueError("Packaged APK hash differs")
        # Deliberately select public fields: the local receipt contains private host paths and URLs.
        public = {
            "kind": "verified-retained-android-release", "forkVersion": version,
            "repository": common.REPOSITORY, "releaseCommit": run("git", "rev-parse", "HEAD"),
            "compiledProductMatchesReleaseSource": True, "flutterCommit": pinned_flutter,
            **{key: receipt[key] for key in ["package", "versionName", "versionCode", "abi", "minSdk", "targetSdk", "signingCertificateSha256"]},
            "assets": {source.name: common.sha256(source), APK: common.sha256(stage / APK)},
            "validation": "151 Flutter tests passed; 6 platform-specific skips. Android17 API37 release emulator: task removal, notification receipt with file hash, explicit stop and reopening verified.",
            "limits": "Physical Pixel, real Wi-Fi Doze and official desktop sender interoperability were not verified in this audit. No store upload. Fork release version is independent from the retained APK runtime version.",
        }
        (stage / "release-provenance.json").write_text(json.dumps(public, indent=2) + "\n")
        assets = sorted(stage.iterdir())
        (stage / "SHA256SUMS").write_text("".join(f"{common.sha256(p)}  {p.name}\n" for p in assets))
        stage.rename(output)
    print(f"Verified Android release assets: {output}")


if __name__ == "__main__":
    main()
