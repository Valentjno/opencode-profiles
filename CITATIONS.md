# Citations & provenance

This project is a **clean-room reimplementation**. No source lines were
copied from the works below. Only the *behavior* (copy
`auth-<name>.json` ↔ `auth.json`, track `current_profile.txt`) and the
general command vocabulary (`list` / `switch` / `save` / `current`,
interactive menu) were used as a functional specification, which is not
copyrightable expression. The `toggle` command, the `delete` command,
MRU cycling via `last_profile.txt`, the three-way parity, and all install /
test / completion files are original to this repository.

If you use or discuss this lineage, please cite all four sources:

## 1. Original gist — yeoweizheng

- Author: [@yeoweizheng](https://github.com/yeoweizheng)
- Gist: `oc-profile.sh` (interactive-only ancestor)
- URL: <https://gist.github.com/yeoweizheng/49c48fc7ff7e8c0f5165ca290e2162d4>
- License: none stated (all rights reserved; view/fork on GitHub only,
  no redistribution grant). Accessed 2026-09-29.

## 2. Documented fork — locxter

- Author: [@locxter](https://github.com/locxter)
- Gist: `oc-profile.md` (guide) + `oc-profile.sh` (CLI subcommands
  `switch` / `save` / `list` / `current`, safety docs,
  `OPENCODE_PROFILE_BASE_DIR` override)
- URL: <https://gist.github.com/locxter/82b613aef5909817b352f62ba9734726>
- Note: fork banner credits (1) above. No license stated.
  Accessed 2026-09-29.

## 3. Three-way port — huydhoang

- Author: [@huydhoang](https://github.com/huydhoang)
- Repo: `oc-profile` — `oc-profile.sh` + `oc-profile.ps1`
  (PowerShell 5.1+/7+, `Get-Process` running-check, BOM-free UTF-8
  `current_profile.txt`, `Unblock-File` / `RemoteSigned` notes)
  + `oc-profile.py` (Python 3.8+ stdlib-only, `pgrep` → `tasklist` → `ps`
  running-check cascade) + unified cross-implementation README
  (platform installs, hardening incl. Windows ACL/`icacls`, troubleshooting).
- URL: <https://github.com/huydhoang/oc-profile>
- Note: About section credits (1) and (2)
  ("Original authors: @locxter and @yeoweizheng"). No `LICENSE` file
  shipped. Accessed 2026-09-29.

**Parity observed across all three implementations of (3)** (used as the
behavioral test oracle for this repo): on-disk layout `auth.json` /
`auth-<name>.json` / `current_profile.txt`; name rule `^[A-Za-z0-9_-]+$`;
overwrite `[y/N]` guard; non-destructive `save` (copy, never truncate);
no network / no dependencies / home-directory-only writes;
`OPENCODE_PROFILE_BASE_DIR` honored everywhere.

## 4. Toggle concept — local `opencode-switch` wrapper

- Author: Valentino Merlino (unpublished, `~/.local/bin/opencode-switch`,
  91-line POSIX `sh`).
- Role: thin wrapper adding a `work` ↔ `personal` toggle over an
  `oc-profiles`-style backend. The generalized `toggle [a] [b]` /
  MRU-cycling semantics in this repository are derived from that idea,
  reimplemented from scratch. None of the cited works (1)–(3) has
  a `toggle` command.

## License-request track (optional, non-blocking)

Because (1)–(3) carry no explicit license, redistribution of their literal
code is not granted. This repository therefore vendors none of it. In
parallel, maintainers may ask each upstream author to add an explicit
license grant (e.g. MIT) via a gist/repo comment. Such a grant would allow
future upstream alignment but is not required for this independent
implementation.
