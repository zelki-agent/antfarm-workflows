#!/bin/bash
# Auto-rebase stale PRs when main branch updates
# Can be run as a GitHub Action or cron job

set -euo pipefail

REPO="${1:-}"
if [ -z "$REPO" ]; then
  echo "Usage: $0 <owner/repo>"
  echo "Example: $0 zelki/my-app"
  exit 1
fi

echo "🔄 Checking for stale antfarm PRs in $REPO..."

# Get all open PRs with antfarm label
OPEN_PRS=$(gh pr list \
  --repo "$REPO" \
  --label "🤖 antfarm" \
  --json number,headRefName,baseRefName,mergeable,title \
  --jq '.[]')

if [ -z "$OPEN_PRS" ]; then
  echo "✅ No open antfarm PRs found"
  exit 0
fi

REBASED_COUNT=0
CONFLICT_COUNT=0

echo "$OPEN_PRS" | jq -c '.' | while read -r pr; do
  PR_NUM=$(echo "$pr" | jq -r '.number')
  BRANCH=$(echo "$pr" | jq -r '.headRefName')
  BASE=$(echo "$pr" | jq -r '.baseRefName')
  MERGEABLE=$(echo "$pr" | jq -r '.mergeable')
  TITLE=$(echo "$pr" | jq -r '.title')
  
  echo ""
  echo "PR #$PR_NUM: $TITLE"
  echo "  Branch: $BRANCH"
  echo "  Mergeable: $MERGEABLE"
  
  # Skip if already mergeable (not behind)
  if [ "$MERGEABLE" = "MERGEABLE" ]; then
    echo "  ✓ Already up-to-date"
    continue
  fi
  
  # Skip if conflicts exist
  if [ "$MERGEABLE" = "CONFLICTING" ]; then
    echo "  ⚠️  Has conflicts - skipping auto-rebase"
    
    # Add needs-rebase label
    gh pr edit $PR_NUM --repo "$REPO" --add-label "needs-rebase" 2>/dev/null || true
    
    # Comment on PR
    gh pr comment $PR_NUM --repo "$REPO" --body "⚠️ **Merge conflicts detected**

This PR has conflicts with \`$BASE\` that prevent auto-rebasing.

**Please resolve conflicts manually:**
\`\`\`bash
git checkout $BRANCH
git fetch origin $BASE
git rebase origin/$BASE
# Resolve conflicts
git rebase --continue
git push --force-with-lease
\`\`\`

Once conflicts are resolved, the \`needs-rebase\` label will be removed."
    
    CONFLICT_COUNT=$((CONFLICT_COUNT + 1))
    continue
  fi
  
  # Branch is behind - attempt rebase
  if [ "$MERGEABLE" = "UNKNOWN" ] || [ "$MERGEABLE" = "BEHIND" ]; then
    echo "  🔄 Branch behind $BASE - attempting rebase..."
    
    # Clone repo in temp directory
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    # Clone with depth 1 for speed
    gh repo clone "$REPO" . -- --depth 50
    
    # Checkout PR branch
    git checkout "$BRANCH"
    
    # Fetch latest base
    git fetch origin "$BASE"
    
    # Attempt rebase
    echo "  Running: git rebase origin/$BASE"
    if git rebase "origin/$BASE"; then
      echo "  ✅ Rebase successful"
      
      # Run tests if test command exists
      if [ -f "package.json" ] && jq -e '.scripts.test' package.json > /dev/null; then
        echo "  🧪 Running tests..."
        npm install --prefer-offline --no-audit 2>&1 | tail -5
        if npm test; then
          echo "  ✅ Tests pass"
          
          # Push rebased branch
          echo "  📤 Pushing rebased branch..."
          git push --force-with-lease
          
          # Comment on PR
          gh pr comment $PR_NUM --repo "$REPO" --body "✅ **Auto-rebase successful**

This PR was automatically rebased onto the latest \`$BASE\`.

**Rebase time:** $(date -u +"%Y-%m-%d %H:%M:%S UTC")  
**Tests:** ✅ Passing

The PR is now up-to-date and ready for review."
          
          REBASED_COUNT=$((REBASED_COUNT + 1))
        else
          echo "  ❌ Tests failed after rebase"
          
          # Abort and warn
          git rebase --abort
          
          gh pr comment $PR_NUM --repo "$REPO" --body "⚠️ **Auto-rebase: tests failed**

Attempted to rebase onto \`$BASE\`, but tests failed after rebase.

**Action required:** Manual investigation needed.

\`\`\`bash
git checkout $BRANCH
git rebase origin/$BASE
# Investigate test failures
\`\`\`"
          
          gh pr edit $PR_NUM --repo "$REPO" --add-label "needs-attention"
        fi
      else
        # No tests - push anyway
        echo "  ⚠️  No test script found - pushing without testing"
        git push --force-with-lease
        
        gh pr comment $PR_NUM --repo "$REPO" --body "✅ **Auto-rebase successful**

This PR was automatically rebased onto the latest \`$BASE\`.

**Rebase time:** $(date -u +"%Y-%m-%d %H:%M:%S UTC")  
**Tests:** ⚠️ No test script found (pushed anyway)

Please verify manually that the PR still works correctly."
        
        REBASED_COUNT=$((REBASED_COUNT + 1))
      fi
    else
      echo "  ❌ Rebase failed (conflicts)"
      git rebase --abort
      
      gh pr edit $PR_NUM --repo "$REPO" --add-label "needs-rebase"
      
      gh pr comment $PR_NUM --repo "$REPO" --body "⚠️ **Auto-rebase failed: conflicts**

Attempted to rebase onto \`$BASE\`, but conflicts were detected.

**Please resolve conflicts manually:**
\`\`\`bash
git checkout $BRANCH
git fetch origin $BASE
git rebase origin/$BASE
# Resolve conflicts
git rebase --continue
git push --force-with-lease
\`\`\`"
      
      CONFLICT_COUNT=$((CONFLICT_COUNT + 1))
    fi
    
    # Cleanup temp dir
    cd /
    rm -rf "$TEMP_DIR"
  fi
done

echo ""
echo "📊 Summary:"
echo "  Open antfarm PRs: $(echo "$OPEN_PRS" | jq -s 'length')"
echo "  Successfully rebased: $REBASED_COUNT"
echo "  Needs manual rebase: $CONFLICT_COUNT"
