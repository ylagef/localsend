"""Offline checks for Android delivery identity validation."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('verify_android', Path(__file__).with_name('verify-android-personal.py'))
verify = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verify)


class AndroidIdentityTests(unittest.TestCase):
    def setUp(self):
        self.package = "package: name='org.localsend.localsend_app' versionCode='123' versionName='1.18.3'\nnative-code: 'arm64-v8a'\n"
        self.certificate = 'Signer #1 certificate SHA-256 digest: abc123\n'

    def check(self, package=None, certificate=None):
        verify.verify_metadata(package or self.package, certificate or self.certificate, '1.18.3', 12, 'abc123')

    def test_exact_personal_identity_is_accepted(self):
        self.check()

    def test_other_package_is_rejected(self):
        with self.assertRaises(ValueError): self.check(self.package.replace('localsend_app', 'localsend_app.debug'))

    def test_different_signing_key_is_rejected(self):
        with self.assertRaises(ValueError): self.check(certificate=self.certificate.replace('abc123', 'def456'))

    def test_wrong_build_is_rejected(self):
        with self.assertRaises(ValueError): self.check(self.package.replace("versionCode='123'", "versionCode='124'"))

    def test_emulator_or_mixed_architecture_is_rejected(self):
        with self.assertRaises(ValueError): self.check(self.package.replace("'arm64-v8a'", "'arm64-v8a' 'x86_64'"))


if __name__ == '__main__':
    unittest.main()
