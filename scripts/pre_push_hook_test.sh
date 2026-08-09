#!/bin/bash
#
# Tests for hooks/pre-push.
#
# Both regressions covered here caused the same user-visible symptom -- a push
# rejected for reasons that had nothing to do with the change being pushed --
# and both are invisible to `bash -n`, so they need an executable test.
#
# No Flutter or Dart toolchain is required: `dart` and `flutter` are stubbed on
# PATH, and DRY_RUN=1 stops the hook before it would run a test suite. That
# keeps this runnable in the CI script-tests job, which has no Flutter.
#
# Usage: bash scripts/pre_push_hook_test.sh

set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK_SRC="$REPO_ROOT/hooks/pre-push"
ZERO="0000000000000000000000000000000000000000"

failures=0

pass() { printf 'ok   - %s\n' "$1"; }
fail() {
    printf 'FAIL - %s\n' "$1"
    if [ -n "${2:-}" ]; then
        printf '       %s\n' "$2"
    fi
    failures=$((failures + 1))
}

# Build a repo whose layout mirrors the real one: a main checkout that owns
# hooks/, plus a linked worktree on its own branch. Echoes the temp dir.
#
# $1 is a lib file added on the worktree branch but with NO mirrored test, used
# by the silent-abort case; pass an empty string to skip it. Its name must sort
# AFTER 'sample' -- see the ordering note on test 2.
make_fixture() {
    orphan_lib="$1"

    tmp="$(mktemp -d)"
    main_tree="$tmp/main"

    mkdir -p "$main_tree"
    cd "$main_tree" || exit 1

    git init -q -b main .
    git config user.email 'test@example.com'
    git config user.name 'Test'
    git config commit.gpgsign false

    mkdir -p lib test hooks
    printf '// lib\n' > lib/sample.dart
    printf "import 'package:submersion/sample.dart';\n" > test/sample_test.dart
    git add -A
    git commit -q -m 'initial'

    # The hook lives in the MAIN checkout only. core.hooksPath is an absolute
    # path in the real repo, so every worktree executes this exact file.
    cp "$HOOK_SRC" "$main_tree/hooks/pre-push"
    chmod +x "$main_tree/hooks/pre-push"

    git worktree add -q "$tmp/wt" -b feature
    cd "$tmp/wt" || exit 1
    printf '// changed on the branch\n' >> lib/sample.dart
    if [ -n "$orphan_lib" ]; then
        printf '// no mirrored test exists for this file\n' > "lib/$orphan_lib.dart"
    fi
    git add -A
    git commit -q -m 'change on feature'

    # Stub the toolchain. `flutter` records the directory it was called from --
    # that is the assertion target for the wrong-tree regression.
    mkdir -p "$tmp/bin"
    printf '#!/bin/bash\npwd -P >> "$CWD_LOG"\nexit 0\n' > "$tmp/bin/flutter"
    printf '#!/bin/bash\nexit 0\n' > "$tmp/bin/dart"
    chmod +x "$tmp/bin/flutter" "$tmp/bin/dart"

    printf '%s\n' "$tmp"
}

# Run the main checkout's hook with the worktree as the working directory,
# feeding it a ref line the way git does for a brand-new branch (all-zero
# remote sha). Sets: hook_status, hook_output, analyze_cwd.
run_hook() {
    tmp="$1"

    cd "$tmp/wt" || exit 1
    : > "$tmp/cwd.log"

    printf 'refs/heads/feature %s refs/heads/feature %s\n' \
        "$(git rev-parse HEAD)" "$ZERO" > "$tmp/refline"

    hook_output="$(PATH="$tmp/bin:$PATH" CWD_LOG="$tmp/cwd.log" DRY_RUN=1 \
        /bin/bash "$tmp/main/hooks/pre-push" < "$tmp/refline" 2>&1)"
    hook_status=$?

    analyze_cwd="$(head -1 "$tmp/cwd.log" 2>/dev/null || true)"
}

# --- Test 1: the checks must run against the tree being pushed --------------
#
# Regression: PROJECT_ROOT was derived from "$0", which with an absolute
# core.hooksPath always resolves into the main checkout. Every worktree push
# therefore formatted, analyzed and tested the main checkout instead.

tmp="$(make_fixture '')"
run_hook "$tmp"

want="$(cd "$tmp/wt" && pwd -P)"
notwant="$(cd "$tmp/main" && pwd -P)"

if [ "$analyze_cwd" = "$want" ]; then
    pass 'runs the checks in the worktree being pushed'
elif [ "$analyze_cwd" = "$notwant" ]; then
    fail 'runs the checks in the worktree being pushed' \
        "ran in the main checkout ($analyze_cwd) instead of the worktree"
else
    fail 'runs the checks in the worktree being pushed' \
        "expected '$want', flutter ran in '$analyze_cwd'"
fi

if [ "$hook_status" -eq 0 ]; then
    pass 'exits 0 for a clean push'
else
    fail 'exits 0 for a clean push' "exit $hook_status: $hook_output"
fi

rm -rf "$tmp"

# --- Test 2: a missing mirrored test path must not abort the hook -----------
#
# Regression: the resolver ended with `[ -f "$t" ] && printf ...` as the last
# statement of a while loop inside $(...). A false test on the final iteration
# propagated 1 out through the substitution to the assignment, and set -e then
# killed the hook with no message -- git reported only "failed to push some
# refs". lib/X.dart -> test/X_test.dart is a guess, so missing paths are normal.
#
# ORDERING MATTERS. Candidates are piped through `sort -u`, and only the LAST
# iteration's exit status escapes the loop. The missing path must therefore sort
# after every existing one, hence the 'zzz_' prefix: named so it sorted before
# 'sample', the loop would end on the existing test/sample_test.dart, return 0,
# and this test would pass against the buggy hook while proving nothing.

tmp="$(make_fixture 'zzz_orphan')"
run_hook "$tmp"

if [ "$hook_status" -eq 0 ]; then
    pass 'survives a changed lib file whose mirrored test does not exist'
else
    fail 'survives a changed lib file whose mirrored test does not exist' \
        "hook exited $hook_status; output: $hook_output"
fi

case "$hook_output" in
    *DRY_RUN*)
        pass 'reaches the test-resolution stage instead of aborting early'
        ;;
    *)
        fail 'reaches the test-resolution stage instead of aborting early' \
            "output did not mention DRY_RUN: $hook_output"
        ;;
esac

rm -rf "$tmp"

# --- Summary ---------------------------------------------------------------

if [ "$failures" -eq 0 ]; then
    printf '\nAll pre-push hook tests passed.\n'
    exit 0
fi

printf '\n%d pre-push hook test(s) failed.\n' "$failures"
exit 1
