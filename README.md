# opencode-profiles

Switch between multiple [opencode](https://opencode.ai) auth profiles —
e.g. `work` and `personal` accounts — without hand-editing `auth.json`.

Three implementations with identical behaviour. Pick the one that fits
your platform:

| File | Runtime | Platform |
|------|---------|----------|
| `bin/opencode-profiles` | POSIX `sh`, zero dependencies | macOS, Linux, BSD, WSL |
| `ps1/opencode-profiles.ps1` | PowerShell 5.1+ / 7+ | Windows, macOS, Linux |
| `py/opencode-profiles.py` | Python 3.8+, stdlib only | Anywhere Python runs |

All three share the same subcommands, prompts, messages and on-disk
layout, so you can mix them (save with one, switch with another).

New in this project vs. the works it was inspired by (see
[Acknowledgements](#acknowledgements)): a generalized **`toggle`**
command (flip between any two profiles, or cycle most-recently-used),
a **`delete`** command, legacy **`opencode-switch` / `oc-profiles`**
compatibility aliases, installers, shell completion, and test suites.

## How it works

opencode keeps your login in a single live file:

```
~/.local/share/opencode/auth.json
```

Switching accounts by hand means: quit opencode → replace `auth.json` →
reopen opencode. This tool automates that by keeping **named snapshots**
next to the live file:

```
~/.local/share/opencode/
├── auth.json               live file opencode reads on startup
├── current_profile.txt     active profile name (managed by the tool)
├── last_profile.txt        previously active profile (toggle memory)
├── auth-work.json          saved profile "work"
└── auth-personal.json      saved profile "personal"
```

`switch <name>` copies `auth-<name>.json` over `auth.json` and records
the name. `save <name>` does the reverse. Profile names may only contain
letters, numbers, hyphens and underscores.

Safety properties:

- No network access, no elevated privileges, no package dependencies.
- Home-directory writes only.
- `save` is non-destructive (copies `auth.json`, never truncates it).
- Overwriting an existing profile always asks first (`[y/N]`).
- Deleting the *active* profile removes the snapshot but leaves the live
  `auth.json` untouched.
- If opencode seems to be running, `switch`/`toggle` warn you (opencode
  reads `auth.json` at launch, so switching mid-session has no effect).
- `.gitignore` excludes `auth*.json` / `current_profile.txt` /
  `last_profile.txt`, so credentials can never be committed by accident.

## Requirements

- The `sh` edition: any POSIX shell (`sh`, `dash`, `bash`, `zsh`).
- The PowerShell edition: Windows PowerShell 5.1+ or PowerShell 7+.
- The Python edition: Python 3.8+ (standard library only).
- An opencode installation that has logged in at least once (so that
  `auth.json` exists to snapshot).

## Installation

### Shell edition (macOS / Linux / BSD / WSL)

```sh
git clone https://github.com/Valentjno/opencode-profiles.git
cd opencode-profiles
./install.sh
```

This installs `opencode-profiles` to `~/.local/bin` plus the
compatibility aliases `opencode-switch`, `oc-profiles`, `oc-profile`.
Options: `./install.sh --prefix DIR` for another target,
`./install.sh --no-compat` to skip the aliases.

Make sure `~/.local/bin` is on `PATH` (the installer tells you if it
is not):

```sh
export PATH="$HOME/.local/bin:$PATH"
```

Verify:

```sh
opencode-profiles --help
```

Optional bash completion:

```sh
mkdir -p ~/.local/share/bash-completion/completions
cp completions/opencode-profiles.bash \
   ~/.local/share/bash-completion/completions/opencode-profiles
```

### PowerShell edition (Windows / cross-platform)

```powershell
git clone https://github.com/Valentjno/opencode-profiles.git
cd opencode-profiles
.\install.ps1
```

This copies the script to `~\bin\opencode-profiles.ps1` and prints the
remaining PATH step. If Windows blocks the file, unblock it once:

```powershell
Unblock-File ~\bin\opencode-profiles.ps1
```

If your execution policy blocks unsigned scripts, per-user
`RemoteSigned` is sufficient:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

Verify:

```powershell
opencode-profiles.ps1 --help
```

### Python edition (cross-platform)

```sh
git clone https://github.com/Valentjno/opencode-profiles.git
cd opencode-profiles
python3 install.py
```

Installs the Python port as `opencode-profiles` (`~/.local/bin`) on
POSIX or `opencode-profiles.py` (`%USERPROFILE%\bin`) on Windows.
On Windows you then run it as `py "%USERPROFILE%\bin\opencode-profiles.py"
--help`. Requires Python 3.8+; nothing to `pip install`.

## Usage

### Interactive menu (recommended for beginners)

Run with no arguments (or `-i`):

```sh
opencode-profiles
```

```
=== opencode-profiles ===
Base directory : /home/you/.local/share/opencode
Current profile: work

1) Switch to a profile
2) Save current auth.json as a profile
3) Toggle between profiles
4) List all profiles
5) Delete a profile
q) Quit

Choose an action [1-5, q]:
```

### CLI subcommands (scripts and power users)

Save the current `auth.json` once per account (after logging in through
opencode normally):

```sh
opencode-profiles save work
opencode-profiles save personal
opencode-profiles save client-acme
```

Switch accounts (always quit opencode first, reopen it after):

```sh
opencode-profiles switch personal
```

Flip between two profiles without naming the destination twice:

```sh
opencode-profiles toggle work personal   # work -> personal -> work ...
opencode-profiles toggle                 # 2 profiles: flip to the other;
                                         # 3+: jump to most-recently-used,
                                         # else next in sorted order
opencode-profiles toggle personal        # flip between current and personal
```

Inspect and clean up:

```sh
opencode-profiles list       # all profiles, marking the active one
opencode-profiles current    # active profile name (or status) only
opencode-profiles delete client-acme
opencode-profiles delete client-acme --yes   # skip the prompt (scripts)
```

The PowerShell and Python editions accept exactly the same arguments —
substitute the command name:

```powershell
.\opencode-profiles.ps1 save work
.\opencode-profiles.ps1 toggle work personal
```

```sh
./opencode-profiles.py save work
./opencode-profiles.py toggle work personal
```

### Typical workflow: setting up multiple accounts

```sh
# 1. Log in to account #1 via opencode normally, then snapshot it:
opencode-profiles save work

# 2. Log in to account #2 via opencode, then snapshot it:
opencode-profiles save personal

# 3. From now on, to switch: quit opencode, run one command, reopen:
opencode-profiles switch personal
# ...or just:
opencode-profiles toggle
```

### Custom base directory

If your opencode data lives elsewhere (e.g. an encrypted volume), point
the tools at it with `OPENCODE_PROFILE_BASE_DIR`:

```sh
OPENCODE_PROFILE_BASE_DIR="/Volumes/EncryptedDrive/opencode" opencode-profiles list
```

```powershell
$env:OPENCODE_PROFILE_BASE_DIR = 'D:\EncryptedDrive\opencode'
.\opencode-profiles.ps1 list
```

Export the variable in your shell rc / `$PROFILE` to make it permanent.

### Compatibility aliases

If you used the earlier scripts this project replaces, the old names
keep working after `./install.sh`:

| Legacy name | Behaviour |
|-------------|-----------|
| `opencode-switch` | Toggle-oriented alias: bare run toggles; `work`/`personal` switch; `current` prints the active profile. Prints a deprecation hint to stderr. |
| `oc-profiles`, `oc-profile` | 1:1 alias of `opencode-profiles` (same hint). |

## Security hardening

Snapshots hold the same secrets as `auth.json`. Lock them down to your
user:

```sh
# macOS / Linux / BSD
chmod 700 ~/.local/share/opencode
chmod 600 ~/.local/share/opencode/auth-*.json
```

On Windows, restrict the folder's ACL to your user via
**Properties → Security**, or with `icacls` from an elevated prompt.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `profile not found: 'xyz'` | Run `list` — names are case-sensitive. |
| `no auth.json found` | Log in via opencode first, then `save <name>`. |
| Switched but opencode shows the old account | You switched while opencode was running — quit it, switch, reopen. |
| `current` says `unknown (auth.json exists …)` | No snapshot is linked (e.g. the active one was deleted) — `save` or `switch` to re-link. |
| `current` says `<name> (profile file missing)` | The snapshot was deleted by hand — `save <name>` again. |
| Windows: script cannot be loaded / execution disabled | See `Unblock-File` and `Set-ExecutionPolicy` under Installation. |
| Python: `No module named …` | You need Python 3.8+ stdlib — the script installs nothing; check `python3 --version`. |
| Permission denied writing the directory | Check you own the base dir (`ls -la ~/.local/share/`). |

## Uninstalling

```sh
./uninstall.sh            # or uninstall.ps1 on Windows
```

Removes the program files (and aliases) only — profile data is never
touched. To also delete snapshots (keeping the live `auth.json`):

```sh
rm ~/.local/share/opencode/auth-*.json
rm ~/.local/share/opencode/current_profile.txt \
   ~/.local/share/opencode/last_profile.txt
```

## Quick reference

```
opencode-profiles                  # interactive menu
opencode-profiles save <name>      # snapshot current auth.json
opencode-profiles switch <name>    # activate a saved profile
opencode-profiles toggle [a] [b]   # flip between profiles
opencode-profiles list             # list profiles + active marker
opencode-profiles current          # print active profile only
opencode-profiles delete <name>    # remove a saved profile
opencode-profiles --help           # full help
opencode-profiles --version        # version
```

## Testing

```sh
sh tests/test_sh.sh          # 30 checks, POSIX shell edition
python3 tests/test_py.py     # 11 checks, Python edition (+ sh interop)
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\test_ps1.ps1
# 18 checks, PowerShell edition (Pester NOT required)
```

All suites run against throwaway `OPENCODE_PROFILE_BASE_DIR`
directories — your real profiles are never touched. The `.ps1` files
are also clean under
[PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer)
(no errors; remaining notes are intentional, e.g. short local helper
names shared across the three editions).

## Repository layout

```
opencode-profiles/
├── bin/opencode-profiles        canonical POSIX sh implementation
├── py/opencode-profiles.py      Python 3.8+ port (stdlib only)
├── ps1/opencode-profiles.ps1    PowerShell 5.1+/7+ port
├── install.sh / uninstall.sh    POSIX installer / uninstaller
├── install.ps1 / uninstall.ps1  Windows installer / uninstaller
├── install.py                   cross-platform (Python edition) installer
├── completions/                 bash completion
├── tests/                       test_sh.sh, test_py.py, test_ps1.ps1
├── CITATIONS.md                 provenance + full citation chain
├── CHANGELOG.md                 release notes
├── LICENSE                      MIT
└── README.md                    this file
```

## Acknowledgements

Behavioural lineage (see [`CITATIONS.md`](CITATIONS.md) for the full
chain with URLs):

1. **[@yeoweizheng](https://github.com/yeoweizheng)** — original
   `oc-profile.sh` gist (interactive-only ancestor).
2. **[@locxter](https://github.com/locxter)** — documented fork adding
   CLI subcommands, safety docs and `OPENCODE_PROFILE_BASE_DIR`.
3. **[@huydhoang](https://github.com/huydhoang/oc-profile)** —
   three-way `sh` + `ps1` + `py` port with Windows support and unified
   docs.
4. A local `opencode-switch` toggle wrapper — the idea behind the
   generalized `toggle` command (none of the above has one).

None of (1)–(3) carries an explicit license, so this repository is a
**clean-room reimplementation**: no source lines were copied — only the
unprotectable behaviour (snapshot files next to `auth.json`, the
`list`/`switch`/`save`/`current` vocabulary) was used as a functional
spec. If you build on the upstream works directly, please credit their
authors (links above).

## Contributing

Issues and pull requests are welcome. Please:

- Keep the three editions behaviour-identical (same commands, same
  messages, same exit codes, same on-disk format).
- Add/extend tests in `tests/` for any behaviour change.
- Never commit `auth*.json`, `current_profile.txt` or
  `last_profile.txt` (already in `.gitignore`).
- Run the relevant suite(s) before pushing.

## License

MIT — see [LICENSE](LICENSE).
