# Known Issues & Fixes

## Issue: Security fixes applied to wrong repo/branch

**Problem:**
Security audit workflows were working in incorrect locations (e.g., `/tmp/squad-pick` instead of `/root/.openclaw/workspace/squad-pick`) and on wrong branches. This caused all security fixes to be isolated in temp directories and never pushed to GitHub PRs.

**Root Cause:**
The scanner agent was expected to infer REPO and BRANCH from vague task descriptions like:
- "Security audit for PR #37: Catalog models (squad-pick)"
- "Security audit for crewsly-schedules PR #60"

The agent would guess wrong and pick:
- Old cached repo paths in `/tmp`
- Random existing branch names (e.g., `feature/nestjs-monorepo-init`)

**Fix Applied (2026-02-15):**
Updated `workflow.yml` to require explicit REPO and BRANCH in task string:
```yaml
⚠️ CRITICAL: The following parameters MUST be provided explicitly in the task string:
- REPO: <absolute-path-to-repo> (e.g., /root/.openclaw/workspace/squad-pick)
- BRANCH: <existing-pr-branch> (e.g., feature/catalog-models-22)
```

Scanner agent now fails immediately if these are not found in the task string.

**Correct Usage:**
```bash
# ❌ WRONG (vague, agent will guess wrong)
antfarm workflow run security-audit "Security audit for PR #37: Catalog models (squad-pick)"

# ✅ CORRECT (explicit repo and branch)
antfarm workflow run security-audit "Security audit for PR #37. REPO: /root/.openclaw/workspace/squad-pick BRANCH: feature/catalog-models-22"
```

**Prevention:**
1. Always provide explicit `REPO:` and `BRANCH:` in security-audit task strings
2. Use absolute paths for REPO (not relative or temp paths)
3. Verify BRANCH exists in the target repo before starting
4. Check the setup step logs to confirm correct repo/branch before fixes begin

**Related Issues:**
- This was a recurring problem (happened multiple times)
- Added validation to fail fast if parameters missing
- Consider adding schema validation for task parameters in future

**Last Updated:** 2026-02-15
