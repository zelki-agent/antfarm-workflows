#!/bin/bash
# TTL-based workflow claim monitor
# Run this periodically (e.g., via cron) to auto-unclaim stale workflows

set -euo pipefail

REPO="${1:-}"
if [ -z "$REPO" ]; then
  echo "Usage: $0 <owner/repo>"
  echo "Example: $0 zelki/my-app"
  exit 1
fi

echo "🔍 Monitoring workflow claims for $REPO..."

# Get all issues with workflow-active label
ACTIVE_ISSUES=$(gh issue list \
  --repo "$REPO" \
  --label "🟢 workflow-active" \
  --json number,assignees,comments,updatedAt \
  --jq '.[]')

if [ -z "$ACTIVE_ISSUES" ]; then
  echo "✅ No active workflows found"
  exit 0
fi

CURRENT_TIME=$(date +%s)
UNCLAIMED_COUNT=0

echo "$ACTIVE_ISSUES" | jq -c '.' | while read -r issue; do
  ISSUE_NUM=$(echo "$issue" | jq -r '.number')
  UPDATED_AT=$(echo "$issue" | jq -r '.updatedAt')
  ASSIGNEES=$(echo "$issue" | jq -r '.assignees[].login' | tr '\n' ',')
  
  # Convert updatedAt to timestamp
  UPDATED_TS=$(date -d "$UPDATED_AT" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$UPDATED_AT" +%s)
  
  # Calculate age in hours
  AGE_SECONDS=$((CURRENT_TIME - UPDATED_TS))
  AGE_HOURS=$((AGE_SECONDS / 3600))
  
  echo "Issue #$ISSUE_NUM: Last update $AGE_HOURS hours ago (assigned to: $ASSIGNEES)"
  
  # Check if TTL expired (default: 4 hours)
  TTL_HOURS=${ANTFARM_CLAIM_TTL_HOURS:-4}
  
  if [ $AGE_HOURS -gt $TTL_HOURS ]; then
    echo "⚠️  Issue #$ISSUE_NUM claim expired (TTL: $TTL_HOURS hours)"
    
    # Look for last workflow comment to check if claim expiry was set
    LAST_COMMENT=$(echo "$issue" | jq -r '.comments[-1].body // empty')
    
    # Check if there's a "Claim expires:" line in recent comments
    CLAIM_EXPIRY=$(gh issue view $ISSUE_NUM --repo "$REPO" --json comments \
      --jq '.comments[] | select(.body | contains("Claim expires:")) | .body' \
      | grep "Claim expires:" | tail -1 | sed 's/.*Claim expires: //' | head -1)
    
    if [ -n "$CLAIM_EXPIRY" ]; then
      # Parse claim expiry time
      EXPIRY_TS=$(date -d "$CLAIM_EXPIRY" +%s 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S UTC" "$CLAIM_EXPIRY" +%s)
      
      if [ $CURRENT_TIME -gt $EXPIRY_TS ]; then
        echo "❌ Claim expired. Auto-unclaiming..."
        
        # Unclaim issue
        if [ -n "$ASSIGNEES" ]; then
          for assignee in $(echo "$ASSIGNEES" | tr ',' ' '); do
            gh issue edit $ISSUE_NUM --repo "$REPO" --remove-assignee "$assignee"
          done
        fi
        
        # Remove active label, add failed label
        gh issue edit $ISSUE_NUM --repo "$REPO" \
          --remove-label "🟢 workflow-active" \
          --add-label "🔴 workflow-stale"
        
        # Post unclaim comment
        gh issue comment $ISSUE_NUM --repo "$REPO" --body "⏱️ **Workflow claim expired**

The workflow that claimed this issue has not posted updates within the TTL window.

**Claim TTL:** $TTL_HOURS hours  
**Last update:** $AGE_HOURS hours ago  
**Action:** Auto-unclaimed

The issue is now available for a new workflow to claim.

---
*To prevent TTL expiry, workflows should post progress updates at least every $TTL_HOURS hours.*"
        
        UNCLAIMED_COUNT=$((UNCLAIMED_COUNT + 1))
        echo "✅ Issue #$ISSUE_NUM auto-unclaimed"
      else
        echo "✓ Claim still valid (expires in $((($EXPIRY_TS - CURRENT_TIME) / 3600)) hours)"
      fi
    else
      # No explicit expiry found - use default TTL
      echo "❌ No claim expiry found, using default TTL ($TTL_HOURS hours)"
      echo "Auto-unclaiming..."
      
      if [ -n "$ASSIGNEES" ]; then
        for assignee in $(echo "$ASSIGNEES" | tr ',' ' '); do
          gh issue edit $ISSUE_NUM --repo "$REPO" --remove-assignee "$assignee" 2>/dev/null || true
        done
      fi
      
      gh issue edit $ISSUE_NUM --repo "$REPO" \
        --remove-label "🟢 workflow-active" \
        --add-label "🔴 workflow-stale" 2>/dev/null || true
      
      gh issue comment $ISSUE_NUM --repo "$REPO" --body "⏱️ **Workflow claim expired (no updates)**

No progress updates detected within the TTL window ($TTL_HOURS hours).

**Last update:** $AGE_HOURS hours ago  
**Action:** Auto-unclaimed

The issue is now available for a new workflow to claim."
      
      UNCLAIMED_COUNT=$((UNCLAIMED_COUNT + 1))
    fi
  else
    echo "✓ Claim valid (expires in $((TTL_HOURS - AGE_HOURS)) hours)"
  fi
done

echo ""
echo "📊 Summary:"
echo "  Active workflows: $(echo "$ACTIVE_ISSUES" | jq -s 'length')"
echo "  Auto-unclaimed: $UNCLAIMED_COUNT"

if [ $UNCLAIMED_COUNT -gt 0 ]; then
  exit 0  # Exit 0 even if unclaimed (this is expected behavior)
fi
