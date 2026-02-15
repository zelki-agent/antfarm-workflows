# Multi-Agent Coordination Mechanisms

This document details the 12 coordination mechanisms that enable multiple independent antfarm agents to collaborate safely on the same GitHub repository without collisions or conflicts.

## Overview

When multiple agents (potentially on different machines, with different operators) all work on the same repository, these mechanisms prevent:
- ❌ Duplicate work (two agents claim the same issue)
- ❌ Merge conflicts (agents modify the same files)
- ❌ Stale branches (agent works on outdated code)
- ❌ Resource exhaustion (too many concurrent workflows)
- ❌ Abandoned work (agent crashes, issue stuck forever)
- ❌ Semantic conflicts (changes that contradict each other)

---

## 1. Atomic Claiming via Issue Assignment

**Problem**: Race condition where two agents both claim an issue simultaneously.

**Solution**: Use GitHub's issue assignment as an atomic lock.

```bash
# Check if already assigned
ASSIGNEES=$(gh issue view $ISSUE_NUM --json assignees --jq '.assignees[].login')
if [ -n "$ASSIGNEES" ]; then
  echo "Already claimed by $ASSIGNEES"
  exit 1
fi

# Atomically assign + label
gh issue edit $ISSUE_NUM --add-assignee "@me" --add-label "🟢 workflow-active"
```

**Implementation**:
- Planner agent (step 2 of claiming)
- Triager agent (bug-fix workflow)
- Scanner agent (security-audit workflow)

**Verification**: Check issue page - should show assignee immediately after claim.

---

## 2. Concurrency Limiting

**Problem**: 10 agents all start workflows at once, exhaust server resources (memory, CPU, disk I/O).

**Solution**: Limit concurrent workflows per repo using label count.

```bash
ACTIVE_COUNT=$(gh issue list --label "🟢 workflow-active" --json number --jq 'length')
MAX_CONCURRENT=3

if [ "$ACTIVE_COUNT" -ge "$MAX_CONCURRENT" ]; then
  echo "Concurrency limit reached. Waiting..."
  sleep 60
  # Retry or queue
fi
```

**Configuration**:
- Default: 3 concurrent workflows
- Override: Set `ANTFARM_MAX_CONCURRENT` env var
- Per-repo: Set GitHub repository variable

**Implementation**: Planner agent (step 1 of claiming)

---

## 3. File Overlap Detection

**Problem**: Agent A working on auth module, Agent B working on "refactor auth" - semantic conflict even if different issues.

**Solution**: Query open PRs, compare changed files, warn if >50% overlap.

```bash
# Get files changed in open PRs
OPEN_PRS=$(gh pr list --json number,files)

# Compare with estimated changes for this task
# (heuristic: keywords, file paths mentioned in task)
```

**Limitations**:
- Can't perfectly predict file changes before planning
- Heuristic-based (keywords in task description)
- Provides warning, not blocking

**Implementation**: Planner agent (step 3 of claiming)

---

## 4. TTL-Based Unclaiming

**Problem**: Agent claims issue, crashes 10 minutes in. Issue is assigned forever, blocks future work.

**Solution**: Claims include expiry timestamp. Monitoring script auto-unclaims after TTL.

```bash
# When claiming
CLAIM_EXPIRY=$(date -u -d '+4 hours' +"%Y-%m-%d %H:%M:%S UTC")
gh issue comment $ISSUE_NUM --body "Claim expires: $CLAIM_EXPIRY"

# Monitoring script (run periodically)
# Checks all active issues, unassigns if expired and no progress updates
```

**Configuration**:
- Default TTL: 4 hours
- Override: `ANTFARM_CLAIM_TTL_HOURS` env var

**Implementation**:
- Claiming: All first-stage agents (planner, triager, scanner)
- Monitoring: `scripts/monitor-claims.sh` (run via cron or GitHub Actions)

**Monitoring Setup**:
```bash
# Manual run
./scripts/monitor-claims.sh owner/repo

# Cron (every 30 minutes)
*/30 * * * * /path/to/scripts/monitor-claims.sh owner/repo

# GitHub Actions
# See .github/workflows/antfarm-coordination.yml
```

---

## 5. Progress Heartbeats

**Problem**: Hard to distinguish "workflow is working" from "workflow crashed" without frequent updates.

**Solution**: Agents post progress comments every 10 minutes.

```bash
# Created during claiming
cat > /tmp/heartbeat_${RUN_ID}.sh <<'EOF'
gh issue comment $ISSUE_NUM --body "Progress: Story $N/$TOTAL"
EOF

# Called periodically by workflow runner every 10 minutes
```

**Benefits**:
- Enables accurate staleness detection
- Provides visibility into workflow progress
- Reassures humans that work is ongoing

**Implementation**: Planner agent creates heartbeat script (step 6 of claiming)

---

## 6. Standardized Branch Naming

**Problem**: Different agents create overlapping or confusing branch names.

**Solution**: Enforce consistent naming convention.

```bash
BRANCH_NAME="<type>/<issue-number>-<slug>"
# Examples:
#   feature/42-add-dark-mode
#   bugfix/55-null-pointer-fix
#   security/100-sql-injection-fix
```

**Benefits**:
- Easy mapping from issue to branch
- Prevents name collisions
- Clear intent from branch name

**Implementation**: Planner agent (step 5 of claiming)

---

## 7. Pre-PR Freshness Checks

**Problem**: Agent works for 2 hours. Meanwhile, 3 PRs merge to main. Agent creates PR based on stale code.

**Solution**: Before creating PR, fetch latest main and auto-rebase if needed.

```bash
git fetch origin main

if ! git merge-base --is-ancestor HEAD origin/main; then
  echo "Branch is stale. Auto-rebasing..."
  git rebase origin/main
  npm test  # Re-run tests after rebase
fi
```

**Implementation**: PR creation step (see `workflows/feature-dev/agents/developer/PR-CREATION.md`)

**Result**: PRs are always up-to-date with main at creation time.

---

## 8. Pre-PR Conflict Detection

**Problem**: Agent creates PR, maintainer tries to merge, discovers conflicts.

**Solution**: Test-merge main before creating PR. Attempt auto-resolution or warn.

```bash
# Test merge (don't commit)
git checkout -b test-merge-$BRANCH
git merge --no-commit --no-ff origin/main

if [ $? -ne 0 ]; then
  # Conflicts detected
  # Try simple auto-resolution (e.g., regenerate lock files)
  # If can't resolve, post warning comment
fi

git merge --abort
```

**Auto-Resolution Strategies**:
- Lock file conflicts → regenerate (`npm install`)
- Simple formatting conflicts → apply prettier
- More complex → warn and let human resolve

**Implementation**: PR creation step (PR-CREATION.md #2)

---

## 9. Auto-Rebase Stale PRs

**Problem**: PR is created clean, but main advances. Now PR is stale and has conflicts.

**Solution**: Periodic script (or GitHub Action) auto-rebases open antfarm PRs.

```bash
# For each open PR with "🤖 antfarm" label:
#   1. Check if behind main
#   2. Attempt rebase
#   3. Run tests
#   4. Push if tests pass
#   5. Comment on PR with result
```

**Implementation**: `scripts/auto-rebase-prs.sh`

**Scheduling**:
```yaml
# GitHub Actions (every 30 minutes)
on:
  schedule:
    - cron: '*/30 * * * *'
```

**Benefits**:
- PRs stay up-to-date automatically
- Reduces merge conflicts
- Catches test failures early

---

## 10. Failure Reporting

**Problem**: Agent crashes. Issue is claimed, no updates, unclear what happened.

**Solution**: On workflow failure, post detailed comment with logs.

```bash
# On crash/error
gh issue comment $ISSUE_NUM --body "❌ Workflow failed

**Run ID:** $RUN_ID
**Error:** $ERROR_MESSAGE
**Logs:** antfarm logs $RUN_ID

---
*Issue auto-unclaimed. Available for retry.*"

# Unassign and update labels
gh issue edit $ISSUE_NUM --remove-assignee "@me" --add-label "🔴 workflow-failed"
```

**Implementation**:
- PR creation step (error handling)
- Workflow runner (exception handlers)

---

## 11. Architectural Decision Log (ADR)

**Problem**: Agent A makes architectural decision in PR #5. Agent B (PR #6) doesn't know, implements contradictory approach.

**Solution**: Agents write ADRs to `docs/decisions/`, read recent ADRs before planning.

**ADR Format**:
```markdown
# ADR-005: Use PostgreSQL for Primary Database

**Date**: 2026-02-15
**Status**: Accepted

## Context
We need a primary database for the application...

## Decision
We will use PostgreSQL 16...

## Consequences
- Developers must have PostgreSQL installed...
```

**Implementation**:
- Planner reads `docs/decisions/` (step 4 of pre-PR checks)
- Developer writes ADRs for significant decisions
- PR description references related ADRs

**Benefits**:
- Shared context across agents
- Prevents contradictory decisions
- Documents rationale

---

## 12. Work Queue Management

**Problem**: Issues come in faster than agents can handle. Need prioritization.

**Solution**: Use GitHub Projects as a work queue.

**Setup**:
```bash
# Create project board
gh project create --owner <org> --title "Antfarm Queue"

# Columns:
#   - Backlog
#   - Ready
#   - In Progress (auto: when issue assigned + workflow-active label)
#   - Review (auto: when PR created)
#   - Done (auto: when issue closed)
```

**Agent Behavior**:
- Only claim issues from "Ready" column
- Move to "In Progress" when claimed
- Move to "Review" when PR created

**Benefits**:
- Clear visibility into queue depth
- Enables prioritization (drag issues)
- Prevents overwhelming the system

**Implementation**: Optional - requires project board setup per repo.

---

## Coordination Summary

| Mechanism | Prevents | Implementation | Frequency |
|-----------|----------|----------------|-----------|
| Atomic Claiming | Duplicate work | Planner/Triager/Scanner | Per workflow start |
| Concurrency Limiting | Resource exhaustion | Planner | Per workflow start |
| File Overlap Detection | Semantic conflicts | Planner | Per workflow start |
| TTL Unclaiming | Abandoned work | Monitor script | Every 30 min |
| Progress Heartbeats | Stale detection uncertainty | All agents | Every 10 min |
| Standardized Branches | Name collisions | Planner | Per workflow start |
| Freshness Checks | Stale PRs | PR creation | Per PR |
| Conflict Detection | Merge conflicts | PR creation | Per PR |
| Auto-Rebase PRs | Stale PRs post-creation | Rebase script | Every 30 min |
| Failure Reporting | Silent failures | Error handlers | On error |
| ADR | Design conflicts | Planner/Developer | As needed |
| Work Queue | Overload | GitHub Projects | Continuous |

---

## Monitoring Dashboard

Recommended monitoring queries:

```bash
# Active workflows
gh issue list --repo owner/repo --label "🟢 workflow-active"

# Failed workflows
gh issue list --repo owner/repo --label "🔴 workflow-failed"

# Stale workflows (manually flagged)
gh issue list --repo owner/repo --label "🔴 workflow-stale"

# Open antfarm PRs
gh pr list --repo owner/repo --label "🤖 antfarm"

# PRs needing rebase
gh pr list --repo owner/repo --label "needs-rebase"
```

**Grafana/Prometheus Metrics** (if using monitoring):
- `antfarm_workflows_active{repo="owner/repo"}` - Active workflow count
- `antfarm_workflows_completed{repo="owner/repo"}` - Completed workflows
- `antfarm_workflows_failed{repo="owner/repo"}` - Failed workflows
- `antfarm_pr_rebase_count{repo="owner/repo"}` - Auto-rebases performed

---

## Testing Coordination

To test coordination mechanisms without real work:

```bash
# Terminal 1: Start workflow A
antfarm workflow run feature-dev "Test task A (issue #10)"

# Terminal 2: Try to start workflow B on same issue (should be blocked)
antfarm workflow run feature-dev "Test task B (issue #10)"
# Expected: "Issue already assigned" - claim prevented

# Terminal 3: Start workflow C on different issue (should succeed)
antfarm workflow run feature-dev "Test task C (issue #11)"

# Check concurrency limit
gh issue list --label "🟢 workflow-active" | wc -l
# Should not exceed MAX_CONCURRENT
```

---

## Maintenance

### Regular Tasks

**Daily**:
- Review failed workflows: `gh issue list --label "🔴 workflow-failed"`
- Check concurrency limits aren't consistently hit

**Weekly**:
- Review stale PRs: `gh pr list --label "needs-rebase"`
- Check TTL unclaiming is working (no stale assignments)
- Review ADR directory for clarity

**Monthly**:
- Analyze workflow success rate
- Adjust concurrency limits if needed
- Update coordination scripts if GitHub API changes

### Troubleshooting

**Issue stuck with active label but no assignee**:
```bash
gh issue edit <issue> --remove-label "🟢 workflow-active"
```

**Multiple agents claimed same issue** (race condition):
```bash
# Manually unassign all but one
gh issue edit <issue> --remove-assignee <username>
```

**PR won't auto-rebase** (conflicts):
```bash
# Check PR status
gh pr view <pr>
# Look for "needs-rebase" label
# Resolve manually
```

---

## Future Enhancements

Potential additions:

1. **Distributed Lock Service** - Use Redis/etcd for stricter atomic claims
2. **Workflow Priority Queues** - Critical bugs jump the queue
3. **Resource Quotas** - Per-agent limits on active workflows
4. **Smart Conflict Prediction** - ML model predicts file conflicts before work starts
5. **Cross-Repo Coordination** - Coordinate across microservice repos
6. **Workflow Checkpointing** - Resume from last good state on failure

---

**Last Updated**: 2026-02-15  
**Version**: 1.0.0
