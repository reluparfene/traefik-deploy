#!/bin/bash

# ============================================
# Traefik Template - Automated Setup Script
# ============================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
print_header() {
    echo -e "\n${BLUE}============================================${NC}"
    echo -e "${BLUE}   $1${NC}"
    echo -e "${BLUE}============================================${NC}\n"
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

# Get script directory and project root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Change to project root
cd "$PROJECT_ROOT"

# Main Setup
print_header "Traefik Template Setup"

# Check installation location
if [[ "$PWD" != "/opt/traefik" ]]; then
    print_warning "Current directory: $PWD"
    print_warning "Recommended production location: /opt/traefik"
    print_warning "See docs/INSTALLATION_LOCATION.md for details"
    echo ""
fi

# 1. Check prerequisites
echo "Checking prerequisites..."
check_command docker
check_command docker-compose
print_success "Prerequisites verified"

# 2. Check for .env file
if [ ! -f .env ]; then
    if [ -f .env.example ]; then
        print_warning ".env file not found. Creating from template..."
        cp .env.example .env
        print_warning "Please edit .env file with your configuration!"
        echo "Press Enter when ready to continue..."
        read
    else
        print_error ".env.example not found!"
        exit 1
    fi
else
    print_success ".env file found"
fi

# 3. Load environment variables
source .env

# 4. Validate required variables
print_header "Validating Configuration"

REQUIRED_VARS=(
    "DOMAIN"
    "ACME_EMAIL"
    "CLOUDNS_SUB_AUTH_ID"
    "CLOUDNS_AUTH_PASSWORD"
)

for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        print_error "$var is not set in .env file!"
        exit 1
    fi
done
print_success "Configuration validated"

# 5. Create Docker networks
print_header "Creating Docker Networks"

./scripts/setup-network-segmentation.sh

# 6. Setup Traefik configuration
print_header "Setting up Traefik Configuration"

# Create config directory structure
mkdir -p data/configurations
mkdir -p logs

# Process traefik.yml template
if [ -f config/traefik.yml.template ]; then
    print_warning "Processing traefik.yml template..."
    envsubst < config/traefik.yml.template > data/traefik.yml
    print_success "traefik.yml created"
else
    print_warning "Using existing traefik.yml"
fi

# Copy dynamic configurations
if [ -d config/dynamic ]; then
    cp -r config/dynamic/* data/configurations/
    print_success "Dynamic configurations copied"
fi

# 7. Setup ACME storage
print_header "Setting up Certificate Storage"

if [ ! -f data/acme.json ]; then
    touch data/acme.json
    chmod 600 data/acme.json
    print_success "acme.json created with correct permissions"
else
    print_success "acme.json already exists"
fi

# 8. Create backup directory
mkdir -p backups
print_success "Backup directory created"

# 9. Generate basic auth password if needed
if [ -z "$TRAEFIK_BASIC_AUTH_PASSWORD" ] || [ "$TRAEFIK_BASIC_AUTH_PASSWORD" == '$$apr1$$your$$encrypted$$password' ]; then
    print_header "Generating Basic Auth Password"
    echo -n "Enter password for Traefik dashboard user '$TRAEFIK_BASIC_AUTH_USER': "
    read -s password
    echo

    if command -v htpasswd &> /dev/null; then
        ENCRYPTED_PASS=$(htpasswd -nb $TRAEFIK_BASIC_AUTH_USER $password | sed -e s/\\$/\\$\\$/g)
        sed -i "s|TRAEFIK_BASIC_AUTH_PASSWORD=.*|TRAEFIK_BASIC_AUTH_PASSWORD=$ENCRYPTED_PASS|" .env
        print_success "Password encrypted and saved to .env"
    else
        print_warning "htpasswd not found. Please install apache2-utils and manually generate password"
    fi
fi

# 10. Create docker-compose override if needed
if [ ! -f docker-compose.override.yml ] && [ -f docker-compose.override.yml.example ]; then
    cp docker-compose.override.yml.example docker-compose.override.yml
    print_success "docker-compose.override.yml created"
fi

# 11. Final validation
print_header "Final Validation"

docker-compose config > /dev/null 2>&1
if [ $? -eq 0 ]; then
    print_success "Docker Compose configuration is valid"
else
    print_error "Docker Compose configuration validation failed!"
    exit 1
fi

# 12. Summary
print_header "Setup Complete!"

echo "Next steps:"
echo "1. Review your .env configuration"
echo "2. Start Traefik with: docker-compose up -d"
echo "3. Check logs with: docker-compose logs -f"
echo "4. Access dashboard at: https://${SUBDOMAIN_TRAEFIK:-traefik.$DOMAIN}"
echo ""
echo "For examples, check the examples/ directory"
echo ""
print_success "Setup completed successfully!"