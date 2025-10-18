#!/usr/bin/env bash
# Generate conventional commit messages using AI
# Usage: ./git_commit_msg.sh

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}🌌 Thanos Git Commit Message Generator${NC}\n"

# Check if we're in a git repo
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo -e "${YELLOW}❌ Not a git repository${NC}"
    exit 1
fi

# Check if there are staged changes
if ! git diff --cached --quiet 2>/dev/null; then
    echo -e "${GREEN}📝 Staged changes detected${NC}\n"
else
    echo -e "${YELLOW}⚠️  No staged changes. Stage some files first with 'git add'${NC}"
    exit 1
fi

# Get the diff
DIFF=$(git diff --cached)

# Create prompt
PROMPT="Generate a conventional commit message for these changes. Use format: <type>: <description>

Types: feat, fix, docs, style, refactor, perf, test, chore

Keep it concise (50 chars max for first line).

Changes:
${DIFF}"

echo -e "${BLUE}⏳ Generating commit message...${NC}\n"

# Call Thanos
COMMIT_MSG=$(thanos complete "${PROMPT}" 2>/dev/null || echo "")

if [ -z "$COMMIT_MSG" ]; then
    echo -e "${YELLOW}❌ Failed to generate commit message${NC}"
    echo "Make sure Thanos is installed and a provider is available"
    echo "Run: thanos discover"
    exit 1
fi

# Clean up the message (remove markdown, quotes, etc.)
COMMIT_MSG=$(echo "$COMMIT_MSG" | sed 's/^```.*$//' | sed 's/^["`'"'"']//;s/["`'"'"']$//' | head -n 3)

# Show the generated message
echo -e "${GREEN}✨ Generated commit message:${NC}\n"
echo "$COMMIT_MSG"
echo ""

# Ask user if they want to use it
read -p "Use this commit message? (y/n) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Commit with the generated message
    git commit -m "$COMMIT_MSG"
    echo -e "\n${GREEN}✅ Committed!${NC}"
else
    echo -e "${YELLOW}Commit cancelled${NC}"
    exit 0
fi
