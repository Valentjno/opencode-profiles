#!/bin/sh
# tests/test_sh.sh — smoke suite for bin/opencode-profiles (POSIX sh).
#
# Runs entirely inside a throwaway OPENCODE_PROFILE_BASE_DIR, so the real
# ~/.local/share/opencode is never touched.
#
# Usage: sh tests/test_sh.sh

PASS=0
FAIL=0

HERE=$(dirname "$0")
BIN="$HERE/../bin/opencode-profiles"

TMPD=$(mktemp -d) || { echo 'cannot create temp dir' >&2; exit 1; }
export OPENCODE_PROFILE_BASE_DIR="$TMPD"
trap 'rm -rf "$TMPD"' EXIT INT TERM

ok() {
    PASS=$((PASS + 1))
    printf 'ok   %s\n' "$1"
}

bad() {
    FAIL=$((FAIL + 1))
    printf 'FAIL %s\n' "$1"
    printf '     %s\n' "$2"
}

# run2 <var_out> <var_rc> -- cmd...  (stderr discarded: pgrep may see CI)
run2() {
    _o=$1
    _r=$2
    shift 2
    # shellcheck disable=SC2145
    _out=$("$@" 2>/dev/null)
    _rc=$?
    eval "$_o=\$_out"
    eval "$_r=\$_rc"
}

expect_out() {
    # expect_out <label> <expected> <actual>
    if [ "$2" = "$3" ]; then
        ok "$1"
    else
        bad "$1" "expected [$2] got [$3]"
    fi
}

expect_rc() {
    # expect_rc <label> <expected_rc> <actual_rc>
    if [ "$2" = "$3" ]; then
        ok "$1"
    else
        bad "$1" "expected rc $2 got $3"
    fi
}

# 1. save two profiles -------------------------------------------------------
printf '{"by":"t-work"}' > "$TMPD/auth.json"
run2 OUT RC "$BIN" save work
expect_rc 'save work rc' 0 "$RC"

printf '{"by":"t-personal"}' > "$TMPD/auth.json"
run2 OUT RC "$BIN" save personal
expect_rc 'save personal rc' 0 "$RC"

# 2. current reports the last saved ------------------------------------------
run2 OUT RC "$BIN" current
expect_out 'current == personal' 'personal' "$OUT"

# 3. list marks the active one -----------------------------------------------
run2 OUT RC "$BIN" list
case $OUT in
    *'* personal  (active)'*work*) ok 'list marks active' ;;
    *) bad 'list marks active' "$OUT" ;;
esac

# 4. switch copies bytes ------------------------------------------------------
run2 OUT RC "$BIN" switch work
expect_rc 'switch work rc' 0 "$RC"
expect_out 'live bytes after switch' '{"by":"t-work"}' "$(cat "$TMPD/auth.json")"

# 5. switch to same profile is a no-op ----------------------------------------
run2 OUT RC "$BIN" switch work
case $OUT in
    *'Already on profile'*) ok 're-switch no-op' ;;
    *) bad 're-switch no-op' "$OUT" ;;
esac

# 6. bare toggle flips the pair -----------------------------------------------
run2 OUT RC "$BIN" toggle
expect_rc 'toggle rc' 0 "$RC"
expect_out 'live bytes after toggle' '{"by":"t-personal"}' "$(cat "$TMPD/auth.json")"
run2 OUT RC "$BIN" toggle
expect_out 'toggle flips back' '{"by":"t-work"}' "$(cat "$TMPD/auth.json")"

# 7. explicit pair toggle ------------------------------------------------------
run2 OUT RC "$BIN" toggle work personal
run2 CUR RC2 "$BIN" current
expect_out 'toggle pair lands personal' 'personal' "$CUR"
run2 OUT RC "$BIN" toggle work personal
run2 CUR RC2 "$BIN" current
expect_out 'toggle pair flips work' 'work' "$CUR"

# 8. single-name toggle ---------------------------------------------------------
run2 OUT RC "$BIN" toggle personal
run2 CUR RC2 "$BIN" current
expect_out 'toggle single goes personal' 'personal' "$CUR"
run2 OUT RC "$BIN" toggle personal
run2 CUR RC2 "$BIN" current
expect_out 'toggle single returns (MRU)' 'work' "$CUR"

# 9. overwrite guard: 'n' keeps bytes -------------------------------------------
printf '{"by":"t-new"}' > "$TMPD/auth.json"
printf 'n\n' | "$BIN" save work >/dev/null 2>&1
expect_out 'overwrite declined keeps snapshot' '{"by":"t-work"}' "$(cat "$TMPD/auth-work.json")"

# 10. overwrite guard: 'y' replaces ------------------------------------------------
printf 'y\n' | "$BIN" save work >/dev/null 2>&1
expect_out 'overwrite accepted replaces snapshot' '{"by":"t-new"}' "$(cat "$TMPD/auth-work.json")"

# 11. invalid name rejected -------------------------------------------------------
run2 OUT RC "$BIN" save 'bad name'
if [ "$RC" -ne 0 ]; then ok 'invalid name rc'; else bad 'invalid name rc' "rc=$RC"; fi

# 12. unknown profile errors -------------------------------------------------------
run2 OUT RC "$BIN" switch nosuch
if [ "$RC" -ne 0 ]; then ok 'unknown switch rc'; else bad 'unknown switch rc' "rc=$RC"; fi
OUT2=$("$BIN" switch nosuch 2>&1)
case $OUT2 in
    *'Error:'*) ok 'unknown switch message' ;;
    *) bad 'unknown switch message' "$OUT2" ;;
esac

# 13. delete with --yes --------------------------------------------------------------
run2 OUT RC "$BIN" delete personal --yes
expect_rc 'delete rc' 0 "$RC"
if [ ! -f "$TMPD/auth-personal.json" ]; then ok 'snapshot file gone'; else bad 'snapshot file gone' 'still exists'; fi

# 14. single remaining profile: toggle is a no-op --------------------------------------
run2 OUT RC "$BIN" toggle
case $OUT in
    *'Nothing to do'*) ok 'single-profile toggle no-op' ;;
    *) bad 'single-profile toggle no-op' "$OUT" ;;
esac

# 15. delete the active profile drops the pointer, keeps live bytes ----------------------
printf '{"by":"keep-me"}' > "$TMPD/auth.json"
run2 OUT RC "$BIN" save solo
cp "$TMPD/auth.json" "$TMPD/live.before"
run2 OUT RC "$BIN" delete solo --yes
expect_rc 'delete active rc' 0 "$RC"
if cmp -s "$TMPD/live.before" "$TMPD/auth.json"; then ok 'live bytes kept'; else bad 'live bytes kept' 'changed'; fi
run2 OUT RC "$BIN" current
case $OUT in
    unknown*) ok 'pointer dropped' ;;
    *) bad 'pointer dropped' "$OUT" ;;
esac

# 16. 3-profile MRU cycling ------------------------------------------------------------------
printf '{"by":"A"}' > "$TMPD/auth.json"; "$BIN" save alpha >/dev/null 2>&1
printf '{"by":"B"}' > "$TMPD/auth.json"; "$BIN" save beta >/dev/null 2>&1
printf '{"by":"C"}' > "$TMPD/auth.json"; "$BIN" save gamma >/dev/null 2>&1
"$BIN" switch alpha >/dev/null 2>&1
"$BIN" switch beta >/dev/null 2>&1
"$BIN" toggle >/dev/null 2>&1
run2 CUR RC2 "$BIN" current
expect_out 'MRU toggle returns alpha' 'alpha' "$CUR"

# 17. help / version --------------------------------------------------------------------------------
run2 OUT RC "$BIN" --help
expect_rc 'help rc' 0 "$RC"
run2 OUT RC "$BIN" --version
case $OUT in
    *'1.0.0'*) ok 'version string' ;;
    *) bad 'version string' "$OUT" ;;
esac

# 18. legacy alias behaviour -----------------------------------------------------------------------------
mkdir -p "$TMPD/links"
ln -sf "$BIN" "$TMPD/links/opencode-switch"
run2 OUT RC "$TMPD/links/opencode-switch" current
expect_out 'alias current passthrough' 'alpha' "$OUT"
run2 OUT RC "$TMPD/links/opencode-switch" toggle alpha beta
run2 CUR RC2 "$BIN" current
expect_out 'alias toggle works' 'beta' "$CUR"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
