#!/usr/bin/env python3
"""tests/test_py.py — suite for py/opencode-profiles.py (stdlib only).

Runs entirely inside throwaway OPENCODE_PROFILE_BASE_DIR directories, so
the real ~/.local/share/opencode is never touched.

Usage: python3 tests/test_py.py
"""

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / ".." / "py" / "opencode-profiles.py"


def run_tool(base, *args, feed=None):
    env = dict(os.environ)
    env["OPENCODE_PROFILE_BASE_DIR"] = str(base)
    proc = subprocess.run(
        [sys.executable, str(SCRIPT)] + list(args),
        input=feed,
        capture_output=True,
        text=True,
        env=env,
    )
    return proc.returncode, proc.stdout.strip(), proc.stderr.strip()


class ProfilesTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.base = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def tool(self, *args, **kwargs):
        return run_tool(self.base, *args, **kwargs)

    def write_live(self, text):
        (self.base / "auth.json").write_text(text, encoding="utf-8")

    def read_live(self):
        return (self.base / "auth.json").read_text(encoding="utf-8")

    # -- core -----------------------------------------------------------
    def test_save_switch_current(self):
        self.write_live('{"by":"work"}')
        rc, out, _ = self.tool("save", "work")
        self.assertEqual(rc, 0)
        self.write_live('{"by":"personal"}')
        rc, out, _ = self.tool("save", "personal")
        self.assertEqual(rc, 0)
        rc, out, _ = self.tool("current")
        self.assertEqual(out, "personal")
        rc, out, _ = self.tool("switch", "work")
        self.assertEqual(rc, 0)
        self.assertEqual(self.read_live(), '{"by":"work"}')

    def test_list_marks_active(self):
        self.write_live("a")
        self.tool("save", "work")
        self.write_live("b")
        self.tool("save", "personal")
        rc, out, _ = self.tool("list")
        self.assertEqual(rc, 0)
        self.assertIn("* personal  (active)", out)
        self.assertIn("work", out)

    def test_toggle_pair(self):
        self.write_live("a")
        self.tool("save", "work")
        self.write_live("b")
        self.tool("save", "personal")
        self.tool("switch", "work")
        self.tool("toggle")
        self.assertEqual(self.tool("current")[1], "personal")
        self.assertEqual(self.read_live(), "b")
        self.tool("toggle")
        self.assertEqual(self.tool("current")[1], "work")

    def test_toggle_explicit_pair(self):
        self.write_live("a")
        self.tool("save", "work")
        self.write_live("b")
        self.tool("save", "personal")
        self.tool("switch", "work")
        self.tool("toggle", "work", "personal")
        self.assertEqual(self.tool("current")[1], "personal")
        self.tool("toggle", "work", "personal")
        self.assertEqual(self.tool("current")[1], "work")

    def test_toggle_mru_three_profiles(self):
        self.write_live("A")
        self.tool("save", "alpha")
        self.write_live("B")
        self.tool("save", "beta")
        self.write_live("C")
        self.tool("save", "gamma")
        self.tool("switch", "alpha")
        self.tool("switch", "beta")
        self.tool("toggle")
        self.assertEqual(self.tool("current")[1], "alpha")

    def test_delete(self):
        self.write_live("a")
        self.tool("save", "work")
        rc, out, _ = self.tool("delete", "work", "--yes")
        self.assertEqual(rc, 0)
        self.assertFalse((self.base / "auth-work.json").exists())
        # live bytes survive deleting the active profile
        self.assertEqual(self.read_live(), "a")
        rc, out, _ = self.tool("current")
        self.assertTrue(out.startswith("unknown"))

    def test_overwrite_guard(self):
        self.write_live("v1")
        self.tool("save", "work")
        self.write_live("v2")
        rc, out, _ = self.tool("save", "work", feed="n\n")
        self.assertEqual((self.base / "auth-work.json").read_text(), "v1")
        rc, out, _ = self.tool("save", "work", feed="y\n")
        self.assertEqual((self.base / "auth-work.json").read_text(), "v2")

    # -- errors ----------------------------------------------------------
    def test_invalid_name(self):
        self.write_live("x")
        rc, out, _ = self.tool("save", "bad name")
        self.assertNotEqual(rc, 0)

    def test_unknown_profile(self):
        rc, out, err = self.tool("switch", "nosuch")
        self.assertNotEqual(rc, 0)
        self.assertIn("Error:", err)

    def test_help_version(self):
        rc, out, _ = self.tool("--help")
        self.assertEqual(rc, 0)
        self.assertIn("toggle", out)
        rc, out, _ = self.tool("--version")
        self.assertEqual(rc, 0)
        self.assertIn("1.0.0", out)

    # -- interop: py saves, sh switches -----------------------------------
    def test_shared_format_with_sh(self):
        sh_bin = HERE / ".." / "bin" / "opencode-profiles"
        if not sh_bin.is_file():
            self.skipTest("sh edition absent")
        self.write_live('{"by":"py"}')
        self.tool("save", "shared")
        env = dict(os.environ)
        env["OPENCODE_PROFILE_BASE_DIR"] = str(self.base)
        proc = subprocess.run(
            [str(sh_bin), "current"], capture_output=True, text=True, env=env
        )
        self.assertEqual(proc.stdout.strip(), "shared")


if __name__ == "__main__":
    unittest.main(verbosity=2)
