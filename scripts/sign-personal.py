"""Ad-hoc sign an isolated local test app without using developer credentials."""
import pathlib
import plistlib
import subprocess
import sys
import tempfile

app = pathlib.Path(sys.argv[1]).resolve()
root = pathlib.Path(__file__).resolve().parents[1]


def sign(path, entitlements=None):
    command = ["codesign", "--force", "--sign", "-", "--timestamp=none"]
    if entitlements:
        command += ["--entitlements", str(entitlements)]
    subprocess.run(command + [str(path)], check=True)


with tempfile.TemporaryDirectory(prefix="localsend-personal-sign-") as temp:
    entitlements = {}
    for name, relative in [("app", "Runner/Release.entitlements"), ("extension", "ShareExtension/ShareExtension.entitlements")]:
        source = (root / "app/macos" / relative).read_text()
        source = source.replace("$(AppIdentifierPrefix)", "").replace("$(TeamIdentifierPrefix)", "")
        target = pathlib.Path(temp) / f"{name}.plist"
        target.write_bytes(plistlib.dumps(plistlib.loads(source.encode())))
        entitlements[name] = target
    code = [p for p in app.rglob("*") if p.suffix in {".framework", ".dylib"} and not p.is_symlink()]
    for path in sorted(code, key=lambda p: len(p.parts), reverse=True):
        sign(path)
    # LaunchAtLogin rewrites its embedded helper's bundle ID during the build.
    # Re-sign nested apps after that rewrite, preserving their sandbox inheritance.
    for helper in sorted(app.rglob("*.app"), key=lambda p: len(p.parts), reverse=True):
        subprocess.run(["codesign", "--force", "--sign", "-", "--timestamp=none",
                        "--preserve-metadata=entitlements", str(helper)], check=True)
    for extension in app.rglob("*.appex"):
        sign(extension, entitlements["extension"])
    sign(app, entitlements["app"])
