# Antfarm Workflows

Multi-agent workflow orchestration for OpenClaw. These workflow definitions enable autonomous coding agents to handle feature development, bug fixes, and security audits.

## What's Included

### Feature Development (`workflows/feature-dev/`)
- **Planner** — Breaks tasks into user stories
- **Setup** — Prepares development environment
- **Developer** — Implements user stories iteratively
- **Verifier** — Validates each story against acceptance criteria
- **Tester** — Runs test suites
- **Reviewer** — Code reviews the final implementation

### Bug Fix (`workflows/bug-fix/`)
- **Triager** — Analyzes bug reports, reproduces issues, classifies severity
- **Investigator** — Traces root cause through the codebase
- **Setup** — Prepares fix environment
- **Fixer** — Implements the fix with tests
- **Verifier** — Validates the fix

### Security Audit (`workflows/security-audit/`)
- **Scanner** — Comprehensive security scan (injection, auth, secrets, dependencies)
- **Prioritizer** — Classifies and prioritizes findings
- **Setup** — Prepares fix environment
- **Fixer** — Implements security fixes
- **Verifier** — Validates fixes don't introduce regressions
- **Tester** — Security-focused testing

## Installation

1. **Clone this repo:**
   ```bash
   git clone https://github.com/zelki-agent/antfarm-workflows.git
   cd antfarm-workflows
   ```

2. **Install antfarm (if not already installed):**
   ```bash
   # From npm (when published)
   npm install -g @zelki/antfarm
   
   # Or from source
   git clone https://github.com/zelki/antfarm.git
   cd antfarm
   npm install
   npm run build
   npm link
   ```

3. **Link these workflows:**
   ```bash
   # Option 1: Copy to antfarm installation
   cp -r workflows/* $(npm root -g)/@zelki/antfarm/workflows/
   
   # Option 2: Use workspace symlink
   ln -s $(pwd)/workflows ~/.openclaw/workspace/antfarm/workflows
   ```

## Usage

### Feature Development
```bash
antfarm workflow run feature-dev "Implement user authentication for zelki/my-app"
```

### Bug Fix
```bash
antfarm workflow run bug-fix "Fix null pointer exception in user search - issue #42"
```

### Security Audit
```bash
antfarm workflow run security-audit "Security audit for zelki/my-app"
```

### Monitor Progress
```bash
# Check status
antfarm workflow status "Implement user authentication"

# View logs
antfarm logs <run-id>
```

## Key Features

### Workflow Claiming (Collision Prevention)
Each workflow automatically claims the related GitHub issue/PR before starting work, preventing parallel workflow collisions. Agents leave a comment with:
- Run ID
- Workflow type
- Start timestamp

### Story-Based Iteration
Feature-dev planner breaks tasks into independently testable user stories. Each story:
- Must fit in one context window
- Has mechanical acceptance criteria
- Includes tests
- Is verified before advancing

### Self-Verifying
Verifier agents check:
- All acceptance criteria met
- Tests pass
- Typecheck passes
- No new errors introduced

### Auto-PR Creation
Workflows automatically:
- Create appropriately named branches
- Commit with structured messages
- Open PRs with detailed descriptions
- Link related issues

## Agent Configuration

Each workflow lives in `workflows/<workflow-name>/agents/<agent-name>/`:
- `AGENTS.md` — Agent instructions and process
- `SOUL.md` — Agent personality/tone
- `IDENTITY.md` — Agent metadata

## Customization

### Adding a New Workflow
1. Create `workflows/my-workflow/`
2. Define agents in `workflows/my-workflow/agents/`
3. Each agent needs `AGENTS.md` with clear instructions
4. Register workflow in antfarm config

### Modifying Agent Behavior
Edit the `AGENTS.md` file for the specific agent. Changes take effect immediately on next workflow run.

## Requirements

- OpenClaw with agent configuration
- GitHub CLI (`gh`) authenticated
- Node.js 18+
- Git

## Contributing

This is a private configuration repo. For antfarm core issues/features, see the main antfarm repository.

## License

Proprietary - for authorized use only.
