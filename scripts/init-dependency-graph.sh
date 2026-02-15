#!/usr/bin/env bash
# Initialize dependency-graph.json on main branch if it doesn't exist
# Usage: ./init-dependency-graph.sh <repo-path>

set -euo pipefail

REPO_PATH="${1:-.}"
GRAPH_FILE="$REPO_PATH/dependency-graph.json"

cd "$REPO_PATH"

# Check if we're in a git repo
if ! git rev-parse --git-dir > /dev/null 2>&1; then
  echo "ERROR: Not a git repository: $REPO_PATH" >&2
  exit 1
fi

# Check if dependency-graph.json exists on main branch
if git show origin/main:dependency-graph.json > /dev/null 2>&1; then
  echo "✓ dependency-graph.json already exists on origin/main"
  exit 0
fi

# Get repo name from git remote
REPO_NAME=$(git remote get-url origin | sed 's/.*[:/]\(.*\)\.git$/\1/' | sed 's/.*\///')
REPO_OWNER=$(git remote get-url origin | sed 's/.*[:/]\(.*\)\/.*\.git$/\1/')
REPO_FULL="${REPO_OWNER}/${REPO_NAME}"

# Create initial dependency graph
cat > "$GRAPH_FILE" <<EOF
{
  "version": 2,
  "stories": [],
  "last_updated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "metadata": {
    "repo": "$REPO_FULL",
    "initialized": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "description": "Antfarm workflow dependency graph - tracks story status and dependencies for parallel task execution"
  }
}
EOF

echo "✓ Created dependency-graph.json"

# Commit and push to main
git checkout main 2>/dev/null || git checkout -b main
git add dependency-graph.json

if git diff --staged --quiet; then
  echo "✓ dependency-graph.json already committed"
  exit 0
fi

git commit -m "chore: Initialize Antfarm dependency graph on main

- Graph lives exclusively on main branch (not feature branches)
- Updated directly by coordination scripts (bypasses PR process)
- Enables parallel workflow execution with collision prevention
- See: https://github.com/zelki-agent/antfarm-workflows/blob/main/DEPENDENCY-GRAPH-ARCHITECTURE.md"

echo "✓ Committed dependency-graph.json to main"

# Push to origin/main
if git push origin main 2>/dev/null; then
  echo "✓ Pushed to origin/main"
else
  echo "⚠ Failed to push to origin/main (may need manual push)"
  echo "  Run: cd $REPO_PATH && git push origin main"
  exit 1
fi

echo ""
echo "✓ Dependency graph initialized successfully"
echo "  Location: $(git remote get-url origin | sed 's/\.git$//')/blob/main/dependency-graph.json"
