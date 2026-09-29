# Changelog

All notable changes to this project are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.0.0] - 2026-09-29

### Added

- Canonical POSIX `sh` implementation: `bin/opencode-profiles`
  (`list`, `switch`, `save`, `delete`, `current`, `toggle`, interactive menu).
- Python 3.8+ stdlib-only port: `py/opencode-profiles.py` (same CLI + `toggle`).
- PowerShell 5.1+/7+ port: `ps1/opencode-profiles.ps1` (same CLI + `toggle`).
- Generalized `toggle`: explicit pair (`toggle a b`), 2-profile flip,
  or most-recently-used cycling for 3+ profiles (`last_profile.txt`).
- `delete` subcommand with confirmation guard (new vs. upstream inspirations).
- Legacy compatibility: `opencode-switch` (toggle semantics) and
  `oc-profiles` / `oc-profile` (1:1 passthrough) shims via `install.sh`.
- Installers: `install.sh` (POSIX), `install.ps1` (Windows),
  `install.py` (cross-platform).
- Uninstallers that remove installed files only and never touch profiles.
- Bash completion (`completions/opencode-profiles.bash`).
- Test suites: `tests/test_sh.sh`, `tests/test_py.py`, `tests/test_ps1.ps1`.
- Docs: `README.md`, `CITATIONS.md`, `CHANGELOG.md`, MIT `LICENSE`.

### Acknowledgements

- Behavior inspired by the gist/repo lineage documented in `CITATIONS.md`.
  All code in this repository is a clean-room reimplementation —
  no source lines were copied from those works.
