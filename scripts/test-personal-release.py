"""Small offline fixtures for release source and retained artifact integrity."""
import importlib.util
from pathlib import Path
import tempfile
import shutil
import unittest

spec = importlib.util.spec_from_file_location("packaging", Path(__file__).with_name("package-personal-release.py"))
packaging = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packaging)


class ReleaseIntegrityTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        source = self.root / "app/lib/main.dart"
        source.parent.mkdir(parents=True)
        source.write_text("accepted product")
        self.manifest = {"sourceFiles": {"app/lib/main.dart": packaging.sha256(source)}}

    def test_product_source_drift_is_rejected(self):
        paths = ["app/lib/main.dart"]
        packaging.verify_source(self.root, self.manifest, paths)
        (self.root / paths[0]).write_text("unvalidated product")
        with self.assertRaisesRegex(ValueError, "Source differs"):
            packaging.verify_source(self.root, self.manifest, paths)

    def test_deleted_and_unrecorded_product_files_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "Source differs"):
            packaging.verify_source(self.root, self.manifest, ["app/lib/main.dart", "app/lib/extra.dart"])
        (self.root / "app/lib/main.dart").unlink()
        with self.assertRaisesRegex(ValueError, "Source differs"):
            packaging.verify_source(self.root, self.manifest, [])

    def test_release_metadata_does_not_reclassify_product_changes(self):
        packaging.verify_source(self.root, self.manifest, ["app/lib/main.dart", "docs/RELEASING.md", "fork-version.json"])
        self.assertFalse(packaging.release_metadata("app/lib/release.dart"))
        self.assertFalse(packaging.release_metadata("scripts/build-macos-personal.sh"))

    def test_source_symlink_retarget_with_identical_bytes_is_rejected(self):
        for name in ["original.txt", "copy.txt"]:
            (self.root / name).write_text("accepted product")
        source = self.root / "app/lib/main.dart"
        source.unlink()
        source.symlink_to("../../original.txt")
        self.manifest["sourceSymlinks"] = {"app/lib/main.dart": "../../original.txt"}
        packaging.verify_source(self.root, self.manifest, ["app/lib/main.dart"])
        source.unlink()
        source.symlink_to("../../copy.txt")
        with self.assertRaisesRegex(ValueError, "Source symlink"):
            packaging.verify_source(self.root, self.manifest, ["app/lib/main.dart"])

    def test_extracted_permissions_are_verified(self):
        app, manifest = self.bundle()
        unpacked = self.root / "unpacked.app"
        shutil.copytree(app, unpacked, symlinks=True)
        packaging.verify_permissions(app, unpacked)
        (unpacked / "binary").chmod(0o700)
        packaging.verify_bundle(unpacked, manifest)
        with self.assertRaisesRegex(ValueError, "permissions"):
            packaging.verify_permissions(app, unpacked)

    def bundle(self):
        app = self.root / "Fixture.app"
        app.mkdir()
        (app / "binary").write_bytes(b"accepted bytes")
        (app / "alias").symlink_to("binary")
        manifest = {"artifactFiles": {"binary": packaging.sha256(app / "binary")}, "artifactSymlinks": {"alias": "binary"}}
        return app, manifest

    def test_exact_bundle_and_links_pass(self):
        app, manifest = self.bundle()
        packaging.verify_bundle(app, manifest)

    def test_changed_or_extra_bundle_bytes_are_rejected(self):
        app, manifest = self.bundle()
        (app / "extra").write_text("unexpected")
        with self.assertRaisesRegex(ValueError, "App files"):
            packaging.verify_bundle(app, manifest)
        (app / "extra").unlink()
        (app / "binary").write_bytes(b"modified")
        with self.assertRaisesRegex(ValueError, "App files"):
            packaging.verify_bundle(app, manifest)

    def test_changed_link_target_is_rejected(self):
        app, manifest = self.bundle()
        (app / "alias").unlink()
        (app / "alias").symlink_to("missing")
        with self.assertRaisesRegex(ValueError, "App files"):
            packaging.verify_bundle(app, manifest)


if __name__ == "__main__":
    unittest.main()
