#!/bin/bash
# Mark story as completed (called by verifier after successful verification)
# Usage: complete-story.sh <story-id> <pr-number> [repo-path]

set -euo pipefail

STORY_ID="$1"
PR_NUM="${2:-none}"
REPO_PATH="${3:-.}"

echo "✅ Marking $STORY_ID as completed..."

cd "$REPO_PATH"

# Create temp branch from main
TEMP_BRANCH="temp-complete-$(date +%s)-$$"
git fetch origin main
git checkout -b "$TEMP_BRANCH" origin/main

# Backup graph
cp dependency-graph.json dependency-graph.json.bak

# Update graph: mark completed, recalculate ready tasks
jq --arg story_id "$STORY_ID" '
  # Mark story as completed
  (.stories[] | select(.id == $story_id) | .status) = "completed" |
  
  # Move from in_progress to completed
  .completed += [$story_id] |
  .in_progress -= [$story_id] |
  
  # Recalculate ready_to_pick
  # A story is ready if all its dependencies are completed
  .ready_to_pick = [
    .stories[] |
    select(
      .status == "pending" and
      (
        (.dependencies | length == 0) or
        all(.dependencies[]; . as $dep | any(.completed[]; . == $dep))
      )
    ) |
    .id
  ] |
  
  # Update blocked list
  .blocked = [
    .stories[] |
    select(.status == "pending" and (.id | IN(.ready_to_pick[]) | not)) |
    .id
  ] |
  
  # Ensure uniqueness
  .completed |= unique |
  .in_progress |= unique |
  .ready_to_pick |= unique |
  .blocked |= unique
' dependency-graph.json > dependency-graph.json.tmp

# Validate JSON
if ! jq empty dependency-graph.json.tmp 2>/dev/null; then
  echo "❌ Graph update produced invalid JSON! Restoring backup..."
  mv dependency-graph.json.bak dependency-graph.json
  git checkout -
  git branch -D "$TEMP_BRANCH"
  exit 1
fi

mv dependency-graph.json.tmp dependency-graph.json
rm -f dependency-graph.json.bak

# Commit to main
git add dependency-graph.json

COMMIT_MSG="chore: Mark $STORY_ID as completed

Story verified and complete. This unblocks dependent stories.

PR: #$PR_NUM
Verified by: $(git config user.name)
Timestamp: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Run ID: ${ANTFARM_RUN_ID:-unknown}"

git commit -m "$COMMIT_MSG"

# Push to main
if ! git push origin HEAD:main; then
  echo "❌ Failed to push graph update to main"
  git checkout -
  git branch -D "$TEMP_BRANCH"
  exit 1
fi

echo "✅ Graph updated on main"

# Show what became ready
NEWLY_READY=$(jq -r '.ready_to_pick[]' dependency-graph.json)
if [ -n "$NEWLY_READY" ]; then
  echo ""
  echo "🎯 Newly available tasks:"
  echo "$NEWLY_READY" | while read story; do
    jq -r --arg id "$story" '.stories[] | select(.id == $id) | "  - \(.id): \(.title)"' dependency-graph.json
  done
fi

# Show current state
echo ""
echo "📊 Current State:"
echo "  Ready: $(jq -r '.ready_to_pick | length' dependency-graph.json)"
echo "  In Progress: $(jq -r '.in_progress | length' dependency-graph.json)"
echo "  Completed: $(jq -r '.completed | length' dependency-graph.json)"
echo "  Blocked: $(jq -r '.blocked | length' dependency-graph.json)"

# Clean up
git checkout -
git branch -D "$TEMP_BRANCH"

exit 0
