# Dependency Graph Architecture (v2)

**Critical fixes for race conditions and consistency issues**

---

## 🔴 Problems Identified (v1)

### 1. Race Condition on Task Pickup
**Issue:** Two agents query simultaneously → both get same task → both try to claim  
**Impact:** Wasted effort, collision detection after the fact

### 2. Graph on Different Branches
**Issue:** Graph lives in feature branches → agents see stale/different versions  
**Impact:** Agents work on blocked tasks, don't see completed tasks, chaos

### 3. Ongoing Tasks Not Reflected Fast Enough
**Issue:** Agent claims → works for 5 min → updates graph → meanwhile others see task as ready  
**Impact:** Duplicate work attempts, race conditions

### 4. Graph Only Updated After PR Merge
**Issue:** Verifier marks complete in feature branch → PR sits in review → dependents stay blocked  
**Impact:** Massive delays, defeats parallelization purpose

---

## ✅ Architecture (v2) - Solutions

### Core Principle: **Graph Lives on `main` Branch ONLY**

```
Feature branches: Code changes (go through PR review)
Main branch: dependency-graph.json (updated directly, bypasses PR)
```

**Why this works:**
- Single source of truth (origin/main)
- All agents see same graph state
- Updates visible immediately (no PR delay)
- Graph is metadata, safe to commit without review

---

## 📊 Graph Location Strategy

| Operation | Where | Branch | Why |
|-----------|-------|--------|-----|
| Create graph | Initial commit | main | Make available to all agents |
| Query graph | `git show origin/main:dependency-graph.json` | origin/main | Single source of truth |
| Update graph (start) | Direct commit | main | Immediate visibility |
| Update graph (complete) | Direct commit | main | Unblock dependents immediately |
| Update graph (fail) | Direct commit | main | Return to pending immediately |
| Feature code | Feature branch | feature/* | Normal PR review process |

---

## 🔐 Atomic Operations

### 1. Claim + Start (Atomic)

**Script:** `claim-and-start.sh <repo> <issue-num>`

**Flow:**
```bash
1. Query graph from origin/main
2. Check if story is ready
3. Claim issue (atomic via GitHub API)
   ↓ If claim fails → abort
4. Checkout origin/main as temp branch
5. Update graph: status = "in_progress"
6. Commit + push directly to main
   ↓ If push fails → rollback claim
7. Return story details
```

**Guarantees:**
- ✅ Claim + graph update are atomic (both succeed or both fail)
- ✅ Graph updated on main immediately after claim
- ✅ Other agents see task as "in_progress" within seconds
- ✅ No race condition (GitHub issue assignment is atomic)

### 2. Complete (Bypass PR)

**Script:** `complete-story.sh <story-id> <pr-num>`

**Flow:**
```bash
1. Checkout origin/main as temp branch
2. Update graph: status = "completed"
3. Recalculate ready_to_pick (unblock dependents)
4. Commit + push directly to main
5. Clean up temp branch
```

**Result:**
- ✅ Dependent stories unblocked immediately
- ✅ PR still in review (code unchanged)
- ✅ Graph reflects reality (work is done, even if PR not merged)

### 3. Fail (Rollback)

**Script:** `fail-story.sh <story-id> <issue-num> <repo>`

**Flow:**
```bash
1. Checkout origin/main as temp branch
2. Update graph: status = "pending" (or back to "ready")
3. Commit + push directly to main
4. Unassign issue
5. Remove workflow-active label, add workflow-failed
```

**Result:**
- ✅ Story available for retry immediately
- ✅ Issue unassigned (other agents can claim)
- ✅ Graph reflects failure

---

## 🔄 Full Workflow Example

### Scenario: 3 agents, 5 stories with dependencies

```
US-001: Create User entity (no deps)
US-002: Create Auth service (depends on US-001)
US-003: Add email validation (depends on US-001)
US-004: Create login endpoint (depends on US-002, US-003)
US-005: Add password reset (depends on US-002)
```

**Initial graph (on main):**
```json
{
  "ready_to_pick": ["US-001"],
  "in_progress": [],
  "completed": [],
  "blocked": ["US-002", "US-003", "US-004", "US-005"]
}
```

### Agent A (10:00:00)

```bash
# Query graph from main
query-next-task.sh → US-001

# Claim atomically (updates main immediately)
claim-and-start.sh zelki/repo 42
# Graph on main NOW shows:
# ready_to_pick: []
# in_progress: ["US-001"]
```

### Agent B (10:00:05 - 5 seconds later)

```bash
# Query graph from main (sees Agent A's update)
query-next-task.sh → none (US-001 in progress, others blocked)

# Wait or work on different issue
```

### Agent A (10:15:00 - completes US-001)

```bash
# Developer finishes, commits code to feature branch
git checkout feature/42-user-entity
git commit -m "feat: US-001 - Create user entity"

# Verifier validates, marks complete (updates main directly)
complete-story.sh US-001 14
# Graph on main NOW shows:
# ready_to_pick: ["US-002", "US-003"]  ← unblocked!
# in_progress: []
# completed: ["US-001"]
# blocked: ["US-004", "US-005"]

# PR #14 still in review (doesn't matter for graph)
```

### Agent B (10:15:10 - queries again)

```bash
# Query graph from main
query-next-task.sh → US-002

# Claim it
claim-and-start.sh zelki/repo 43
# Graph now: in_progress: ["US-002"]
```

### Agent C (10:15:15 - also queries)

```bash
# Query graph from main
query-next-task.sh → US-003

# Claim it
claim-and-start.sh zelki/repo 44
# Graph now: in_progress: ["US-002", "US-003"]
```

**Parallel execution achieved!** 🎉
- Agent B works on US-002
- Agent C works on US-003
- Both unblocked by US-001 completion
- No collisions, no race conditions

---

## 📝 Agent Workflow (Updated)

### Developer (BEFORE starting work)

```bash
# 1. Query graph (from origin/main)
NEXT_TASK=$(query-next-task.sh)

if [ "$NEXT_TASK" = "none" ]; then
  echo "No tasks ready. Exiting."
  exit 0
fi

STORY_ID=$(echo "$NEXT_TASK" | jq -r '.id')
ISSUE_NUM=$(echo "$NEXT_TASK" | jq -r '.issue_number')

# 2. Claim atomically (updates main immediately)
claim-and-start.sh $REPO $ISSUE_NUM

# 3. Checkout feature branch
git checkout $FEATURE_BRANCH

# 4. Implement story
# ... coding ...

# 5. Commit to feature branch (NOT main)
git commit -m "feat: $STORY_ID - ..."
git push origin $FEATURE_BRANCH
```

### Verifier (AFTER successful verification)

```bash
# 1. Verify tests pass, criteria met
# ... verification ...

# 2. Mark complete (updates main directly, bypasses PR)
complete-story.sh $STORY_ID $PR_NUM

# 3. Post comment on PR
gh pr comment $PR_NUM --body "✅ Story verified, dependency graph updated. Dependent stories unblocked."
```

### On Failure

```bash
# Mark failed (updates main, unassigns issue)
fail-story.sh $STORY_ID $ISSUE_NUM $REPO

# Post failure comment
gh issue comment $ISSUE_NUM --body "❌ Workflow failed. Story returned to pending. Available for retry."
```

---

## 🎯 Consistency Guarantees

### Single Source of Truth
- **Graph always on origin/main**
- All agents fetch from origin/main before querying
- No local copies, no branch divergence

### Atomic Updates
- Claim + graph update are one operation (both succeed or both fail)
- Complete updates graph immediately (no PR delay)
- Fail updates graph + unassigns issue atomically

### Immediate Visibility
- Agent A claims → commits to main
- Agent B queries (1 second later) → sees Agent A's claim
- No stale reads, no race conditions

### PR Independence
- Code changes go through PR (normal review)
- Graph updates bypass PR (metadata, safe to commit)
- PR can be in review while dependents proceed

---

## ⚠️ What Could Still Go Wrong?

### Git Push Conflicts
**Scenario:** Agent A and Agent B both update graph simultaneously  
**Mitigation:** Retry push with rebase (standard Git conflict resolution)

```bash
# If push fails
git pull --rebase origin main
git push origin HEAD:main
```

### Network Failures
**Scenario:** Agent claims issue but can't push graph update  
**Mitigation:** Rollback claim (already implemented in claim-and-start.sh)

### Stale Graph After Fast-Forward
**Scenario:** Agent queries, graph updates, agent claims 5 sec later on stale data  
**Mitigation:** Re-query in claim-and-start.sh (fetch latest before updating)

---

## 📊 Migration from v1 to v2

### For Existing Workflows

1. **Update scripts:**
   - Replace `update-dependency-graph.sh` with new versions
   - Add `claim-and-start.sh`, `complete-story.sh`, `fail-story.sh`
   - Update `query-next-task.sh` to read from origin/main

2. **Update agent instructions:**
   - Developer: Use `claim-and-start.sh` instead of manual claim + update
   - Verifier: Use `complete-story.sh` instead of update-dependency-graph.sh
   - On failure: Use `fail-story.sh`

3. **Move graph to main:**
   ```bash
   # If graph is currently on feature branch
   git checkout $FEATURE_BRANCH
   git mv dependency-graph.json /tmp/graph.json
   git commit -m "chore: Remove graph from feature branch"
   
   git checkout main
   git pull
   mv /tmp/graph.json dependency-graph.json
   git add dependency-graph.json
   git commit -m "chore: Move dependency graph to main branch"
   git push origin main
   ```

4. **Delete graph from feature branches:**
   - Graph should NEVER exist on feature branches going forward
   - Only on main

---

## 🎉 Benefits (v2 vs v1)

| Metric | v1 | v2 |
|--------|----|----|
| Race condition on claim | ❌ Possible | ✅ Prevented (atomic) |
| Graph consistency | ❌ Branch-dependent | ✅ Single source (main) |
| Visibility delay | ❌ Minutes-hours (PR) | ✅ Seconds (direct commit) |
| Duplicate work risk | ⚠️ Medium | ✅ Low |
| Parallelization blocked by PRs | ❌ Yes | ✅ No |

---

**Version:** 2.0  
**Last Updated:** 2026-02-15  
**Status:** ✅ Production Ready
