#!/usr/bin/env bash
# Promote a published beta build to the stable channel everywhere.
#
# Usage: ./scripts/release/promote.sh <build-number> [--rollout FRACTION] [--bump patch|minor|major]
#
# Thin wrapper over the Promote Beta workflow (.github/workflows/promote.yml):
# verifies the beta exists and shows what will be promoted before dispatching.

set -euo pipefail

BUILD="${1:?Usage: promote.sh <build-number> [--rollout FRACTION] [--bump patch|minor|major]}"
shift
ROLLOUT="1.0"
BUMP="patch"
while [ $# -gt 0 ]; do
  case "$1" in
    --rollout) ROLLOUT="$2"; shift 2 ;;
    --bump) BUMP="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

TAG=$(gh release list --repo submersion-app/beta-builds --json tagName \
  -q ".[].tagName" | grep -E "\.${BUILD}$" | head -1)
if [ -z "$TAG" ]; then
  echo "Error: no beta release ending in .${BUILD} found in beta-builds." >&2
  exit 1
fi

BLOCKERS=$(gh issue list --repo submersion-app/submersion \
  --label beta-blocker --state open --json number -q 'length')
if [ "$BLOCKERS" != "0" ]; then
  echo "Error: $BLOCKERS open beta-blocker issue(s). Resolve before promoting." >&2
  exit 1
fi

echo "About to promote $TAG to stable (Play rollout $ROLLOUT, next bump: $BUMP)."
read -r -p "Continue? [y/N] " answer
[ "$answer" = "y" ] || { echo "Aborted."; exit 1; }

gh workflow run promote.yml \
  -f build-number="$BUILD" -f play-rollout="$ROLLOUT" -f next-bump="$BUMP"
echo "Dispatched. Watch with:"
echo "  gh run watch \$(gh run list --workflow=promote.yml --limit 1 --json databaseId -q '.[0].databaseId')"
