"""Exercise packaging guards with real Mach-O binaries, without an Apple account."""
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest

from mediapipe_static_packaging import NAMES, PackagingError, remove_wrappers


class StaticPackagingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.compiled = tempfile.TemporaryDirectory(prefix="coach-packaging-binaries-")
        root = Path(cls.compiled.name)
        cls.empty = root / "Empty.dylib"
        cls.code = root / "Code.dylib"
        cls.archive = root / "Static.a"
        cls.main = root / "Main"
        cls.linked = root / "LinkedMain"
        source = root / "Main.c"
        source.write_text("int main(void) { return 0; }\n")
        implementation = root / "Code.c"
        implementation.write_text("int real_sdk_function(void) { return 42; }\n")
        commands = [
            ["clang", "-dynamiclib", "-x", "c", "/dev/null", "-Wl,-install_name,@rpath/MediaPipeTasksVision.framework/MediaPipeTasksVision", "-o", str(cls.empty)],
            ["clang", "-dynamiclib", str(implementation), "-o", str(cls.code)],
            ["clang", "-c", str(implementation), "-o", str(root / "Code.o")],
            ["libtool", "-static", "-o", str(cls.archive), str(root / "Code.o")],
            ["clang", str(source), "-o", str(cls.main)],
            ["clang", str(source), f"-Wl,-needed_library,{cls.empty}", "-o", str(cls.linked)],
        ]
        for command in commands:
            subprocess.run(["xcrun", *command], check=True, capture_output=True)

    @classmethod
    def tearDownClass(cls):
        cls.compiled.cleanup()

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="coach-packaging-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.app = self.root / "Test.app"
        self.products = self.root / "Products"
        self.app.mkdir()
        self.products.mkdir()
        shutil.copyfile(self.main, self.app / "Test")

    def wrapper(self, name):
        wrapper = self.app / "Frameworks" / f"{name}.framework"
        wrapper.mkdir(parents=True)
        shutil.copyfile(self.empty, wrapper / name)
        with (wrapper / "Info.plist").open("wb") as stream:
            plistlib.dump({"CFBundleExecutable": name}, stream)
        linked_input = self.products / f"{name}.framework"
        linked_input.mkdir()
        shutil.copyfile(self.archive, linked_input / name)
        return wrapper

    def test_removes_six_empty_wrappers_and_preserves_unrelated_code_and_resources(self):
        for name in NAMES:
            self.wrapper(name)
        resource = self.app / "PrivacyInfo.xcprivacy"
        resource.write_bytes(b"privacy data must survive")
        other = self.app / "Frameworks/Other.framework/Other"
        other.parent.mkdir()
        shutil.copyfile(self.code, other)
        self.assertEqual(len(remove_wrappers(self.app, self.products)), 6)
        self.assertEqual(resource.read_bytes(), b"privacy data must survive")
        self.assertEqual(other.read_bytes(), self.code.read_bytes())
        self.assertTrue((self.app / "Test").exists())

    def test_cleanup_is_idempotent(self):
        self.wrapper("MediaPipeTasksVision")
        self.assertEqual(remove_wrappers(self.app, self.products), ["MediaPipeTasksVision.framework"])
        self.assertEqual(remove_wrappers(self.app, self.products), [])

    def test_real_sdk_code_aborts_before_removing_any_wrapper(self):
        audio = self.wrapper("MediaPipeTasksAudio")
        vision = self.wrapper("MediaPipeTasksVision")
        shutil.copyfile(self.code, vision / "MediaPipeTasksVision")
        with self.assertRaisesRegex(PackagingError, "code/data/exports"):
            remove_wrappers(self.app, self.products)
        self.assertTrue(audio.is_dir())
        self.assertTrue(vision.is_dir())

    def test_resource_bearing_wrapper_is_preserved(self):
        vision = self.wrapper("MediaPipeTasksVision")
        (vision / "PrivacyInfo.xcprivacy").write_bytes(b"retain SDK privacy")
        with self.assertRaisesRegex(PackagingError, "contains resources"):
            remove_wrappers(self.app, self.products)
        self.assertTrue(vision.is_dir())

    def test_runtime_dependency_aborts_removal(self):
        vision = self.wrapper("MediaPipeTasksVision")
        shutil.copyfile(self.linked, self.app / "Test")
        with self.assertRaisesRegex(PackagingError, "runtime dependency"):
            remove_wrappers(self.app, self.products)
        self.assertTrue(vision.is_dir())

    def test_debug_dylib_runtime_dependency_is_also_detected(self):
        vision = self.wrapper("MediaPipeTasksVision")
        shutil.copyfile(self.linked, self.app / "Test.debug.dylib")
        with self.assertRaisesRegex(PackagingError, "runtime dependency"):
            remove_wrappers(self.app, self.products)
        self.assertTrue(vision.is_dir())

    def test_dynamic_linked_input_is_rejected(self):
        vision = self.wrapper("MediaPipeTasksVision")
        shutil.copyfile(self.code, self.products / "MediaPipeTasksVision.framework/MediaPipeTasksVision")
        with self.assertRaisesRegex(PackagingError, "expected static archive"):
            remove_wrappers(self.app, self.products)
        self.assertTrue(vision.is_dir())

    def test_symlinked_wrapper_is_never_removed(self):
        vision = self.wrapper("MediaPipeTasksVision")
        outside = self.root / "Original.framework"
        vision.rename(outside)
        vision.symlink_to(outside, target_is_directory=True)
        with self.assertRaisesRegex(PackagingError, "symlinked wrapper"):
            remove_wrappers(self.app, self.products)
        self.assertTrue(outside.is_dir())

    def test_missing_main_executable_prevents_cleanup(self):
        vision = self.wrapper("MediaPipeTasksVision")
        (self.app / "Test").unlink()
        with self.assertRaisesRegex(PackagingError, "main executable must be linked"):
            remove_wrappers(self.app, self.products)
        self.assertTrue(vision.is_dir())


if __name__ == "__main__":
    unittest.main()
