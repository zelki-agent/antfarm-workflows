#!/bin/bash
# Mark story as failed and return to pending (called on workflow failure)
# Usage: fail-story.sh <story-id> <issue-number> <repo-owner/repo> [repo-path]

set -euo pipefail

STORY_ID="$1"
ISSUE_NUM="$2"
REPO="$3"
REPO_PATH="${4:-.}"

echo "❌ Marking $STORY_ID as failed..."

cd "$REPO_PATH"

# Create temp branch from main
TEMP_BRANCH="temp-fail-$(date +%s)-$$"
git fetch origin main
git checkout -b "$TEMP_BRANCH" origin/main

# Update graph: mark as failed (return to pending)
jq --arg story_id "$STORY_ID" '
  # Update story status
  (.stories[] | select(.id == $story_id) | .status) = "pending" |
  
  # Move from in_progress back to appropriate list
  .in_progress -= [$story_id] |
  
  # Recalculate ready status (ready if no dependencies or all deps completed)
  (
    if ((.stories[] | select(.id == $story_id) | .dependencies | length) == 0) then
      .ready_to_pick += [$story_id]
    elif all((.stories[] | select(.id == $story_id) | .dependencies[]); . as $dep | any(.completed[]; . == $dep)) then
      .ready_to_pick += [$story_id]
    else
      .blocked += [$story_id]
    end
  ) |
  
  # Ensure uniqueness
  .in_progress |= unique |
  .ready_to_pick |= unique |
  .blocked |= unique
' dependency-graph.json > dependency-graph.json.tmp

# Validate JSON
if ! jq empty dependency-graph.json.tmp 2>/dev/null; then
  echo "❌ Graph update produced invalid JSON! Aborting..."
  git checkout -
  git branch -D "$TEMP_BRANCH"
  exit 1
fi

mv dependency-graph.json.tmp dependency-graph.json

# Commit to main
git add dependency-graph.json

COMMIT_MSG="chore: Mark $STORY_ID as failed (returned to pending)

Workflow failed. Story returned to pending state.

Issue: #$ISSUE_NUM
Failed by: $(git config user.name)
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

# Unassign issue and update labels
echo "📌 Unassigning issue and updating labels..."
gh issue edit $ISSUE_NUM --repo $REPO --remove-assignee "@me" 2>/dev/null || true
gh issue edit $ISSUE_NUM --repo $REPO --remove-label "🟢 workflow-active" 2>/dev/null || true
gh issue edit $ISSUE_NUM --repo $REPO --add-label "🔴 workflow-failed" 2>/dev/null || true

echo "✅ Issue unassigned and labeled as failed"

# Clean up
git checkout -
git branch -D "$TEMP_BRANCH"

exit 0
