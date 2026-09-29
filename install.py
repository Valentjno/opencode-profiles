#!/usr/bin/env python3
"""install.py — cross-platform installer for the Python edition.

Copies py/opencode-profiles.py to a directory on PATH
(default: ~/.local/bin on POSIX, %USERPROFILE%\\bin on Windows),
as ``opencode-profiles`` (POSIX, executable) or ``opencode-profiles.py``
(Windows). Profile data is never touched.

For the POSIX shell edition prefer ./install.sh; for the native Windows
edition prefer ./install.ps1. This installer is the batteries-included
fallback that works anywhere Python 3.8+ runs.

Usage:
    python3 install.py [--prefix DIR] [--name NAME]
"""

import argparse
import os
import shutil
import stat
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SRC = HERE / "py" / "opencode-profiles.py"


def main():
    parser = argparse.ArgumentParser(description="Install opencode-profiles (Python edition).")
    parser.add_argument("--prefix", default="",
                        help="target directory (default: ~/.local/bin or %%USERPROFILE%%\\bin)")
    parser.add_argument("--name", default="",
                        help="installed file name (default picks per-OS)")
    args = parser.parse_args()

    if not SRC.is_file():
        print("Error: cannot find %s; run from the repo root" % SRC, file=sys.stderr)
        return 1

    if args.prefix:
        target_dir = Path(args.prefix).expanduser()
    elif os.name == "nt":
        target_dir = Path.home() / "bin"
    else:
        target_dir = Path.home() / ".local" / "bin"

    default_name = "opencode-profiles.py" if os.name == "nt" else "opencode-profiles"
    dest = target_dir / (args.name or default_name)

    try:
        target_dir.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(str(SRC), str(dest))
        if os.name != "nt":
            mode = dest.stat().st_mode
            dest.chmod(mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    except OSError as exc:
        print("Error: install failed: %s" % exc, file=sys.stderr)
        return 1

    print("Installed: %s" % dest)
    if os.name == "nt":
        print("Run it with: py \"%s\" --help" % dest)
        print("Tip: the native edition is ps1/opencode-profiles.ps1 (see install.ps1).")
    else:
        print("Verify with: opencode-profiles --help")
        path_dirs = os.environ.get("PATH", "").split(os.pathsep)
        if str(target_dir) not in path_dirs:
            print("Note: %s is not on PATH. Add to your shell rc:" % target_dir)
            print("  export PATH=\"$HOME/.local/bin:$PATH\"")
    return 0


if __name__ == "__main__":
    sys.exit(main())
