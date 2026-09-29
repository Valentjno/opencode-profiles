#!/bin/sh
# uninstall.sh — remove an install.sh installation.
# Only removes the program files; profile data is never touched.

set -eu

PREFIX="${1:-$HOME/.local/bin}"
case $1 in
    --prefix)
        PREFIX="${2:-$HOME/.local/bin}"
        ;;
    --prefix=*)
        PREFIX=${1#--prefix=}
        ;;
esac

for name in opencode-profiles opencode-switch oc-profiles oc-profile; do
    target="$PREFIX/$name"
    if [ -e "$target" ] || [ -L "$target" ]; then
        rm -f "$target" && echo "Removed: $target"
    else
        echo "Skip (absent): $target"
    fi
done

echo "Profile data left intact. To also delete snapshots, see README 'Uninstalling'."
