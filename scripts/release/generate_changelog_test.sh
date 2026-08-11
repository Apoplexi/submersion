#!/usr/bin/env bash
# Tests for generate_changelog.sh --notes-only, the Sparkle/appcast release
# notes path. Its stdout is piped into generate_release_notes_html.sh and
# published inside the update dialog, so progress output must stay on stderr:
# the v1.7.2.4977 appcast shipped "Changelog: 1.7.2 (commits since ...)" and
# "Found 82 commit(s) in 7 section(s)." as the opening lines of the notes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GEN="$SCRIPT_DIR/generate_changelog.sh"

fail() { echo "FAIL: $1"; exit 1; }

# Build a scratch repository with a tagged release and conventional commits
# after it, mirroring the state the release workflow runs from.
TMPREPO=$(mktemp -d)
trap 'rm -rf "$TMPREPO"' EXIT
(
  cd "$TMPREPO"
  git init -q
  git -c user.name=t -c user.email=t@t commit -q --allow-empty -m "chore: initial"
  git tag v1.0.0.1
  git -c user.name=t -c user.email=t@t commit -q --allow-empty -m "feat: a new thing"
  git -c user.name=t -c user.email=t@t commit -q --allow-empty -m "fix: an old thing"
)

STDOUT=$(cd "$TMPREPO" && "$GEN" --notes-only 2>/dev/null)
STDERR=$(cd "$TMPREPO" && "$GEN" --notes-only 2>&1 >/dev/null)

# Progress lines belong on stderr, never in the published notes body.
echo "$STDOUT" | grep -qiE '^(changelog:|found |generating|nothing to generate)' \
  && fail "progress output leaked onto --notes-only stdout"

# The notes must start with the version heading, not blank filler or noise.
[ -n "$STDOUT" ] || fail "--notes-only produced no output"
echo "$STDOUT" | head -1 | grep -q '^## ' \
  || fail "--notes-only does not start with the version heading"

# The commit content itself must be present.
echo "$STDOUT" | grep -q "a new thing" || fail "feat commit missing from notes"
echo "$STDOUT" | grep -q "an old thing" || fail "fix commit missing from notes"

# The progress lines still exist for humans running the script interactively.
echo "$STDERR" | grep -q "^Changelog: " || fail "progress summary missing from stderr"
echo "$STDERR" | grep -q "commit(s) in" || fail "commit count missing from stderr"

echo "PASS: all generate_changelog tests passed"
