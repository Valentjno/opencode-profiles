#!/usr/bin/env python3
"""opencode-profiles: manage multiple opencode auth profiles.

Snapshots live beside the credentials file opencode reads::

    $BASE/auth.json             live credentials (opencode reads this)
    $BASE/auth-<name>.json      one snapshot per saved profile
    $BASE/current_profile.txt   active profile name
    $BASE/last_profile.txt      previously active profile (toggle memory)

$BASE defaults to ~/.local/share/opencode; set OPENCODE_PROFILE_BASE_DIR
to override it. Stdlib only, Python 3.8+.

Clean-room implementation for the opencode-profiles project (MIT).
Behavioural inspirations are credited in CITATIONS.md; no lines are
copied from those works.
"""

import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

VERSION = "1.0.0"
NAME_PATTERN = re.compile(r"^[A-Za-z0-9_-]+$")


class Store:
    """Resolved on-disk locations for one base directory."""

    def __init__(self, base):
        self.base = base
        self.live = base / "auth.json"
        self.track = base / "current_profile.txt"
        self.prev = base / "last_profile.txt"

    def slot(self, name):
        return self.base / ("auth-%s.json" % name)


def resolve_store():
    override = os.environ.get("OPENCODE_PROFILE_BASE_DIR", "").strip()
    if override:
        base = Path(override).expanduser()
    else:
        base = Path.home() / ".local" / "share" / "opencode"
    store = Store(base)
    try:
        base.mkdir(parents=True, exist_ok=True)
    except OSError:
        abort("cannot create directory '%s'" % base)
    return store


def abort(message):
    print("Error: %s" % message, file=sys.stderr)
    sys.exit(1)


def tell(message=""):
    print(message)


def caution(message):
    print("Warning: %s" % message, file=sys.stderr)


def ask(prompt):
    """Return a stripped input line, or None on EOF."""
    try:
        return input(prompt).strip()
    except (EOFError, KeyboardInterrupt):
        print()
        return None


def read_first_line(path):
    try:
        with open(str(path), "r", encoding="utf-8") as handle:
            line = handle.readline()
    except OSError:
        return ""
    return line.strip().strip("\r\n").strip()


def collect_profiles(store):
    found = []
    try:
        entries = list(store.base.iterdir())
    except OSError:
        return []
    for entry in entries:
        if not entry.is_file():
            continue
        fname = entry.name
        if not fname.startswith("auth-") or not fname.endswith(".json"):
            continue
        inner = fname[len("auth-"):-len(".json")]
        if inner and "/" not in inner and "\\" not in inner:
            found.append(inner)
    return sorted(set(found))


def describe_current(store):
    """Return (recorded, active, text, previous)."""
    recorded = ""
    active = ""
    previous = ""
    if store.track.is_file():
        recorded = read_first_line(store.track)
        if recorded and store.slot(recorded).is_file():
            active = recorded
            text = recorded
        elif recorded:
            text = "%s (profile file missing)" % recorded
        else:
            text = "unset (empty tracking file)"
    elif store.live.is_file():
        text = "unknown (auth.json exists but is not linked to a saved profile)"
    else:
        text = "unset (no auth.json)"
    if store.prev.is_file():
        previous = read_first_line(store.prev)
    return recorded, active, text, previous


def name_acceptable(name):
    if not name:
        tell("Profile name cannot be empty.")
        return False
    if not NAME_PATTERN.match(name):
        tell("Profile name may only contain letters, numbers, underscores, and hyphens.")
        return False
    return True


def confirm(question):
    answer = ask("%s [y/N]: " % question)
    return answer is not None and answer.lower() in ("y", "yes")


def opencode_active():
    """Best-effort check for a running opencode process; never raises."""
    if shutil.which("pgrep"):
        try:
            done = subprocess.run(
                ["pgrep", "-x", "opencode"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            return done.returncode == 0
        except OSError:
            pass
    if os.name == "nt":
        try:
            done = subprocess.run(
                ["tasklist", "/FI", "IMAGENAME eq opencode.exe", "/NH"],
                capture_output=True,
                text=True,
            )
            return "opencode.exe" in (done.stdout or "").lower()
        except OSError:
            return False
    if shutil.which("ps"):
        try:
            done = subprocess.run(
                ["ps", "-A", "-o", "comm="], capture_output=True, text=True
            )
            return any(
                line.strip() == "opencode"
                for line in (done.stdout or "").splitlines()
            )
        except OSError:
            pass
    return False


def remember(store, name, remembered_as_previous=None):
    if remembered_as_previous:
        try:
            store.prev.write_text(remembered_as_previous + "\n", encoding="utf-8")
        except OSError:
            abort("cannot update last_profile.txt")
    try:
        store.track.write_text(name + "\n", encoding="utf-8")
    except OSError:
        abort("cannot update current_profile.txt")


def activate(store, name, active):
    source = store.slot(name)
    if not source.is_file():
        abort("profile not found: '%s' (see 'list')" % name)
    if opencode_active():
        caution("opencode seems to be running; quit it first, then switch, then reopen it.")
    older = active if active and active != name else None
    try:
        shutil.copyfile(str(source), str(store.live))
    except OSError:
        abort("cannot copy profile over auth.json")
    remember(store, name, older)
    tell("Switched to profile '%s'." % name)


def snapshot(store, name, active):
    if not store.live.is_file():
        abort("no auth.json at '%s'; log in via opencode first" % store.live)
    try:
        shutil.copyfile(str(store.live), str(store.slot(name)))
    except OSError:
        abort("cannot save profile '%s'" % name)
    older = active if active and active != name else None
    remember(store, name, older)
    tell("Saved current auth.json to profile '%s'." % name)


def remove_saved(store, name, active, skip_prompt=False):
    target = store.slot(name)
    if not target.is_file():
        abort("profile not found: '%s' (see 'list')" % name)
    if not skip_prompt and not confirm("Delete profile '%s'?" % name):
        tell("Aborted.")
        return
    try:
        target.unlink()
    except OSError:
        abort("cannot delete profile '%s'" % name)
    if active == name:
        try:
            if store.track.is_file():
                store.track.unlink()
        except OSError:
            abort("cannot update current_profile.txt")
    tell("Deleted profile '%s'." % name)


def show_list(store):
    profiles = collect_profiles(store)
    _, active, text, _ = describe_current(store)
    tell("Current profile: %s" % text)
    tell("")
    if not profiles:
        tell("No saved profiles in %s" % store.base)
        tell("Tip: 'save <name>' snapshots the current auth.json.")
        return
    tell("Available profiles:")
    for item in profiles:
        if item == active:
            tell("  * %s  (active)" % item)
        else:
            tell("    %s" % item)


def show_current(store):
    tell(describe_current(store)[2])


def pick_other(profiles, active):
    for item in profiles:
        if item != active:
            return item
    return ""


def pick_next(profiles, active):
    if active in profiles:
        idx = profiles.index(active)
        return profiles[(idx + 1) % len(profiles)]
    return profiles[0] if profiles else ""


def flip(store, first="", second=""):
    if first and not name_acceptable(first):
        sys.exit(1)
    if second and not name_acceptable(second):
        sys.exit(1)
    profiles = collect_profiles(store)
    _, active, text, previous = describe_current(store)
    known = set(profiles)

    if first and second:
        if first == second:
            abort("toggle needs two different profile names")
        if first not in known:
            abort("profile not found: '%s' (see 'list')" % first)
        if second not in known:
            abort("profile not found: '%s' (see 'list')" % second)
        if active == first:
            activate(store, second, active)
        elif active == second:
            activate(store, first, active)
        else:
            tell("Current profile is '%s'; selecting '%s'." % (text, first))
            activate(store, first, active)
        return

    if first:
        if first not in known:
            abort("profile not found: '%s' (see 'list')" % first)
        if active == first:
            fallback = ""
            if previous and previous != first and previous in known:
                fallback = previous
            elif len(profiles) >= 2:
                fallback = pick_other(profiles, first)
            if not fallback:
                abort("only one profile exists; nothing to toggle to")
            activate(store, fallback, active)
        else:
            activate(store, first, active)
        return

    if not profiles:
        abort("no saved profiles (see: save <name>)")
    if len(profiles) == 1:
        tell("Already on profile '%s'. Nothing to do." % profiles[0])
        return
    if len(profiles) == 2:
        dest = pick_other(profiles, active)
        if not dest:
            abort("unrecognized active profile '%s'" % text)
        activate(store, dest, active)
        return
    if previous and previous != active and previous in known:
        activate(store, previous, active)
        return
    dest = pick_next(profiles, active)
    if not dest:
        abort("unrecognized active profile '%s'" % text)
    activate(store, dest, active)


def do_switch(store, name):
    if not name:
        abort("usage: switch <profile_name>")
    if not name_acceptable(name):
        sys.exit(1)
    _, active, _, _ = describe_current(store)
    if active == name:
        tell("Already on profile '%s'. Nothing to do." % name)
        return
    activate(store, name, active)


def do_save(store, name):
    if not name:
        abort("usage: save <profile_name>")
    if not name_acceptable(name):
        sys.exit(1)
    _, active, _, _ = describe_current(store)
    if store.slot(name).is_file() and not confirm(
        "Profile '%s' already exists. Overwrite?" % name
    ):
        tell("Aborted.")
        return
    snapshot(store, name, active)


def do_delete(store, name, flag=""):
    if not name:
        abort("usage: delete <profile_name> [--yes]")
    if not name_acceptable(name):
        sys.exit(1)
    _, active, _, _ = describe_current(store)
    remove_saved(store, name, active, skip_prompt=flag in ("--yes", "-y", "--force"))


HELP_TEXT = """\
opencode-profiles {version} - manage multiple opencode auth profiles

USAGE
    {prog} [COMMAND] [ARGS]
    (no arguments)         interactive menu

COMMANDS
    list                   list saved profiles, marking the active one
    current                print the active profile name (or status)
    switch <name>          activate a saved profile (copies it to auth.json)
    save <name>            snapshot the current auth.json as <name>
    delete <name> [--yes]  remove a saved profile (asks first unless --yes)
    toggle [a] [b]         flip between profiles:
                             toggle a b  flip between a and b
                             toggle a    flip between current and a
                             toggle      2 profiles: flip to the other;
                                         3+: jump to most-recently-used,
                                         else next in sorted order
    -i                     force the interactive menu
    -h, --help             show this help
    -V, --version          print the version

HOW IT WORKS
    Profiles are snapshots stored next to the live file opencode reads.
    Always quit opencode before switching, then reopen it afterwards.
    Set OPENCODE_PROFILE_BASE_DIR to use a different directory.

EXAMPLES
    {prog} save work
    {prog} switch personal
    {prog} toggle work personal
    {prog} list
""".format


def show_help(prog):
    tell(HELP_TEXT(version=VERSION, prog=prog).rstrip("\n"))


def menu_pick(store):
    profiles = collect_profiles(store)
    _, active, _, _ = describe_current(store)
    if not profiles:
        tell("No saved profiles yet; use 'save' first.")
        return
    for idx, item in enumerate(profiles, start=1):
        tell("%d) %s%s" % (idx, item, "  (active)" if item == active else ""))
    while True:
        choice = ask("Select a profile [1-%d, q]: " % len(profiles))
        if choice is None or choice in ("q", "quit"):
            return
        if not choice.isdigit():
            tell("Enter a number, or q.")
            continue
        num = int(choice)
        if num < 1 or num > len(profiles):
            tell("Enter a number from 1 to %d." % len(profiles))
            continue
        _, live_active, _, _ = describe_current(store)
        activate(store, profiles[num - 1], live_active)
        return


def menu_save(store):
    if not store.live.is_file():
        tell("No auth.json found. Nothing to save.")
        return
    _, active, _, _ = describe_current(store)
    while True:
        if active:
            name = ask("Profile name [%s]: " % active)
        else:
            name = ask("Profile name: ")
        if name is None or name in ("q", "quit"):
            return
        if not name and active:
            name = active
        if not name_acceptable(name or ""):
            continue
        if store.slot(name).is_file():
            answer = ask("Profile '%s' already exists. Overwrite? [y/N]: " % name)
            if answer is None or answer in ("q", "quit"):
                return
            if answer.lower() not in ("y", "yes"):
                continue
        _, live_active, _, _ = describe_current(store)
        snapshot(store, name, live_active)
        return


def menu_delete(store):
    profiles = collect_profiles(store)
    _, active, _, _ = describe_current(store)
    if not profiles:
        tell("No saved profiles yet; nothing to delete.")
        return
    for idx, item in enumerate(profiles, start=1):
        tell("%d) %s%s" % (idx, item, "  (active)" if item == active else ""))
    while True:
        choice = ask("Delete which profile [1-%d, q]: " % len(profiles))
        if choice is None or choice in ("q", "quit"):
            return
        if not choice.isdigit():
            tell("Enter a number, or q.")
            continue
        num = int(choice)
        if num < 1 or num > len(profiles):
            tell("Enter a number from 1 to %d." % len(profiles))
            continue
        _, live_active, _, _ = describe_current(store)
        remove_saved(store, profiles[num - 1], live_active)
        return


def menu_main(store):
    while True:
        _, _, text, _ = describe_current(store)
        tell("")
        tell("=== opencode-profiles ===")
        tell("Base directory : %s" % store.base)
        tell("Current profile: %s" % text)
        tell("")
        tell("1) Switch to a profile")
        tell("2) Save current auth.json as a profile")
        tell("3) Toggle between profiles")
        tell("4) List all profiles")
        tell("5) Delete a profile")
        tell("q) Quit")
        tell("")
        action = ask("Choose an action [1-5, q]: ")
        if action is None:
            action = "q"
        tell("")
        if action == "1":
            menu_pick(store)
        elif action == "2":
            menu_save(store)
        elif action == "3":
            try:
                flip(store)
            except SystemExit:
                tell("Toggle failed (see message above).")
        elif action == "4":
            show_list(store)
        elif action == "5":
            menu_delete(store)
        elif action in ("q", "quit"):
            tell("Goodbye.")
            sys.exit(0)
        else:
            tell("Invalid choice. Enter 1-5 or q.")


def compat_hint(legacy):
    caution("'%s' is a compatibility alias; prefer 'opencode-profiles' (see --help)." % legacy)


def main(argv):
    prog = os.path.basename(argv[0])
    args = argv[1:]
    store = resolve_store()

    if prog.startswith("opencode-switch"):
        if not args or args[0] == "toggle":
            compat_hint(prog)
            rest = args[1:] if args else []
            flip(store, rest[0] if len(rest) > 0 else "",
                 rest[1] if len(rest) > 1 else "")
            return 0
        if args[0] in ("work", "personal") and len(args) == 1:
            compat_hint(prog)
            do_switch(store, args[0])
            return 0
        if args[0] not in ("current", "-h", "--help", "-V", "--version",
                            "list", "switch", "save", "delete", "-i"):
            compat_hint(prog)
        else:
            compat_hint(prog)
    elif prog.startswith("oc-profiles") or prog.startswith("oc-profile"):
        compat_hint(prog)

    cmd = args[0] if args else ""
    rest = args[1:]

    if cmd in ("", "-i"):
        menu_main(store)
    elif cmd == "list":
        show_list(store)
    elif cmd == "current":
        show_current(store)
    elif cmd == "switch":
        do_switch(store, rest[0] if rest else "")
    elif cmd == "save":
        do_save(store, rest[0] if rest else "")
    elif cmd in ("delete", "rm", "remove"):
        do_delete(store, rest[0] if rest else "", rest[1] if len(rest) > 1 else "")
    elif cmd == "toggle":
        flip(store, rest[0] if len(rest) > 0 else "",
             rest[1] if len(rest) > 1 else "")
    elif cmd in ("-h", "--help", "help"):
        show_help(prog)
    elif cmd in ("-V", "--version", "version"):
        tell("opencode-profiles %s" % VERSION)
    else:
        abort("unknown command '%s' (see --help)" % cmd)


if __name__ == "__main__":
    main(sys.argv)
