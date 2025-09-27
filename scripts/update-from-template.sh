#!/bin/bash

# ============================================
# Update from Template Repository
# Use this to pull updates from original template
# ============================================

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Configuration
TEMPLATE_REPO=${TEMPLATE_REPO:-"https://github.com/ORIGINAL_OWNER/traefik-template.git"}
TEMPLATE_REMOTE="template"

echo "============================================"
echo "   Update from Template Repository"
echo "============================================"
echo ""

# Check if git repository
if [ ! -d .git ]; then
    echo -e "${RED}❌ Not a git repository!${NC}"
    exit 1
fi

# Check if template remote exists
if ! git remote | grep -q "^${TEMPLATE_REMOTE}$"; then
    echo -e "${YELLOW}Adding template repository as remote...${NC}"
    echo "Template: $TEMPLATE_REPO"
    git remote add $TEMPLATE_REMOTE $TEMPLATE_REPO
    echo -e "${GREEN}✅ Template remote added${NC}"
else
    echo -e "${GREEN}✅ Template remote already configured${NC}"
fi

# Fetch latest from template
echo -e "${YELLOW}Fetching latest template...${NC}"
git fetch $TEMPLATE_REMOTE

# Show what's new
echo ""
echo -e "${BLUE}Available template updates:${NC}"
git log HEAD..$TEMPLATE_REMOTE/main --oneline --no-decorate || echo "No new updates"

echo ""
echo "Choose update method:"
echo "1) Merge all updates (keeps your customizations)"
echo "2) Update specific files only (safer)"
echo "3) View differences first"
echo "4) Cancel"
echo ""
read -p "Your choice [1-4]: " choice

case $choice in
    1)
        echo -e "${YELLOW}Merging all updates from template...${NC}"

        # Backup current state
        git stash push -m "Backup before template update"

        # Merge
        if git merge $TEMPLATE_REMOTE/main --allow-unrelated-histories -m "Merge updates from template"; then
            echo -e "${GREEN}✅ Successfully merged template updates${NC}"
            echo ""
            echo "Please review changes and test before deploying!"
            echo "Your stashed changes can be restored with: git stash pop"
        else
            echo -e "${RED}Merge conflicts detected!${NC}"
            echo "Please resolve conflicts manually, then run:"
            echo "  git commit"
            echo ""
            echo "To abort merge:"
            echo "  git merge --abort"
            echo "  git stash pop"
        fi
        ;;

    2)
        echo ""
        echo "Select files to update:"
        echo "1) Scripts only (./scripts/)"
        echo "2) Docker Compose files"
        echo "3) Configuration templates (./config/)"
        echo "4) Examples (./examples/)"
        echo "5) Documentation (./docs/)"
        echo "6) Custom selection"
        echo ""
        read -p "Your choice [1-6]: " file_choice

        case $file_choice in
            1) FILES="scripts/" ;;
            2) FILES="docker-compose.yml docker-compose.override.yml.example" ;;
            3) FILES="config/" ;;
            4) FILES="examples/" ;;
            5) FILES="docs/ README.md CLAUDE.md" ;;
            6)
                echo "Enter files/directories to update (space-separated):"
                read FILES
                ;;
            *) echo "Invalid choice"; exit 1 ;;
        esac

        echo -e "${YELLOW}Updating: $FILES${NC}"
        for file in $FILES; do
            if git ls-tree $TEMPLATE_REMOTE/main --name-only | grep -q "^$file"; then
                git checkout $TEMPLATE_REMOTE/main -- $file
                echo -e "${GREEN}✅ Updated $file${NC}"
            else
                echo -e "${YELLOW}⚠️  $file not found in template${NC}"
            fi
        done

        echo ""
        echo "Files updated. Review changes with: git diff --cached"
        echo "Commit when ready: git commit -m 'Update from template: $FILES'"
        ;;

    3)
        echo ""
        echo -e "${BLUE}Comparing with template:${NC}"
        echo "---"
        git diff HEAD..$TEMPLATE_REMOTE/main --stat
        echo "---"
        echo ""
        echo "View detailed diff with:"
        echo "  git diff HEAD..$TEMPLATE_REMOTE/main"
        echo ""
        echo "View specific file diff:"
        echo "  git diff HEAD..$TEMPLATE_REMOTE/main -- docker-compose.yml"
        ;;

    4)
        echo "Update cancelled"
        exit 0
        ;;

    *)
        echo "Invalid choice"
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}   Update Process Complete${NC}"
echo -e "${GREEN}============================================${NC}"

# Show current status
echo ""
git status --short