#!/bin/bash
# Workflow Monitor - Handles TTL enforcement, failure detection, and cleanup
# Run this as a cron job or GitHub Action every 30 minutes

set -euo pipefail

REPO="${ANTFARM_REPO:-}"
if [ -z "$REPO" ]; then
  echo "❌ ANTFARM_REPO environment variable required"
  exit 1
fi

echo "🔍 Checking workflow health for $REPO..."

# Get all issues with workflow-active label
ACTIVE_ISSUES=$(gh issue list --repo "$REPO" \
  --label "🟢 workflow-active" \
  --json number,assignees,comments,updatedAt \
  --jq '.[]')

if [ -z "$ACTIVE_ISSUES" ]; then
  echo "✅ No active workflows"
  exit 0
fi

echo "$ACTIVE_ISSUES" | jq -c '.' | while read -r issue; do
  ISSUE_NUM=$(echo "$issue" | jq -r '.number')
  UPDATED_AT=$(echo "$issue" | jq -r '.updatedAt')
  ASSIGNEE=$(echo "$issue" | jq -r '.assignees[0].login // "none"')
  
  # Parse last workflow comment
  LAST_COMMENT=$(gh issue view "$ISSUE_NUM" --repo "$REPO" --json comments \
    --jq '.comments[] | select(.body | contains("🐜") or contains("🔄")) | .body' \
    | tail -1)
  
  # Extract claim expiry from comment
  CLAIM_EXPIRY=$(echo "$LAST_COMMENT" | grep -oP 'Claim expires:\s*\K.*' || echo "")
  
  if [ -n "$CLAIM_EXPIRY" ]; then
    EXPIRY_UNIX=$(date -d "$CLAIM_EXPIRY" +%s 2>/dev/null || echo 0)
    NOW_UNIX=$(date +%s)
    
    if [ "$EXPIRY_UNIX" -gt 0 ] && [ "$NOW_UNIX" -gt "$EXPIRY_UNIX" ]; then
      echo "⏰ Issue #$ISSUE_NUM: Claim expired. Unclaiming..."
      
      # Unassign and remove active label
      gh issue edit "$ISSUE_NUM" --repo "$REPO" \
        --remove-assignee "$ASSIGNEE" \
        --remove-label "🟢 workflow-active" \
        --add-label "🔴 workflow-failed"
      
      # Post timeout comment
      gh issue comment "$ISSUE_NUM" --repo "$REPO" --body "🕐 **Workflow timed out**

The workflow claim has expired with no completion.
Issue is now available for reassignment.

Last update: $UPDATED_AT
Assigned to: $ASSIGNEE

If this was unexpected, please check workflow logs."
      
      continue
    fi
  fi
  
  # Check for stale workflows (no heartbeat in 30+ minutes)
  UPDATED_UNIX=$(date -d "$UPDATED_AT" +%s)
  NOW_UNIX=$(date +%s)
  MINUTES_SINCE_UPDATE=$(( (NOW_UNIX - UPDATED_UNIX) / 60 ))
  
  if [ "$MINUTES_SINCE_UPDATE" -gt 30 ]; then
    echo "⚠️ Issue #$ISSUE_NUM: No activity for $MINUTES_SINCE_UPDATE minutes"
    
    # Check if any progress comments exist
    PROGRESS_COMMENTS=$(gh issue view "$ISSUE_NUM" --repo "$REPO" --json comments \
      --jq '.comments[] | select(.body | contains("🔄 **Workflow progress")) | .createdAt' \
      | wc -l)
    
    if [ "$PROGRESS_COMMENTS" -eq 0 ]; then
      echo "❌ Issue #$ISSUE_NUM: No progress comments. Likely failed at start."
      
      gh issue edit "$ISSUE_NUM" --repo "$REPO" \
        --remove-assignee "$ASSIGNEE" \
        --remove-label "🟢 workflow-active" \
        --add-label "🔴 workflow-failed"
      
      gh issue comment "$ISSUE_NUM" --repo "$REPO" --body "❌ **Workflow failure detected**

No progress updates detected. The workflow likely crashed or failed to start.
Issue is now available for reassignment.

Last known update: $UPDATED_AT"
    else
      echo "⚠️ Issue #$ISSUE_NUM: Has progress but stalled. Waiting one more cycle..."
    fi
  fi
done

echo "✅ Workflow health check complete"
