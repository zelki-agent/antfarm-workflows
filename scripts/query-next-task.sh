#!/bin/bash
# Query the next available task from dependency graph
# Usage: query-next-task.sh [repo-path]
#
# CRITICAL: Always queries from origin/main to ensure all agents see same state

set -euo pipefail

REPO_PATH="${1:-.}"
cd "$REPO_PATH"

# Fetch latest main
echo "🔄 Fetching latest dependency graph from origin/main..." >&2
git fetch origin main 2>&1 | grep -v "^From" || true

# Get graph from origin/main (NOT local branch)
GRAPH_FILE="/tmp/dependency-graph-$$.json"
if ! git show origin/main:dependency-graph.json > "$GRAPH_FILE" 2>/dev/null; then
  echo "Error: dependency-graph.json not found on origin/main" >&2
  echo "Run dependency-mapper agent first to generate the graph." >&2
  rm -f "$GRAPH_FILE"
  exit 1
fi

# Validate JSON
if ! jq empty "$GRAPH_FILE" 2>/dev/null; then
  echo "Error: dependency-graph.json from origin/main is invalid JSON" >&2
  rm -f "$GRAPH_FILE"
  exit 1
fi

# Get ready tasks (tasks with all dependencies completed or no dependencies)
READY=$(jq -r '.ready_to_pick[]' "$GRAPH_FILE" 2>/dev/null || echo "")

if [ -z "$READY" ]; then
  # Check if all tasks are completed
  TOTAL=$(jq -r '.stories | length' "$GRAPH_FILE")
  COMPLETED=$(jq -r '.completed | length' "$GRAPH_FILE")
  
  if [ "$TOTAL" -eq "$COMPLETED" ]; then
    echo "✅ All tasks completed!" >&2
  else
    echo "⏸️  No tasks ready. All tasks are either in progress or blocked." >&2
    
    # Show what's blocking
    IN_PROGRESS=$(jq -r '.in_progress[]' "$GRAPH_FILE" 2>/dev/null || echo "")
    if [ -n "$IN_PROGRESS" ]; then
      echo "Currently in progress:" >&2
      echo "$IN_PROGRESS" | while read story; do
        jq -r --arg id "$story" '.stories[] | select(.id == $id) | "  - \(.id): \(.title)"' "$GRAPH_FILE"
      done >&2
    fi
  fi
  
  rm -f "$GRAPH_FILE"
  echo "none"
  exit 0
fi

# Pick first ready task (FIFO)
NEXT_STORY=$(echo "$READY" | head -1)

# Get full story details
STORY_DETAILS=$(jq --arg id "$NEXT_STORY" '.stories[] | select(.id == $id)' "$GRAPH_FILE")

# Clean up temp file
rm -f "$GRAPH_FILE"

# Output full JSON for easy parsing
echo "$STORY_DETAILS"

# Also output human-readable summary to stderr
echo "📊 Next available task: $NEXT_STORY" >&2
echo "$STORY_DETAILS" | jq -r '"  Title: \(.title)\n  Issue: #\(.issue_number)\n  Dependencies: \(if .dependencies | length == 0 then "none" else (.dependencies | join(", ")) end)"' >&2

exit 0
