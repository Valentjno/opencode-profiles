#!/bin/sh
# install.sh — install opencode-profiles (POSIX shell edition).
#
# Installs bin/opencode-profiles to $PREFIX (~/.local/bin by default) and
# creates compatibility symlinks:
#   opencode-switch  -> opencode-profiles (toggle-oriented alias)
#   oc-profiles      -> opencode-profiles (deprecated 1:1 alias)
#   oc-profile       -> opencode-profiles (deprecated 1:1 alias)
#
# Usage:
#   ./install.sh [--prefix DIR] [--no-compat]
#
# Existing profile data (~/.local/share/opencode/) is never touched.

set -eu

PREFIX="$HOME/.local/bin"
LINK_COMPAT=1

while [ $# -gt 0 ]; do
    case $1 in
        --prefix)
            [ -n "${2:-}" ] || { echo "Error: --prefix needs a directory" >&2; exit 1; }
            PREFIX=$2
            shift 2
            ;;
        --prefix=*)
            PREFIX=${1#--prefix=}
            shift
            ;;
        --no-compat)
            LINK_COMPAT=0
            shift
            ;;
        -h|--help)
            sed -n '2,12p' "$0"
            exit 0
            ;;
        *)
            echo "Error: unknown option '$1' (see --help)" >&2
            exit 1
            ;;
    esac
done

HERE=$(dirname "$0")
SRC="$HERE/bin/opencode-profiles"

[ -f "$SRC" ] || { echo "Error: cannot find $SRC; run from the repo root" >&2; exit 1; }

mkdir -p "$PREFIX" || { echo "Error: cannot create $PREFIX" >&2; exit 1; }

cp "$SRC" "$PREFIX/opencode-profiles"
chmod +x "$PREFIX/opencode-profiles"
echo "Installed: $PREFIX/opencode-profiles"

if [ "$LINK_COMPAT" -eq 1 ]; then
    for alias in opencode-switch oc-profiles oc-profile; do
        ln -sf opencode-profiles "$PREFIX/$alias"
        echo "Alias:     $PREFIX/$alias -> opencode-profiles"
    done
fi

case :$PATH: in
    *:"$PREFIX":*) ;;
    *) echo "Note: $PREFIX is not on PATH. Add this to your shell rc:" >&2
       echo "  export PATH=\"\$HOME/.local/bin:\$PATH\"" >&2 ;;
esac

echo "Verify with: opencode-profiles --help"
