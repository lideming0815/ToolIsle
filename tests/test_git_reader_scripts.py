"""Portable harness checks; these do not replace the real macOS Store test."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
NATIVE = ROOT / "scripts/test_git_reader_native.sh"


class GitReaderScriptTests(unittest.TestCase):
    def run_native(self, derived_data=None):
        env = os.environ.copy()
        env.pop("DERIVED_DATA", None)
        if derived_data is not None:
            env["DERIVED_DATA"] = str(derived_data)
        return subprocess.run(
            ["bash", str(NATIVE)], cwd=ROOT, env=env,
            capture_output=True, text=True, timeout=10,
        )

    def test_reader_scripts_parse_before_any_build(self):
        for name in ("test_git_reader.sh", "test_git_reader_native.sh"):
            with self.subTest(script=name):
                result = subprocess.run(
                    ["bash", "-n", str(ROOT / "scripts" / name)],
                    capture_output=True, text=True, timeout=10,
                )
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_missing_derived_data_has_actionable_diagnostic(self):
        result = self.run_native()
        self.assertEqual(result.returncode, 2)
        self.assertIn("Set DERIVED_DATA", result.stderr)
        self.assertNotIn("unexpected EOF", result.stderr)

    def test_empty_derived_data_is_rejected(self):
        result = self.run_native("")
        self.assertEqual(result.returncode, 2)
        self.assertIn("Set DERIVED_DATA", result.stderr)

    def test_missing_dependency_with_spaces_and_apostrophe_in_path(self):
        with tempfile.TemporaryDirectory(prefix="reader's build ") as directory:
            result = self.run_native(directory)
            self.assertEqual(result.returncode, 2)
            self.assertIn("Missing built Defaults object:", result.stderr)
            self.assertIn(str(Path(directory) / "Build/Products/Debug/Defaults.o"), result.stderr)
            self.assertNotIn("unexpected EOF", result.stderr)


if __name__ == "__main__":
    unittest.main()
