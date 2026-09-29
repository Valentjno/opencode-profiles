# Bash completion for opencode-profiles.
#
# Install: copy (or symlink) this file to a bash-completion directory, e.g.
#   mkdir -p ~/.local/share/bash-completion/completions
#   cp completions/opencode-profiles.bash ~/.local/share/bash-completion/completions/opencode-profiles
# and restart your shell. install.sh does not do this automatically.
#
# Completes subcommands, and profile names for switch/toggle/delete/save,
# honouring OPENCODE_PROFILE_BASE_DIR.

_opencode_profiles_list_names() {
    local base="${OPENCODE_PROFILE_BASE_DIR:-$HOME/.local/share/opencode}"
    local f name
    for f in "$base"/auth-*.json; do
        [ -f "$f" ] || continue
        name=$(basename "$f")
        name=${name#auth-}
        name=${name%.json}
        printf '%s\n' "$name"
    done 2>/dev/null
}

_opencode_profiles() {
    local cur prev cmds
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev=""
    if [ "$COMP_CWORD" -ge 1 ]; then
        prev="${COMP_WORDS[COMP_CWORD-1]}"
    fi
    cmds="list current switch save delete toggle -i -h --help -V --version"

    # `toggle <a> <b>`: complete the second name too.
    if [ "$COMP_CWORD" -eq 3 ] && [ "${COMP_WORDS[1]}" = "toggle" ]; then
        COMPREPLY=($(compgen -W "$(_opencode_profiles_list_names)" -- "$cur"))
        return 0
    fi

    case "$prev" in
        switch|save|toggle)
            COMPREPLY=($(compgen -W "$(_opencode_profiles_list_names)" -- "$cur"))
            return 0
            ;;
        delete)
            COMPREPLY=($(compgen -W "$(_opencode_profiles_list_names) --yes" -- "$cur"))
            return 0
            ;;
    esac

    if [ "$COMP_CWORD" -eq 1 ]; then
        COMPREPLY=($(compgen -W "$cmds" -- "$cur"))
        return 0
    fi
}

complete -F _opencode_profiles opencode-profiles opencode-switch oc-profiles oc-profile
