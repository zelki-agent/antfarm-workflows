# Multi-Agent Coordination Guide

This document explains how multiple uncoordinated antfarm agents safely collaborate on the same repository.

## Problem Statement

When multiple agents work independently on the same repository, several failure modes can occur:
- **Race conditions** — Two agents start work on the same issue
- **Merge conflicts** — Agents modify the same files in parallel PRs
- **Stale branches** — Agent's work becomes outdated while in progress
- **Resource exhaustion** — Too many agents running simultaneously
- **Silent failures** — Crashed workflows leave issues "claimed" forever
- **Semantic conflicts** — Overlapping architectural changes

## Solution: Multi-Layer Coordination

### 1. Atomic Claiming

**Mechanism:** GitHub issue assignment + labels

```bash
# Before starting work
gh issue edit $ISSUE_NUM --add-assignee "@me" --add-label "🟢 workflow-active"
```

**Benefits:**
- Atomic operation prevents race conditions
- Visible in GitHub UI
- Leverages native GitHub features

**Fallback:** If assignment fails, abort immediately to prevent collision

---

### 2. Time-To-Live (TTL) Claims

**Mechanism:** Expiry timestamp in claim comment

```markdown
**Claim expires:** 2026-02-15 14:00:00 UTC
```

**Monitoring:** Cron job (`scripts/workflow-monitor.sh`) runs every 30 minutes:
- Checks for expired claims
- Unassigns issue
- Posts timeout comment
- Adds `🔴 workflow-failed` label

**Configuration:**
```bash
# Default 4 hours
CLAIM_TTL_HOURS=4

# In claim comment
CLAIM_EXPIRY=$(date -u -d '+4 hours' +"%Y-%m-%d %H:%M:%S UTC")
```

---

### 3. Progress Heartbeats

**Mechanism:** Periodic update comments

```bash
# Every 10 minutes during workflow execution
gh issue comment $ISSUE_NUM --body "🔄 **Workflow progress update**
**Run ID:** \`$RUN_ID\`
**Current:** Story 3/12
**Last update:** $(date -u)"
```

**Detection:** Monitoring script flags issues with no heartbeat in 30+ minutes

**Benefits:**
- Early failure detection
- Visible progress for humans
- Enables automatic cleanup

---

### 4. Concurrency Limiting

**Mechanism:** Label-based counting

```bash
ACTIVE_COUNT=$(gh issue list --label "🟢 workflow-active" --jq 'length')
MAX_CONCURRENT=3  # Configurable per repo

if [ "$ACTIVE_COUNT" -ge "$MAX_CONCURRENT" ]; then
  echo "Concurrency limit reached. Waiting..."
  sleep 60
fi
```

**Benefits:**
- Prevents resource exhaustion (memory, CPU, rate limits)
- Keeps PR review queue manageable
- Reduces merge conflict probability

**Configuration:** Set per repository based on:
- Available resources
- Review team size
- Code complexity

---

### 5. Pre-PR Safety Checks

**Mechanism:** Comprehensive checks before PR creation

```bash
# 1. Freshness check
git fetch origin main
if ! git merge-base --is-ancestor HEAD origin/main; then
  git rebase origin/main
  # Re-run tests after rebase
fi

# 2. Conflict detection (dry-run merge)
git merge --no-commit --no-ff origin/main
if [ $? -ne 0 ]; then
  # Handle conflicts or abort
fi

# 3. Quality gates
pnpm test
pnpm build
pnpm typecheck
```

**Benefits:**
- Prevents broken PRs
- Catches staleness early
- Auto-resolves simple conflicts

---

### 6. File Overlap Detection

**Mechanism:** Compare with open PRs before claiming

```bash
# Get files from open PRs
OPEN_PR_FILES=$(gh pr list --json files --jq '.[].files[].path')

# Estimate files this workflow will touch (heuristic)
# Warn if >50% overlap detected
```

**Benefits:**
- Early warning of potential conflicts
- Allows coordination before work starts
- Heuristic-based (not perfect, but helpful)

---

### 7. Auto-Rebase for Stale PRs

**Mechanism:** GitHub Action (`.github/workflows/auto-rebase-prs.yml`)

Runs every 6 hours + on main push:
- Fetches open PRs with antfarm labels
- Checks if behind main
- Auto-rebases if no conflicts
- Re-runs CI
- Labels PRs needing manual rebase

**Benefits:**
- Keeps PRs fresh
- Reduces manual rebase work
- Automatically re-runs tests

---

### 8. Failure Reporting

**Mechanism:** Error handling in all agents

```bash
# On any failure
gh issue comment $ISSUE_NUM --body "❌ **Workflow failure**
**Run ID:** \`$RUN_ID\`
**Error:** $ERROR_MESSAGE
**Stage:** $CURRENT_STAGE
**Logs:** <link-to-logs>

Issue is now available for reassignment."

gh issue edit $ISSUE_NUM \
  --remove-assignee "@me" \
  --remove-label "🟢 workflow-active" \
  --add-label "🔴 workflow-failed"
```

**Benefits:**
- Immediate visibility of failures
- Issue automatically released for retry
- Diagnostic information preserved

---

### 9. Architectural Decision Records

**Mechanism:** Shared document (`docs/architectural-decisions.md`)

Agents:
1. Read ADRs before planning
2. Follow established patterns
3. Add new ADRs when making architectural decisions

**Benefits:**
- Consistency across parallel work
- Prevents conflicting approaches
- Knowledge sharing

---

### 10. Standardized Branch Naming

**Mechanism:** Format `<type>/<issue-num>-<slug>`

Examples:
- `feature/123-user-authentication`
- `bugfix/456-null-pointer-fix`
- `security/789-sql-injection-patch`

**Benefits:**
- Clear issue→branch mapping
- Prevents naming collisions
- Enables tooling

---

## Setup

### 1. Install Monitoring Script

```bash
# Add to crontab (run every 30 minutes)
*/30 * * * * ANTFARM_REPO=owner/repo /path/to/scripts/workflow-monitor.sh >> /var/log/antfarm-monitor.log 2>&1
```

Or use GitHub Actions (recommended):
```yaml
# .github/workflows/workflow-monitor.yml
name: Workflow Monitor
on:
  schedule:
    - cron: '*/30 * * * *'
  workflow_dispatch:

jobs:
  monitor:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - env:
          ANTFARM_REPO: ${{ github.repository }}
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: bash scripts/workflow-monitor.sh
```

### 2. Enable Auto-Rebase Action

Copy `.github/workflows/auto-rebase-prs.yml` to your repository.

Requires:
- `contents: write` permission
- `pull-requests: write` permission

### 3. Configure Labels

```bash
gh label create "🟢 workflow-active" --color "0e8a16" --description "Antfarm workflow in progress"
gh label create "🔴 workflow-failed" --color "d73a4a" --description "Antfarm workflow failed"
gh label create "needs-rebase" --color "fbca04" --description "PR needs manual rebase"
```

### 4. Set Concurrency Limit

In each workflow's planner agent, set:
```bash
MAX_CONCURRENT=3  # Adjust based on repo/team size
```

### 5. Configure Claim TTL

Default is 4 hours. Adjust based on typical workflow duration:
```bash
CLAIM_TTL_HOURS=4  # Increase for long-running tasks
```

---

## Monitoring

### Check Active Workflows

```bash
gh issue list --label "🟢 workflow-active"
```

### Check Failed Workflows

```bash
gh issue list --label "🔴 workflow-failed"
```

### Check Stale PRs

```bash
gh pr list --label "needs-rebase"
```

### View Workflow Logs

```bash
# Via antfarm CLI
antfarm logs <run-id>

# Via issue comments
gh issue view <issue-num> --comments
```

---

## Troubleshooting

### Issue Stuck as "Claimed"

Run workflow monitor manually:
```bash
ANTFARM_REPO=owner/repo ./scripts/workflow-monitor.sh
```

Or manually unclaim:
```bash
gh issue edit <issue-num> \
  --remove-assignee <user> \
  --remove-label "🟢 workflow-active"
```

### PR Has Merge Conflicts

1. Check if labeled `needs-rebase`
2. Rebase manually:
   ```bash
   git checkout <branch>
   git pull origin <branch>
   git rebase origin/main
   # Resolve conflicts
   git push --force-with-lease origin <branch>
   ```
3. Label automatically removed on next auto-rebase run

### Concurrency Limit Too Restrictive

Increase `MAX_CONCURRENT` in workflow configs, or temporarily override:
```bash
# Remove active label from completed issues
gh issue edit <issue-num> --remove-label "🟢 workflow-active"
```

### Too Many Progress Comments

Comments are intentionally frequent (every 10 min) for failure detection. To reduce noise:
- Use GitHub's "Hide" feature on bot comments
- Or increase heartbeat interval (trade-off: slower failure detection)

---

## Best Practices

1. **Monitor the queue** — Check active workflow count regularly
2. **Review ADRs** — Keep architectural decisions in sync
3. **Label cleanup** — Periodically audit and clean up stale labels
4. **Adjust limits** — Tune concurrency based on actual usage
5. **Log review** — Check monitoring logs for patterns

---

## Future Enhancements

Potential additions:
- **Distributed locking** — Use Redis/DynamoDB for more robust claiming
- **Work queue** — Formal queue system instead of polling labels
- **Conflict prediction** — ML-based prediction of likely conflicts
- **Auto-merge** — Automatically merge PRs that pass all checks (with approval rules)
- **Workflow prioritization** — Priority queue for critical bugs

---

This coordination system makes antfarm agents production-ready for real-world collaborative development at scale.
