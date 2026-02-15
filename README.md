# Antfarm Workflows

Multi-agent workflow orchestration for OpenClaw. These workflow definitions enable autonomous coding agents to handle feature development, bug fixes, and security audits with sophisticated coordination mechanisms to prevent collisions when multiple agents work on the same repository.

## Table of Contents

- [Setup Requirements](#setup-requirements)
- [Agent Overview](#agent-overview)
- [Coordination Mechanisms](#coordination-mechanisms)
- [How to Use](#how-to-use)
- [Workflow Reference](#workflow-reference)
- [Troubleshooting](#troubleshooting)

---

## Setup Requirements

### Prerequisites

1. **OpenClaw Installation**
   ```bash
   # Install OpenClaw (if not already installed)
   npm install -g openclaw
   
   # Verify installation
   openclaw --version
   ```

2. **Antfarm Installation**
   ```bash
   # Clone antfarm (adjust path as needed)
   git clone https://github.com/zelki/antfarm.git
   cd antfarm
   npm install
   npm run build
   
   # Link globally or copy to workspace
   npm link
   # OR
   cp -r dist ~/.openclaw/workspace/antfarm/
   ```

3. **GitHub CLI (`gh`)**
   ```bash
   # Install gh CLI
   # macOS
   brew install gh
   
   # Linux (Debian/Ubuntu)
   sudo apt install gh
   
   # Authenticate with GitHub
   gh auth login
   
   # Verify authentication
   gh auth status
   ```

### GitHub Token Permissions

Your GitHub token (used by `gh` CLI) needs these permissions:

**Repository Permissions:**
- ✅ **Contents**: Read and write (for pushing code, creating branches)
- ✅ **Issues**: Read and write (for claiming issues, posting comments)
- ✅ **Pull Requests**: Read and write (for creating PRs, commenting)
- ✅ **Metadata**: Read (automatic with repo access)

**Optional but Recommended:**
- ✅ **Projects**: Read and write (for project board integration)
- ✅ **Actions**: Read and write (for checking CI status)

**To configure via `gh`:**
```bash
gh auth refresh -h github.com -s repo,write:discussion,project
```

### Repository Setup

Each repository where agents will work needs:

1. **Labels** (auto-created by workflows, but can pre-create):
   ```bash
   gh label create "🟢 workflow-active" --color "0e8a16" --description "Antfarm workflow in progress"
   gh label create "🔴 workflow-failed" --color "d73a4a" --description "Antfarm workflow failed"
   gh label create "user-story" --color "1d76db" --description "Auto-generated user story"
   ```

2. **Branch Protection** (optional but recommended):
   - Require PR reviews before merging
   - Require status checks to pass
   - Require branches to be up to date before merging

3. **Enable Issues** (if not already enabled):
   - Go to repo Settings → Features → Issues (check)

### OpenClaw Configuration

Ensure your OpenClaw config allows the necessary tools:

```json
{
  "agents": {
    "list": [
      {
        "id": "feature-dev-planner",
        "tools": {
          "profile": "coding",
          "alsoAllow": ["web_search", "web_fetch"]
        }
      }
      // ... other agents
    ]
  },
  "tools": {
    "exec": {
      "security": "full",  // Or configure allowlist for gh, git commands
      "host": "gateway"
    }
  }
}
```

---

## Agent Overview

### Feature Development Workflow (`feature-dev`)

A complete feature implementation pipeline:

1. **Planner** 🧭
   - **Role**: Breaks down features into implementable user stories
   - **Claims work**: Assigns issue, posts claiming comment with TTL
   - **Checks**: Concurrency limits, file overlap detection
   - **Output**: Ordered stories with acceptance criteria, GitHub issues per story
   - **Coordination**: Creates branch, sets up progress heartbeat

2. **Setup** 🔧
   - **Role**: Prepares development environment
   - **Actions**: Clones repo, checks out branch, installs dependencies
   - **Validation**: Ensures clean git state, runs initial health checks

3. **Developer** 💻
   - **Role**: Implements user stories iteratively (one story per session)
   - **Standards**: Writes tests, follows conventions, makes atomic commits
   - **Memory**: Uses `progress.txt` for cross-session context
   - **Pattern Recognition**: Documents reusable patterns in progress log

4. **Verifier** ✅
   - **Role**: Validates each story against acceptance criteria
   - **Checks**: Tests pass, typecheck passes, all criteria met
   - **Feedback Loop**: Returns work to developer if verification fails

5. **Tester** 🧪
   - **Role**: Runs comprehensive test suite before PR creation
   - **Actions**: Unit tests, integration tests, e2e tests (if present)
   - **Quality Gates**: Coverage checks, linting, build verification

6. **PR Creator** 📝
   - **Role**: Creates or updates pull request
   - **Pre-PR Checks**: Freshness validation, rebase if stale, conflict detection
   - **PR Description**: Detailed summary, linked issues, test notes
   - **Coordination**: Labels issue, updates progress

7. **Reviewer** 👁️
   - **Role**: Automated code review before human review
   - **Checks**: Code quality, test coverage, security patterns
   - **Feedback**: Posts review comments on PR
   - **Final Step**: Marks workflow complete, posts completion comment

### Bug Fix Workflow (`bug-fix`)

Systematic bug resolution pipeline:

1. **Triager** 🔍
   - **Role**: Analyzes bug reports, reproduces issues
   - **Claims work**: Assigns issue atomically
   - **Classification**: Severity (critical/high/medium/low)
   - **Output**: Reproduction steps, affected files, problem statement

2. **Investigator** 🕵️
   - **Role**: Traces root cause through codebase
   - **Actions**: Code path analysis, dependency checks, log review
   - **Output**: Root cause analysis, fix strategy

3. **Setup** 🔧
   - **Role**: Prepares bugfix environment
   - **Branch**: Creates `bugfix/<issue>-<slug>`

4. **Fixer** 🛠️
   - **Role**: Implements fix with regression tests
   - **Requirements**: Test that demonstrates bug, test that validates fix
   - **Commit**: References issue number for auto-close

5. **Verifier** ✅
   - **Role**: Validates fix resolves issue without breaking existing functionality
   - **Checks**: Bug-specific test passes, regression suite passes

6. **PR Creator & Reviewer** (same as feature-dev)

### Security Audit Workflow (`security-audit`)

Comprehensive security scanning and remediation:

1. **Scanner** 🔐
   - **Role**: Comprehensive security audit
   - **Claims work**: Assigns audit issue
   - **Scans**: Injection vulns, auth issues, secrets, dependencies, headers
   - **Tools**: `npm audit`, manual code review, pattern matching
   - **Output**: Prioritized vulnerability list with evidence

2. **Prioritizer** 📊
   - **Role**: Risk assessment and fix ordering
   - **Criteria**: Severity, exploitability, ease of fix
   - **Output**: Ordered fix plan, grouped by related areas

3. **Setup** 🔧
   - **Role**: Prepares security fix environment
   - **Branch**: Creates `security/<issue>-<slug>`

4. **Fixer** 🛠️
   - **Role**: Implements security fixes
   - **Standards**: Fixes vulnerabilities, adds preventive patterns
   - **Documentation**: Security notes in PR description

5. **Verifier** ✅
   - **Role**: Validates fixes without introducing new issues
   - **Checks**: Vulnerability remediated, no new vulns introduced

6. **Tester** 🧪
   - **Role**: Security-focused testing
   - **Actions**: Attack simulation, edge case testing
   - **Tools**: Security test suites, manual verification

7. **PR Creator & Reviewer** (same as feature-dev)

---

## Coordination Mechanisms

These workflows implement sophisticated coordination to prevent collisions when multiple agents work on the same repository:

### 1. **Atomic Claiming**
- Issues are assigned using `gh issue edit --add-assignee`
- Agents check for existing assignees before claiming
- If already assigned → abort to prevent collision

### 2. **Concurrency Limiting**
- Maximum concurrent workflows per repo (default: 3)
- Checked via `🟢 workflow-active` label count
- Agents wait or queue if limit reached

### 3. **File Overlap Detection**
- Queries open PRs for changed files
- Compares with estimated changes for new work
- Warns if >50% file overlap detected

### 4. **TTL-Based Unclaiming**
- Claims include expiry timestamp (default: 4 hours)
- External cron/monitor can auto-unassign expired claims
- Prevents abandoned work from blocking issues forever

### 5. **Progress Heartbeats**
- Agents post progress updates every 10 minutes
- Includes current story, run ID, timestamp
- Enables detection of stalled workflows

### 6. **Standardized Branch Naming**
- `feature/<issue>-<slug>`
- `bugfix/<issue>-<slug>`
- `security/<issue>-<slug>`
- Makes mapping obvious, prevents name collisions

### 7. **Pre-PR Freshness Checks**
- Fetches latest `main` before creating PR
- Auto-rebases if branch is stale
- Re-runs tests after rebase

### 8. **Conflict Detection**
- Test-merges `main` before opening PR
- Attempts auto-resolution if conflicts detected
- Falls back to human if resolution fails

### 9. **Failure Reporting**
- Posts failure comment on crash
- Unassigns issue automatically
- Labels issue `🔴 workflow-failed`

### 10. **Architectural Decision Log**
- Agents read `docs/decisions/*.md` before planning
- Post-implementation ADRs written for significant changes
- Enables coordination on design decisions

---

## How to Use

### Installation

1. **Clone this repository:**
   ```bash
   git clone https://github.com/zelki-agent/antfarm-workflows.git
   cd antfarm-workflows
   ```

2. **Link workflows to antfarm:**
   ```bash
   # Option 1: Symlink (recommended for development)
   ln -s $(pwd)/workflows ~/.openclaw/workspace/antfarm/workflows
   
   # Option 2: Copy (for production deployment)
   cp -r workflows ~/.openclaw/workspace/antfarm/workflows/
   ```

3. **Verify installation:**
   ```bash
   ls ~/.openclaw/workspace/antfarm/workflows/
   # Should show: feature-dev  bug-fix  security-audit
   ```

### Running Workflows

#### Feature Development

```bash
# Start a feature workflow
node ~/.openclaw/workspace/antfarm/dist/cli/cli.js workflow run feature-dev \
  "Implement user authentication for zelki/my-app (issue #42)"

# The workflow will:
# 1. Claim issue #42 atomically
# 2. Break feature into user stories
# 3. Implement stories iteratively
# 4. Create PR when complete
# 5. Post review feedback
```

#### Bug Fix

```bash
# Start a bug fix workflow
node ~/.openclaw/workspace/antfarm/dist/cli/cli.js workflow run bug-fix \
  "Fix null pointer exception in user search - zelki/my-app issue #55"

# The workflow will:
# 1. Claim issue #55
# 2. Triage: reproduce bug, classify severity
# 3. Investigate root cause
# 4. Implement fix with regression tests
# 5. Create PR
```

#### Security Audit

```bash
# Start a security audit workflow
node ~/.openclaw/workspace/antfarm/dist/cli/cli.js workflow run security-audit \
  "Security audit for zelki/my-app (issue #100)"

# The workflow will:
# 1. Claim issue #100
# 2. Run comprehensive security scan
# 3. Prioritize findings by severity
# 4. Implement fixes for all findings
# 5. Create PR with security notes
```

### Monitoring Progress

```bash
# Check workflow status
node ~/.openclaw/workspace/antfarm/dist/cli/cli.js workflow status "Implement user authentication"

# View detailed logs
node ~/.openclaw/workspace/antfarm/dist/cli/cli.js logs <run-id>

# View logs for specific run (get run-id from status)
node ~/.openclaw/workspace/antfarm/dist/cli/cli.js logs 60734958-5f7c-4162-afd7-572baca1996c

# Watch progress in real-time (on GitHub)
# - Check the issue for progress comments
# - Look for the 🟢 workflow-active label
```

### Multiple Agents / Parallel Work

These workflows are designed for multiple independent agents working on the same repo:

```bash
# Agent 1 (Machine A)
antfarm workflow run feature-dev "Add dark mode - issue #10"

# Agent 2 (Machine B) - can run simultaneously
antfarm workflow run bug-fix "Fix logout crash - issue #11"

# Agent 3 (Machine C) - will wait if concurrency limit reached
antfarm workflow run feature-dev "Add export feature - issue #12"
# ⏳ Waits if 3+ workflows already active on this repo
```

**Coordination automatically handles:**
- ✅ No duplicate work (atomic claiming)
- ✅ No merge conflicts (freshness checks + auto-rebase)
- ✅ No resource exhaustion (concurrency limits)
- ✅ No abandoned work (TTL + auto-unclaim)
- ✅ No semantic overlap (file overlap detection + warnings)

---

## Workflow Reference

### Environment Variables

Set these in your OpenClaw config or shell:

```bash
# Run ID (auto-set by antfarm, but can override)
export ANTFARM_RUN_ID="custom-run-id"

# Concurrency limit (default: 3)
export ANTFARM_MAX_CONCURRENT=5

# Claim TTL in hours (default: 4)
export ANTFARM_CLAIM_TTL_HOURS=6

# Heartbeat interval in minutes (default: 10)
export ANTFARM_HEARTBEAT_INTERVAL=5
```

### Agent Configuration Paths

Each workflow's agents are configured in:
```
workflows/
├── feature-dev/
│   ├── agents/
│   │   ├── planner/
│   │   │   ├── AGENTS.md    ← Agent instructions
│   │   │   ├── SOUL.md      ← Personality
│   │   │   └── IDENTITY.md  ← Metadata
│   │   ├── developer/
│   │   ├── verifier/
│   │   ├── tester/
│   │   └── reviewer/
│   └── workflow.yml
├── bug-fix/
│   └── agents/ ...
└── security-audit/
    └── agents/ ...
```

### Customization

#### Modify Agent Behavior
Edit `workflows/<workflow>/agents/<agent>/AGENTS.md` to change:
- Process steps
- Acceptance criteria
- Coordination rules
- Output format

#### Add a New Workflow
1. Create `workflows/my-workflow/`
2. Add `workflow.yml` defining pipeline stages
3. Create agent directories with AGENTS.md, SOUL.md, IDENTITY.md
4. Test with a simple task

#### Adjust Concurrency Limits
Per-repo limits can be set via GitHub repository variables:
```bash
gh variable set ANTFARM_MAX_CONCURRENT --body "5" --repo owner/repo
```

---

## Troubleshooting

### Workflow Won't Start

**Issue**: "Concurrency limit reached"
```bash
# Check active workflows
gh issue list --repo owner/repo --label "🟢 workflow-active"

# Manually remove stale active labels if needed
gh issue edit <issue-num> --repo owner/repo --remove-label "🟢 workflow-active"
```

**Issue**: "Issue already assigned"
```bash
# Check who has it assigned
gh issue view <issue-num> --repo owner/repo

# Manually unassign if stale (>4 hours with no progress)
gh issue edit <issue-num> --repo owner/repo --remove-assignee <username>
```

### Workflow Failed Mid-Run

**Check failure logs:**
```bash
# View logs for the run
antfarm logs <run-id>

# Check GitHub issue for failure comment
gh issue view <issue-num> --repo owner/repo --comments
```

**Resume workflow:**
```bash
# If safe to retry, manually unassign and re-run
gh issue edit <issue-num> --remove-assignee "@me" --remove-label "🔴 workflow-failed"
antfarm workflow run feature-dev "Same task again"
```

### Merge Conflicts

**Automatic resolution failed:**
```bash
# Workflows will post a comment when conflicts can't be auto-resolved
# Check the PR for conflict markers
gh pr view <pr-num> --repo owner/repo

# Manually resolve:
git checkout feature/<issue>-<slug>
git fetch origin main
git rebase origin/main
# Resolve conflicts, then:
git rebase --continue
git push --force-with-lease
```

### Stale Branch

**PR shows "outdated branch" warning:**
```bash
# Workflows auto-rebase before creating PR, but if main advanced after:
gh pr checkout <pr-num>
git fetch origin main
git rebase origin/main
npm test  # or appropriate test command
git push --force-with-lease
```

### Permission Errors

**"Resource not accessible by integration":**
- Check GitHub token permissions (see [Setup Requirements](#github-token-permissions))
- Refresh token: `gh auth refresh -h github.com -s repo,write:discussion,project`

**"refusing to allow a personal access token to create or update workflow":**
- This is expected - workflows cannot modify GitHub Actions
- Workflow YAML changes need manual PR

### Debug Mode

Enable verbose logging:
```bash
# Set in OpenClaw config or environment
export DEBUG="antfarm:*"
export ANTFARM_VERBOSE=true

# Run workflow
antfarm workflow run feature-dev "Task description"
```

---

## Contributing

This is a private configuration repository. For bugs/features in the core antfarm system, see the main antfarm repository.

To propose workflow improvements:
1. Test changes in your fork
2. Document the enhancement
3. Share results with the team

---

## License

Proprietary - authorized use only.

## Support

For questions or issues:
- Check troubleshooting section above
- Review antfarm documentation
- Contact: [your-support-channel]

---

**Version**: 1.0.0  
**Last Updated**: 2026-02-15  
**Maintained by**: zelki-agent
