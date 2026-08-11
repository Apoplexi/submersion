#!/usr/bin/env bash
# Build the tester-facing "what to test" text for a beta build.
#
# The per-merge beta pipeline previously handed TestFlight and Play a fixed
# string ("Beta vX - automated per-merge build"), so testers had no way to tell
# what any given beta actually changed. This script turns the commit range
# between two betas into notes the stores will accept.
#
# Store fields have hard limits that differ per platform, and exceeding them
# fails the upload rather than truncating: Apple's TestFlight whatsNew caps at
# 4000 characters, Google Play's release notes at 500 per locale. Each format
# caps itself and says how many items it dropped.
#
# Usage:
#   beta_release_notes.sh --since <sha> --format store    # <sha>..HEAD
#   beta_release_notes.sh --range <gitrange> --format play
#   beta_release_notes.sh --stdin --format markdown       # subjects on stdin
#
# An empty --since falls back to the last tag, so the first beta of a release
# still produces real notes.
#
# Formats:
#   store     TestFlight whatsNew (plain text, 4000 chars)
#   play      Play release notes (plain text, 500 chars)
#   markdown  GitHub beta release body (uncapped, keeps internal work)
#
# --cumulative (markdown only) appends a second section covering everything
# since the last production tag, for a tester coming straight from the public
# release rather than from the previous beta.
#
# All progress and diagnostics go to stderr; stdout is only ever the notes.
set -euo pipefail

STORE_LIMIT=4000
PLAY_LIMIT=500
# Room for the "...and N more." line appended after truncation.
TRUNCATION_RESERVE=24

# Held in variables and used unquoted: bash silently fails to match a regex
# written inline with an escaped trailing space, matching 2 of 120 real PR
# titles where the same expression in grep -E matched 49.
CONVENTIONAL_RE='^[a-z]+(\([^)]*\))?!?: '
FIX_VERB_RE='^(Fix|Fixes|Fixed|Stop|Stops|Resolve|Resolves|Correct|Corrects|Prevent|Prevents|Repair|Repairs|Restore|Restores) '

RANGE=""
FORMAT=""
USE_STDIN=false
SINCE=""
SINCE_GIVEN=false
CUMULATIVE=false

die() { echo "beta_release_notes: $1" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --range)  RANGE="${2:-}"; shift 2 ;;
    --since)  SINCE="${2:-}"; SINCE_GIVEN=true; shift 2 ;;
    --stdin)  USE_STDIN=true; shift ;;
    --cumulative) CUMULATIVE=true; shift ;;
    --format) FORMAT="${2:-}"; shift 2 ;;
    --help|-h)
      sed -nE '2,/^$/s/^# ?//p' "$0"
      exit 0
      ;;
    *) die "unknown argument: $1" ;;
  esac
done

case "$FORMAT" in
  store|play|markdown) ;;
  "") die "--format is required (store, play, or markdown)" ;;
  *)  die "unknown --format: $FORMAT (expected store, play, or markdown)" ;;
esac

# --since takes the previous beta's commit and turns it into a range. The
# pipeline knows that commit but not a git range, and on the very first beta it
# knows nothing: an empty value falls back to the last tag so the first beta
# still gets real notes instead of an error.
if [ "$SINCE_GIVEN" = true ]; then
  if [ -n "$SINCE" ]; then
    RANGE="${SINCE}..HEAD"
  else
    # Restricted to the app's own 4-segment tags (vX.Y.Z.BUILD). The repo also
    # carries Flutter's upstream tags, and an unfiltered describe can land on
    # one of those, producing a range of thousands of unrelated commits.
    LAST_TAG=$(git describe --tags --abbrev=0 --match 'v*.*.*.*' 2>/dev/null || echo "")
    if [ -n "$LAST_TAG" ]; then
      echo "No previous beta given; falling back to tag ${LAST_TAG}." >&2
      RANGE="${LAST_TAG}..HEAD"
    else
      echo "No previous beta and no tags; using full history." >&2
      RANGE="HEAD"
    fi
  fi
fi

if [ "$USE_STDIN" = false ] && [ -z "$RANGE" ]; then
  die "one of --range <gitrange>, --since <sha>, or --stdin is required"
fi

# The store formats have a few hundred to a few thousand characters to spend on
# this build alone; a second, longer section would only crowd out the delta the
# tester is being asked to exercise.
if [ "$CUMULATIVE" = true ] && [ "$FORMAT" != markdown ]; then
  die "--cumulative applies to --format markdown only (got: $FORMAT)"
fi

# --- Sort subjects into tester-facing buckets -------------------------------
#
# Only feat/fix/perf describe something a tester can exercise. Everything else
# (chore, ci, docs, test, refactor, unconventional subjects) is internal: it is
# kept for the GitHub release body but withheld from the store fields, where
# the character budget is scarce and the audience is not the development team.

FEATURES=""
FIXES=""
IMPROVEMENTS=""
INTERNAL=""

append_line() {
  # $1 = current value, $2 = line. Emits the new value.
  if [ -z "$1" ]; then printf '%s' "$2"; else printf '%s\n%s' "$1" "$2"; fi
}

# Collapse duplicate subjects, preserving first-seen order. Cherry-picks and
# revert/reapply pairs otherwise list the same line several times.
dedupe() {
  [ -n "$1" ] || return 0
  printf '%s\n' "$1" | awk '!seen[$0]++'
}

# Fills the four bucket variables from the subjects passed as $1. Called more
# than once in cumulative mode, so it resets the buckets on entry.
classify_subjects() {
  FEATURES=""
  FIXES=""
  IMPROVEMENTS=""
  INTERNAL=""

  while IFS= read -r subject; do
    [ -n "$subject" ] || continue
    message=$(printf '%s' "$subject" | sed -E 's/^[a-z]+(\([^)]*\))?!?: *//')
    case "$subject" in
      feat\(*\)*:*|feat:*|feat!:*|feat\(*\)!:*)
        FEATURES=$(append_line "$FEATURES" "$message") ;;
      fix\(*\)*:*|fix:*|fix!:*|fix\(*\)!:*)
        FIXES=$(append_line "$FIXES" "$message") ;;
      perf\(*\)*:*|perf:*|perf!:*|perf\(*\)!:*)
        IMPROVEMENTS=$(append_line "$IMPROVEMENTS" "$message") ;;
      *)
        # Everything that is not feat/fix/perf. A subject with any other
        # conventional prefix (chore, ci, docs, test, refactor, build, style)
        # is internal by definition. A subject without one is a prose PR
        # title, which is real tester-facing work, so it is bucketed by its
        # leading verb rather than dropped.
        #
        # An infrastructure PR titled in prose therefore surfaces as
        # tester-facing. That is the deliberate direction of the error: the
        # defect being fixed is under-reporting, and prefixing the PR title
        # "ci:" keeps it internal when that is wanted.
        if [[ "$subject" =~ $CONVENTIONAL_RE ]]; then
          INTERNAL=$(append_line "$INTERNAL" "$message")
        elif [[ "$subject" =~ $FIX_VERB_RE ]]; then
          FIXES=$(append_line "$FIXES" "$message")
        else
          FEATURES=$(append_line "$FEATURES" "$message")
        fi
        ;;
    esac
  done <<EOF
$1
EOF

  FEATURES=$(dedupe "$FEATURES")
  FIXES=$(dedupe "$FIXES")
  IMPROVEMENTS=$(dedupe "$IMPROVEMENTS")
  INTERNAL=$(dedupe "$INTERNAL")
}

subjects_in_range() {
  echo "Reading commits in ${1}..." >&2
  # Walk the first-parent line of main. Each entry is either a PR merge, whose
  # body's first line is the PR title, or a commit made straight to main.
  #
  # A --no-merges walk read the PR branch's own commits instead, which are
  # working notes ("address review feedback") and mostly carry no conventional
  # prefix, so they were bucketed as internal and never reached the stores.
  #
  # --first-parent also excludes merges made *inside* a PR branch, so a
  # branch-sync merge ("Merge origin/main into <branch>") needs no special
  # case: it is not on this line.
  #
  # Records are separated by \001 and fields by \002 because a commit body is
  # multi-line and may contain anything else.
  git log --first-parent --format='%x01%P%x02%s%x02%b' "$1" | awk '
    BEGIN { RS = "\001"; FS = "\002" }
    NF < 3 { next }
    {
      parents = $1
      subject = $2
      body = $3
      if (parents ~ / /) {
        # More than one parent: a merge. Only GitHub PR merges describe user
        # work; anything else on this line is a manual merge and is skipped.
        if (subject !~ /^Merge pull request #/) next
        n = split(body, line, "\n")
        for (i = 1; i <= n; i++)
          if (line[i] ~ /[^ \t\r]/) { print line[i]; break }
      } else {
        print subject
      }
    }
  '
}

# --- Collect commit subjects ------------------------------------------------

if [ "$USE_STDIN" = true ]; then
  SUBJECTS=$(cat)
else
  SUBJECTS=$(subjects_in_range "$RANGE")
fi

classify_subjects "$SUBJECTS"

# --- Markdown: the GitHub beta release body ---------------------------------

render_markdown() {
  local emitted=false
  emit_section() {
    [ -n "$2" ] || return 0
    [ "$emitted" = true ] && echo ""
    echo "### $1"
    echo ""
    printf '%s\n' "$2" | sed 's/^/- /'
    emitted=true
  }
  emit_section "New features" "$FEATURES"
  emit_section "Bug fixes" "$FIXES"
  emit_section "Performance" "$IMPROVEMENTS"
  emit_section "Internal" "$INTERNAL"
  [ "$emitted" = true ] || echo "$1"
}

if [ "$FORMAT" = markdown ]; then
  # Without --cumulative the body is exactly this beta's delta.
  if [ "$CUMULATIVE" = false ]; then
    render_markdown "No changes recorded since the previous beta."
    exit 0
  fi

  # With it, the per-beta delta is the headline and a second section carries
  # everything since the last production release, for a tester arriving
  # straight from the public build. Only the app's own 4-segment tags count as
  # a production release; the repo also carries Flutter's upstream tags.
  STABLE_TAG=$(git describe --tags --abbrev=0 --match 'v*.*.*.*' 2>/dev/null || echo "")

  if [ -z "$STABLE_TAG" ]; then
    echo "No production tag found; omitting the cumulative section." >&2
    render_markdown "No changes recorded since the previous beta."
    exit 0
  fi

  echo "## New in this beta"
  echo ""
  render_markdown "No changes recorded since the previous beta."
  echo ""
  echo "## Everything since $STABLE_TAG"
  echo ""
  classify_subjects "$(subjects_in_range "${STABLE_TAG}..HEAD")"
  render_markdown "No changes recorded since $STABLE_TAG."
  exit 0
fi

# --- Store formats: plain text within a hard character budget ---------------

if [ "$FORMAT" = play ]; then LIMIT=$PLAY_LIMIT; else LIMIT=$STORE_LIMIT; fi

# Build the full untruncated line list, tagging item lines so truncation can
# report how many were dropped and so a heading is never left dangling.
LINES=""
add() { LINES=$(append_line "$LINES" "$1"); }

add_section() {
  [ -n "$2" ] || return 0
  [ -n "$LINES" ] && add "H:"
  add "H:$1"
  while IFS= read -r item; do
    [ -n "$item" ] && add "I:- $item"
  done <<EOF
$2
EOF
}

add_section "New in this build" "$FEATURES"
add_section "Improved" "$IMPROVEMENTS"
add_section "Fixed" "$FIXES"

if [ -z "$LINES" ]; then
  if [ -n "$INTERNAL" ]; then
    echo "This build contains internal changes only - build, CI, refactoring," \
      "and test work. Please retest your usual workflows and report anything" \
      "that behaves differently."
  else
    echo "This beta matches the previous build; no new changes were recorded."
  fi
  exit 0
fi

# Accumulate lines until the next one would breach the budget, then keep
# scanning to count the items left out.
OUT=""
dropped=0
truncated=false

while IFS= read -r tagged; do
  kind="${tagged%%:*}"
  line="${tagged#*:}"

  if [ "$truncated" = true ]; then
    [ "$kind" = "I" ] && dropped=$((dropped + 1))
    continue
  fi

  if [ -z "$OUT" ]; then candidate="$line"; else candidate="$OUT"$'\n'"$line"; fi
  if [ "${#candidate}" -gt $((LIMIT - TRUNCATION_RESERVE)) ]; then
    truncated=true
    [ "$kind" = "I" ] && dropped=$((dropped + 1))
    continue
  fi
  OUT="$candidate"
done <<EOF
$LINES
EOF

# Truncation can leave a heading with nothing under it, which reads as though
# that section were empty rather than cut.
while [ -n "$OUT" ]; do
  last="${OUT##*$'\n'}"
  case "$last" in
    "- "*) break ;;
    *) if [ "$last" = "$OUT" ]; then OUT=""; else OUT="${OUT%$'\n'*}"; fi ;;
  esac
done

if [ "$dropped" -gt 0 ]; then
  if [ -n "$OUT" ]; then
    OUT="$OUT"$'\n'"...and $dropped more."
  else
    OUT="...and $dropped more."
  fi
fi

printf '%s\n' "$OUT"
