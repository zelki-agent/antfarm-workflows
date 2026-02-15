#!/bin/bash
# Update dependency graph when a story is completed or started
# Usage: update-dependency-graph.sh <action> <story-id> [repo-path]
#   action: start | complete | fail

set -euo pipefail

ACTION="$1"
STORY_ID="$2"
REPO_PATH="${3:-.}"

cd "$REPO_PATH"

# Check if graph exists
if [ ! -f "dependency-graph.json" ]; then
  echo "Error: dependency-graph.json not found" >&2
  exit 1
fi

# Validate action
if [[ ! "$ACTION" =~ ^(start|complete|fail)$ ]]; then
  echo "Error: Invalid action '$ACTION'. Must be: start | complete | fail" >&2
  exit 1
fi

# Backup current graph
cp dependency-graph.json dependency-graph.json.bak

case "$ACTION" in
  start)
    # Mark story as in_progress
    jq --arg story_id "$STORY_ID" '
      # Update story status
      (.stories[] | select(.id == $story_id) | .status) = "in_progress" |
      
      # Move from ready_to_pick to in_progress
      .in_progress += [$story_id] |
      .ready_to_pick -= [$story_id] |
      
      # Ensure uniqueness
      .in_progress |= unique
    ' dependency-graph.json > dependency-graph.json.tmp
    
    mv dependency-graph.json.tmp dependency-graph.json
    echo "✅ Marked $STORY_ID as in_progress"
    ;;
    
  complete)
    # Mark story as completed and recalculate ready tasks
    jq --arg story_id "$STORY_ID" '
      # Update story status
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
            all(.dependencies[]; . as $dep | any($ENV.completed | fromjson[]; . == $dep))
          )
        ) |
        .id
      ] |
      
      # Update blocked list (inverse of ready)
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
    ' --argjson completed "$(jq -c '.completed' dependency-graph.json)" \
      dependency-graph.json > dependency-graph.json.tmp
    
    mv dependency-graph.json.tmp dependency-graph.json
    echo "✅ Marked $STORY_ID as completed"
    
    # Show what became ready
    NEWLY_READY=$(jq -r '.ready_to_pick[]' dependency-graph.json)
    if [ -n "$NEWLY_READY" ]; then
      echo "🎯 Newly available tasks:"
      echo "$NEWLY_READY" | while read story; do
        jq -r --arg id "$story" '.stories[] | select(.id == $id) | "  - \(.id): \(.title)"' dependency-graph.json
      done
    fi
    ;;
    
  fail)
    # Mark story as failed and move back to pending
    jq --arg story_id "$STORY_ID" '
      # Update story status
      (.stories[] | select(.id == $story_id) | .status) = "pending" |
      
      # Move from in_progress back to ready_to_pick (if no deps) or blocked
      .in_progress -= [$story_id] |
      
      # Recalculate ready status
      (
        if ((.stories[] | select(.id == $story_id) | .dependencies | length) == 0) then
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
    
    mv dependency-graph.json.tmp dependency-graph.json
    echo "⚠️  Marked $STORY_ID as failed (returned to pending)"
    ;;
esac

# Validate updated JSON
if ! jq empty dependency-graph.json 2>/dev/null; then
  echo "❌ Graph update produced invalid JSON! Restoring backup..." >&2
  mv dependency-graph.json.bak dependency-graph.json
  exit 1
fi

# Clean up backup
rm -f dependency-graph.json.bak

# Show current state
echo ""
echo "📊 Current State:"
echo "  Ready: $(jq -r '.ready_to_pick | length' dependency-graph.json)"
echo "  In Progress: $(jq -r '.in_progress | length' dependency-graph.json)"
echo "  Completed: $(jq -r '.completed | length' dependency-graph.json)"
echo "  Blocked: $(jq -r '.blocked | length' dependency-graph.json)"

exit 0
