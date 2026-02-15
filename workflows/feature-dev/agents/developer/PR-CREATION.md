# PR Creation Checklist

Run pre-PR coordination checks before creating pull requests.

## Pre-PR Checks

### 1. Freshness Check + Auto-Rebase
```bash
git fetch origin main
if ! git merge-base --is-ancestor HEAD origin/main; then
  git rebase origin/main && npm test
fi
```

### 2. Conflict Detection
```bash
git merge --no-commit --no-ff origin/main
# Check for conflicts, attempt auto-resolution
git merge --abort
```

### 3. File Overlap Check
Check open PRs for file overlap >50%

### 4. Architectural Decision Review
Read `docs/decisions/*.md` for recent ADRs

### 5. Create PR with Full Description
Include: summary, changes, tests, related issues, ADRs

See COORDINATION.md for full implementation details.
