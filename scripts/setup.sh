#!/bin/bash

# ============================================
# Traefik Complete Setup Script
# ============================================
# Usage:
#   ./scripts/setup.sh                    # Uses existing .env
#   ./scripts/setup.sh echo.misavan.net   # Clones config from branch

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
CONFIGS_REPO="https://github.com/reluparfene/traefik-configs.git"
CONFIG_DIR="/opt/traefik-config"

# Functions
print_header() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}   $1${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

check_command() {
    if ! command -v $1 &> /dev/null; then
        print_error "$1 is not installed!"
        exit 1
    fi
}

# ============================================
# STEP 0: Run validation checks first
# ============================================
print_header "Traefik Setup - Starting Validation"

# Check if we're in the right directory
if [ ! -f "docker-compose.yml" ]; then
    print_error "Must run from Traefik directory root!"
    echo "  Current directory: $(pwd)"
    exit 1
fi

# Run pre-flight checks first (system level checks)
if [ -f "$SCRIPT_DIR/preflight-check.sh" ]; then
    print_warning "Running system pre-flight checks..."
    if ! "$SCRIPT_DIR/preflight-check.sh"; then
        print_error "Pre-flight checks failed!"
        echo ""
        echo "Fix the system errors above and run setup.sh again."
        exit 1
    fi
    print_success "System checks passed"
fi

# ============================================
# STEP 1: Handle configuration
# ============================================
print_header "Configuration Setup"

# If branch name provided, get config from that branch
if [ ! -z "$1" ]; then
    SERVER_BRANCH=$1
    print_warning "Setting up with config from branch: $SERVER_BRANCH"

    # Check for token
    if [ -z "$GITHUB_TOKEN" ]; then
        print_warning "No GITHUB_TOKEN set. Assuming public repository."
        CONFIGS_URL=$CONFIGS_REPO
    else
        CONFIGS_URL=$(echo $CONFIGS_REPO | sed "s|https://|https://${GITHUB_TOKEN}@|")
    fi

    # Clone or update config
    if [ ! -d "$CONFIG_DIR" ]; then
        print_warning "Cloning configuration..."
        if ! git clone -b "$SERVER_BRANCH" "$CONFIGS_URL" "$CONFIG_DIR" 2>/dev/null; then
            print_error "Failed to clone branch '$SERVER_BRANCH'"
            exit 1
        fi
    else
        print_warning "Updating configuration..."
        cd "$CONFIG_DIR"
        CURRENT=$(git branch --show-current)
        if [ "$CURRENT" != "$SERVER_BRANCH" ]; then
            git checkout "$SERVER_BRANCH"
        fi
        git pull
        cd - > /dev/null
    fi

    # Link .env
    if [ -f .env ] && [ ! -L .env ]; then
        cp .env .env.backup
        print_warning "Backed up existing .env to .env.backup"
    fi
    ln -sf "$CONFIG_DIR/.env" .env
    print_success "Configuration linked from branch: $SERVER_BRANCH"
fi

# Check for .env
if [ ! -f .env ]; then
    if [ -f .env.example ]; then
        print_warning ".env not found. Creating from template..."
        cp .env.example .env
        print_error "Please edit .env with your configuration!"
        echo "  nano .env"
        echo ""
        echo "After editing, run setup.sh again."
        exit 1
    else
        print_error "No .env file found and no .env.example template!"
        exit 1
    fi
fi

# Run configuration validator after .env is ensured to exist
if [ -f "$SCRIPT_DIR/validate-config.sh" ]; then
    print_warning "Validating configuration..."
    if ! "$SCRIPT_DIR/validate-config.sh"; then
        print_error "Configuration validation failed!"
        echo ""
        echo "Fix the errors in .env and run setup.sh again."
        exit 1
    fi
    print_success "Configuration is valid"
fi

# Load environment (validation already done by validate-config.sh)
source .env
print_success "Environment loaded"

# ============================================
# STEP 3: Create Docker networks
# ============================================
print_header "Creating Docker Networks"

create_network() {
    local name=$1
    local subnet=$2
    local internal=$3

    # Check if network exists
    if docker network inspect "$name" &>/dev/null; then
        local existing_subnet=$(docker network inspect -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}' "$name")
        if [ "$existing_subnet" == "$subnet" ]; then
            print_success "Network '$name' exists with correct subnet"
        else
            print_error "CONFLICT: Network '$name' already exists with different subnet!"
            echo ""
            echo "  Expected subnet: $subnet"
            echo "  Current subnet:  $existing_subnet"
            echo ""
            echo "  Solutions:"
            echo "  1. Remove the existing network (if not in use):"
            echo "     docker network rm $name"
            echo ""
            echo "  2. Or check what's using it:"
            echo "     docker network inspect $name"
            echo ""
            print_error "Setup aborted due to network conflict!"
            exit 1
        fi
        return
    fi

    # Check for subnet conflict - FAIL if exists
    local conflicts=$(docker network ls -q | xargs -r docker network inspect -f '{{range .IPAM.Config}}{{.Subnet}}{{end}} {{.Name}}' 2>/dev/null | grep "^$subnet " | cut -d' ' -f2)
    if [ ! -z "$conflicts" ]; then
        print_error "SUBNET CONFLICT: Cannot create network '$name'!"
        echo ""
        echo "  Subnet $subnet is already in use by network: $conflicts"
        echo ""
        echo "  This template requires the following subnets to be available:"
        echo "    - 172.20.0.0/24 for traefik-public"
        echo "    - 172.21.0.0/24 for app-frontend"
        echo "    - 172.22.0.0/24 for db-backend"
        echo "    - 172.23.0.0/24 for management"
        echo ""
        echo "  Solutions:"
        echo "  1. Remove the conflicting network (if not in use):"
        echo "     docker network rm $conflicts"
        echo ""
        echo "  2. Or check what's using it:"
        echo "     docker network inspect $conflicts"
        echo ""
        print_error "Setup aborted due to subnet conflict!"
        exit 1
    fi

    # Create network
    local cmd="docker network create --driver=bridge --subnet=$subnet"
    if [ "$internal" == "true" ]; then
        cmd="$cmd --internal"
    fi
    cmd="$cmd $name"

    if $cmd; then
        print_success "Created network: $name ($subnet) $([ "$internal" == "true" ] && echo "[INTERNAL]")"
    else
        print_error "Failed to create network: $name"
        echo ""
        echo "  This might be due to:"
        echo "  - Docker daemon issues"
        echo "  - Permission problems"
        echo "  - Invalid subnet format"
        echo ""
        echo "  Try running: docker network create --subnet=$subnet $name"
        echo ""
        print_error "Setup aborted due to network creation failure!"
        exit 1
    fi
}

# Create networks
create_network "traefik-public" "${NETWORK_SUBNET_PUBLIC:-172.20.0.0/24}" "false"
create_network "app-frontend" "${NETWORK_SUBNET_FRONTEND:-172.21.0.0/24}" "false"
create_network "db-backend" "${NETWORK_SUBNET_BACKEND:-172.22.0.0/24}" "true"
create_network "management" "${NETWORK_SUBNET_MANAGEMENT:-172.23.0.0/24}" "true"

# ============================================
# STEP 4: Setup Traefik configuration
# ============================================
print_header "Setting up Traefik Configuration"

# Create directories
mkdir -p data/configurations logs

# Process template if exists
if [ -f config/traefik.yml.template ]; then
    # Check envsubst
    if ! command -v envsubst &> /dev/null; then
        print_warning "Installing envsubst..."
        apt-get update && apt-get install -y gettext-base
    fi

    print_warning "Processing configuration template..."

    # Export all vars for envsubst
    set -a
    source .env
    set +a

    # Process template
    envsubst < config/traefik.yml.template > data/traefik.yml

    # Verify substitution worked
    if grep -q '${DOMAIN}' data/traefik.yml; then
        print_warning "Using fallback substitution method..."
        cp config/traefik.yml.template data/traefik.yml
        sed -i "s/\${DOMAIN}/$DOMAIN/g" data/traefik.yml
        sed -i "s/\${SUBDOMAIN_TRAEFIK:-traefik.\${DOMAIN}}/${SUBDOMAIN_TRAEFIK:-traefik.$DOMAIN}/g" data/traefik.yml
        sed -i "s/\${ACME_EMAIL}/$ACME_EMAIL/g" data/traefik.yml
        sed -i "s/\${TRAEFIK_DASHBOARD_ENABLED:-true}/true/g" data/traefik.yml
    fi

    print_success "Configuration processed"
fi

# Copy dynamic configs
if [ -d config/dynamic ]; then
    cp -r config/dynamic/* data/configurations/ 2>/dev/null || true
    print_success "Dynamic configurations copied"
fi

# ============================================
# STEP 5: Setup SSL certificate storage
# ============================================
print_header "Setting up Certificate Storage"

if [ ! -f data/acme.json ]; then
    touch data/acme.json
    chmod 600 data/acme.json
    print_success "Certificate storage created"
else
    chmod 600 data/acme.json
    print_success "Certificate storage verified"
fi

# ============================================
# STEP 6: Start services
# ============================================
print_header "Starting Services"

# Validate docker-compose
if ! docker-compose config >/dev/null 2>&1; then
    print_error "Docker Compose configuration invalid!"
    docker-compose config
    exit 1
fi

# Start
docker-compose up -d

# ============================================
# STEP 7: Summary
# ============================================
print_header "Setup Complete!"

# Show status
docker-compose ps

echo ""
echo "Configuration:"
echo "  Domain: $DOMAIN"
echo "  Dashboard: https://traefik.$DOMAIN"
echo "  Email: $ACME_EMAIL"

if [ ! -z "$SERVER_BRANCH" ]; then
    echo "  Config branch: $SERVER_BRANCH"
fi

echo ""
echo "Next steps:"
echo "  1. Check logs: docker-compose logs -f traefik"
echo "  2. Access dashboard: https://traefik.$DOMAIN"
echo "  3. Monitor certificates: watch docker exec traefik-proxy cat /acme.json | jq ."

echo ""
print_success "Traefik is ready!"