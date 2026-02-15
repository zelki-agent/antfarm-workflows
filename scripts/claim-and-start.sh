#!/bin/bash
# Atomic claim + graph update
# Usage: claim-and-start.sh <repo-owner/repo> <issue-number>

set -euo pipefail

REPO="$1"
ISSUE_NUM="$2"
REPO_PATH="${3:-.}"

echo "🎯 Atomically claiming issue #$ISSUE_NUM..."

# 1. Query graph to get story details
git fetch origin main
STORY_JSON=$(git show origin/main:dependency-graph.json | jq --arg issue "$ISSUE_NUM" '.stories[] | select(.issue_number == ($issue | tonumber))')

if [ -z "$STORY_JSON" ]; then
  echo "❌ Story not found in dependency graph for issue #$ISSUE_NUM"
  exit 1
fi

STORY_ID=$(echo "$STORY_JSON" | jq -r '.id')
STORY_STATUS=$(echo "$STORY_JSON" | jq -r '.status')

# Check if story is ready
if [ "$STORY_STATUS" != "ready" ] && [ "$STORY_STATUS" != "pending" ]; then
  echo "❌ Story $STORY_ID is not ready (status: $STORY_STATUS)"
  exit 1
fi

# 2. Attempt to claim issue (atomic via GitHub API)
echo "📌 Claiming issue..."
if ! gh issue edit $ISSUE_NUM --repo $REPO --add-assignee "@me" --add-label "🟢 workflow-active"; then
  echo "❌ Failed to claim issue (already assigned or insufficient permissions)"
  exit 1
fi

echo "✅ Issue claimed"

# 3. Update graph on main branch
echo "📊 Updating dependency graph on main..."

cd "$REPO_PATH"

# Create temp branch from main
TEMP_BRANCH="temp-claim-$(date +%s)-$$"
git fetch origin main
git checkout -b "$TEMP_BRANCH" origin/main

# Update graph
jq --arg story_id "$STORY_ID" '
  (.stories[] | select(.id == $story_id) | .status) = "in_progress" |
  .in_progress += [$story_id] |
  .ready_to_pick -= [$story_id] |
  .in_progress |= unique |
  .ready_to_pick |= unique
' dependency-graph.json > dependency-graph.json.tmp

mv dependency-graph.json.tmp dependency-graph.json

# Commit to main
git add dependency-graph.json
git commit -m "chore: Claim $STORY_ID (issue #$ISSUE_NUM) - mark in_progress

Atomically claimed issue and updated dependency graph.

Run ID: ${ANTFARM_RUN_ID:-unknown}
Claimed by: $(git config user.name)
Timestamp: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"

# Push to main
if ! git push origin HEAD:main; then
  echo "❌ Failed to push graph update to main"
  echo "⚠️  Rolling back issue assignment..."
  gh issue edit $ISSUE_NUM --repo $REPO --remove-assignee "@me" --remove-label "🟢 workflow-active"
  git checkout -
  git branch -D "$TEMP_BRANCH"
  exit 1
fi

echo "✅ Graph updated on main"

# Clean up
git checkout -
git branch -D "$TEMP_BRANCH"

# Return story details
echo ""
echo "✅ Successfully claimed $STORY_ID"
echo "$STORY_JSON"

exit 0
