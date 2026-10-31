"""Offline negative fixtures for publishing retained Android delivery bytes."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("android_release", Path(__file__).with_name("package-android-release.py"))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class AndroidReleaseTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.apk = self.root / "artifacts" / release.APK
        self.apk.parent.mkdir()
        self.apk.write_bytes(b"verified APK fixture")
        self.receipt = {"package": "org.localsend.localsend_app", "abi": "arm64-v8a", "signatureVerified": True,
                        "retainedKeyMatched": True, "sha256": release.common.sha256(self.apk), "bytes": self.apk.stat().st_size,
                        "signingCertificateSha256": "a" * 64, "versionCode": 202610393, "versionName": "1.18.3"}
        self.certificate = self.apk.with_name(self.apk.name + ".certificate.txt")
        self.certificate.write_text("Signer #1 certificate SHA-256 digest: " + "a" * 64)
        self.package = self.apk.with_name(self.apk.name + ".package.txt")
        self.package.write_text("package: name='org.localsend.localsend_app' versionCode='202610393' versionName='1.18.3' compileSdkVersion='36'\nnative-code: 'arm64-v8a'\n")

    def test_verified_retained_apk_passes(self):
        self.assertEqual(release.verify_apk(self.root, self.receipt), self.apk)

    def test_changed_apk_is_rejected(self):
        self.apk.write_bytes(b"tampered APK")
        with self.assertRaisesRegex(ValueError, "differs from"):
            release.verify_apk(self.root, self.receipt)

    def test_unverified_signature_is_rejected(self):
        self.receipt["signatureVerified"] = False
        with self.assertRaisesRegex(ValueError, "signing verification"):
            release.verify_apk(self.root, self.receipt)

    def test_changed_certificate_or_identity_is_rejected(self):
        self.certificate.write_text("Signer #1 certificate SHA-256 digest: " + "b" * 64)
        with self.assertRaisesRegex(ValueError, "certificate differs"):
            release.verify_apk(self.root, self.receipt)
        self.certificate.write_text("Signer #1 certificate SHA-256 digest: " + "a" * 64)
        self.package.write_text(self.package.read_text().replace("202610393", "202610403"))
        with self.assertRaisesRegex(ValueError, "identity differs"):
            release.verify_apk(self.root, self.receipt)

    def test_product_source_drift_is_rejected_but_release_metadata_is_allowed(self):
        source = self.root / "app/lib/main.dart"
        source.parent.mkdir(parents=True)
        source.write_text("verified source")
        manifest = {"sourceFiles": {"app/lib/main.dart": release.common.sha256(source)}}
        release.common.verify_source(self.root, manifest, ["app/lib/main.dart", "AGENTS.md", "scripts/package-android-release.py"])
        source.write_text("unverified source")
        with self.assertRaisesRegex(ValueError, "Source differs"):
            release.common.verify_source(self.root, manifest, ["app/lib/main.dart"])

    def test_directory_symlinks_remain_in_source_verification(self):
        target = self.root / "directory"
        target.mkdir()
        link = self.root / "new-link"
        link.symlink_to(target, target_is_directory=True)
        self.assertEqual(release.source_paths(self.root, ["directory", "new-link"]), ["new-link"])
        with self.assertRaisesRegex(ValueError, "Source symlink differs"):
            release.common.verify_source(self.root, {"sourceFiles": {}}, ["new-link"])

    def test_runtime_source_cannot_be_exempted_as_release_metadata(self):
        for path in ["app/assets/i18n/en.json", "app/android/app/src/main/AndroidManifest.xml", "scripts/build-android-personal.sh"]:
            self.assertFalse(release.common.release_metadata(path))


if __name__ == "__main__":
    unittest.main()
