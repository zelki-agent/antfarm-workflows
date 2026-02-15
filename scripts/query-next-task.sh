#!/bin/bash
# Query the next available task from dependency graph
# Usage: query-next-task.sh [repo-path]

set -euo pipefail

REPO_PATH="${1:-.}"
cd "$REPO_PATH"

# Check if graph exists
if [ ! -f "dependency-graph.json" ]; then
  echo "Error: dependency-graph.json not found in $REPO_PATH" >&2
  echo "Run dependency-mapper agent first to generate the graph." >&2
  exit 1
fi

# Validate JSON
if ! jq empty dependency-graph.json 2>/dev/null; then
  echo "Error: dependency-graph.json is invalid JSON" >&2
  exit 1
fi

# Get ready tasks (tasks with all dependencies completed or no dependencies)
READY=$(jq -r '.ready_to_pick[]' dependency-graph.json 2>/dev/null || echo "")

if [ -z "$READY" ]; then
  # Check if all tasks are completed
  TOTAL=$(jq -r '.stories | length' dependency-graph.json)
  COMPLETED=$(jq -r '.completed | length' dependency-graph.json)
  
  if [ "$TOTAL" -eq "$COMPLETED" ]; then
    echo "✅ All tasks completed!" >&2
  else
    echo "⏸️  No tasks ready. All tasks are either in progress or blocked." >&2
    
    # Show what's blocking
    IN_PROGRESS=$(jq -r '.in_progress[]' dependency-graph.json 2>/dev/null || echo "")
    if [ -n "$IN_PROGRESS" ]; then
      echo "Currently in progress:" >&2
      echo "$IN_PROGRESS" | while read story; do
        jq -r --arg id "$story" '.stories[] | select(.id == $id) | "  - \(.id): \(.title)"' dependency-graph.json
      done >&2
    fi
  fi
  
  echo "none"
  exit 0
fi

# Pick first ready task (FIFO)
NEXT_STORY=$(echo "$READY" | head -1)

# Get full story details
STORY_DETAILS=$(jq --arg id "$NEXT_STORY" '.stories[] | select(.id == $id)' dependency-graph.json)

# Output full JSON for easy parsing
echo "$STORY_DETAILS"

# Also output human-readable summary to stderr
echo "📊 Next available task: $NEXT_STORY" >&2
echo "$STORY_DETAILS" | jq -r '"  Title: \(.title)\n  Issue: #\(.issue_number)\n  Dependencies: \(if .dependencies | length == 0 then "none" else (.dependencies | join(", ")) end)"' >&2

exit 0
