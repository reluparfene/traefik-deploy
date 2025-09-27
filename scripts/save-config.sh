#!/bin/bash

# ============================================
# Configuration Backup Script for Server Repositories
# Use this after creating repository from template
# ============================================

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "============================================"
echo "   Configuration Backup for Server Repository"
echo "============================================"
echo ""

# Check if .env exists
if [ ! -f .env ]; then
    echo -e "${RED}❌ .env file not found!${NC}"
    echo "Please create .env from .env.example first"
    exit 1
fi

# Check if git repository
if [ ! -d .git ]; then
    echo -e "${RED}❌ Not a git repository!${NC}"
    echo "This should be run in your server repository created from template"
    exit 1
fi

# Remove .env from .gitignore if present
if grep -q "^\.env$" .gitignore 2>/dev/null; then
    echo -e "${YELLOW}Updating .gitignore to allow .env backup...${NC}"
    sed -i '/^\.env$/d' .gitignore
    echo -e "${GREEN}✅ .gitignore updated${NC}"
else
    echo -e "${GREEN}✅ .env already allowed in git${NC}"
fi

# Get hostname for commit message
HOSTNAME=$(hostname)
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Stage changes
echo -e "${YELLOW}Staging configuration files...${NC}"
git add .env
git add .gitignore

# Add other configuration files if they exist
[ -f docker-compose.override.yml ] && git add docker-compose.override.yml
[ -d data/configurations ] && git add data/configurations/

# Check if there are changes to commit
if git diff --cached --quiet; then
    echo -e "${YELLOW}No changes to commit${NC}"
else
    # Commit
    echo -e "${YELLOW}Committing configuration...${NC}"
    git commit -m "Configuration backup from $HOSTNAME at $TIMESTAMP"
    echo -e "${GREEN}✅ Configuration committed${NC}"
fi

# Push to remote
echo -e "${YELLOW}Pushing to GitHub...${NC}"
if git push; then
    echo -e "${GREEN}✅ Configuration backed up to GitHub${NC}"
else
    echo -e "${RED}❌ Failed to push. Please check your remote configuration${NC}"
    echo "You can manually push later with: git push"
fi

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}   Configuration Backup Complete!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "Your configuration is now saved in your private GitHub repository."
echo "In case of disaster, just clone this repository and run:"
echo "  ./scripts/setup.sh && docker-compose up -d"