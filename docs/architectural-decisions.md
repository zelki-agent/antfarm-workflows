# Architectural Decision Records (ADRs)

This document tracks architectural decisions made across antfarm workflows. Agents read this before planning to maintain consistency.

## How to Use

### For Agents (Planning Phase)

Before generating a plan:
1. Read this document
2. Check if recent decisions affect your task
3. Follow established patterns
4. Add new decisions if your task introduces architectural changes

### For Humans

Review agent-proposed ADRs during PR review. Approve or request changes before merging.

---

## Decision Format

```markdown
## ADR-XXX: Title (YYYY-MM-DD)

**Status:** Proposed | Accepted | Deprecated | Superseded by ADR-YYY

**Context:**
What problem or question prompted this decision?

**Decision:**
What approach was chosen?

**Consequences:**
- Positive outcomes
- Trade-offs
- Future implications

**Related PRs:** #123, #456
```

---

## Active Decisions

### ADR-001: Workflow Coordination via GitHub Issue Assignment (2026-02-15)

**Status:** Accepted

**Context:**
Multiple uncoordinated agents need to collaborate on the same repository without colliding on the same work or creating merge conflicts.

**Decision:**
Use GitHub's native issue assignment + labels as the primary coordination mechanism:
- Issues are atomically claimed via `gh issue edit --add-assignee`
- Active workflows marked with `🟢 workflow-active` label
- Claims include TTL (4 hours default)
- Monitoring cron job enforces TTL and detects failures

**Consequences:**
- ✅ Prevents race conditions on claiming
- ✅ Visible coordination state in GitHub UI
- ✅ No external database required
- ⚠️ Requires `gh` CLI authenticated
- ⚠️ Depends on GitHub API availability

**Related PRs:** Initial implementation

---

### ADR-002: Standardized Branch Naming (2026-02-15)

**Status:** Accepted

**Context:**
Need consistent branch naming to:
- Map branches to issues
- Avoid branch name collisions
- Enable automated tooling

**Decision:**
Use format: `<type>/<issue-num>-<slug>`
- `feature/123-user-authentication`
- `bugfix/456-null-pointer-fix`
- `security/789-sql-injection-patch`

**Consequences:**
- ✅ Clear issue→branch mapping
- ✅ Prevents naming collisions
- ✅ Easy to parse programmatically
- ⚠️ Slug truncated to 50 chars (branch name limits)

**Related PRs:** Initial implementation

---

### ADR-003: Pre-PR Safety Checks (2026-02-15)

**Status:** Accepted

**Context:**
Need to prevent PRs with merge conflicts, test failures, or stale code from being created.

**Decision:**
Before creating any PR, run mandatory safety checks:
1. Fetch latest main
2. Check if branch is behind → auto-rebase if possible
3. Dry-run merge test to detect conflicts
4. Re-run full test suite after rebase
5. Only create PR if all checks pass

**Consequences:**
- ✅ Significantly reduces broken PRs
- ✅ Catches staleness before PR creation
- ✅ Auto-resolves simple conflicts
- ⚠️ Adds 1-3 minutes to PR creation
- ⚠️ Complex conflicts still require manual resolution

**Related PRs:** Initial implementation

---

### ADR-004: Progress Heartbeat Comments (2026-02-15)

**Status:** Accepted

**Context:**
Need to detect when workflows crash, hang, or silently fail without leaving PRs in limbo.

**Decision:**
Agents post progress update comments every 10 minutes:
- Initial claim comment
- Periodic progress updates ("Story 3/12 in progress")
- Final completion comment
- Monitoring script checks for heartbeat absence

**Consequences:**
- ✅ Early failure detection (<30 min)
- ✅ Visible progress for humans
- ✅ Enables automatic cleanup of failed workflows
- ⚠️ Adds noise to issue comments (mitigated with collapsible format)

**Related PRs:** Initial implementation

---

### ADR-005: Concurrency Limiting via Label Count (2026-02-15)

**Status:** Accepted

**Context:**
Need to prevent resource exhaustion when many agents attempt to work simultaneously (OOM, rate limits, etc.).

**Decision:**
- Max 3 concurrent workflows per repository (configurable)
- Check via `gh issue list --label "🟢 workflow-active" | count`
- Agents wait/retry if limit reached
- Helps with rate limiting, resource usage, and merge velocity

**Consequences:**
- ✅ Prevents resource exhaustion
- ✅ Manageable PR review queue
- ✅ Reduces merge conflict probability
- ⚠️ May slow parallel development
- ⚠️ Queue behavior needs monitoring

**Related PRs:** Initial implementation

---

## Adding New Decisions

When your workflow makes an architectural choice that affects future work:

```bash
# In your PR, add to this file
cat >> docs/architectural-decisions.md <<EOF

---

### ADR-XXX: Your Decision Title ($(date +%Y-%m-%d))

**Status:** Proposed

**Context:**
Explain the problem...

**Decision:**
Describe your approach...

**Consequences:**
- Pro 1
- Pro 2
- Trade-off 1

**Related PRs:** #<your-pr-number>

EOF

git add docs/architectural-decisions.md
git commit -m "docs: Add ADR-XXX - Your Decision Title"
```

The PR reviewer will validate the ADR during code review.

---

## Deprecated Decisions

None yet.
