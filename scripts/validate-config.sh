#!/bin/bash

# ============================================
# Configuration Validator for Traefik Template
# Validates .env and all configuration files
# ============================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
ERRORS=0
WARNINGS=0

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
    ((WARNINGS++))
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
    ((ERRORS++))
}

# ============================================
# Check .env Configuration
# ============================================
print_header "Environment Configuration Validation"

if [ ! -f .env ]; then
    print_error ".env file not found!"
    echo "  Create it from template: cp .env.example .env"
    exit 1
fi

# Load environment
set -a
source .env
set +a

# Validate required variables
print_header "Required Variables"

check_var() {
    local var=$1
    local description=$2
    local pattern=$3

    if [ -z "${!var}" ]; then
        print_error "$var is not set - $description"
        return 1
    fi

    if [ ! -z "$pattern" ]; then
        if [[ ! "${!var}" =~ $pattern ]]; then
            print_error "$var has invalid format - $description"
            echo "  Current value: ${!var}"
            return 1
        fi
    fi

    print_success "$var is valid"
    return 0
}

# Domain validation
check_var "DOMAIN" "Main domain (e.g., example.com)" '^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$'

# Email validation
check_var "ACME_EMAIL" "Email for Let's Encrypt certificates" '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'

# DNS Provider credentials
check_var "CLOUDNS_SUB_AUTH_ID" "ClouDNS authentication ID" ""
check_var "CLOUDNS_AUTH_PASSWORD" "ClouDNS password" ""

# Traefik dashboard auth
check_var "TRAEFIK_BASIC_AUTH_USER" "Dashboard username" '^[a-zA-Z0-9_-]+$'

if [ ! -z "$TRAEFIK_BASIC_AUTH_PASSWORD" ]; then
    if [[ "$TRAEFIK_BASIC_AUTH_PASSWORD" =~ ^\$apr1\$|\$2[aby]\$ ]]; then
        print_success "TRAEFIK_BASIC_AUTH_PASSWORD is properly hashed"
    else
        print_error "TRAEFIK_BASIC_AUTH_PASSWORD is not hashed!"
        echo "  Generate with: htpasswd -nb $TRAEFIK_BASIC_AUTH_USER your_password | sed -e s/\\$/\\$\\$/g"
    fi
else
    print_error "TRAEFIK_BASIC_AUTH_PASSWORD is not set"
fi

# ============================================
# Network Configuration
# ============================================
print_header "Network Configuration"

# Check network subnets format
for net_var in NETWORK_SUBNET_PUBLIC NETWORK_SUBNET_FRONTEND NETWORK_SUBNET_BACKEND NETWORK_SUBNET_MANAGEMENT; do
    if [ ! -z "${!net_var}" ]; then
        if [[ "${!net_var}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
            print_success "$net_var: ${!net_var}"
        else
            print_error "$net_var has invalid format: ${!net_var}"
            echo "  Expected format: 172.20.0.0/24"
        fi
    fi
done

# ============================================
# Template Files Validation
# ============================================
print_header "Configuration Templates"

# Check traefik.yml.template
if [ -f config/traefik.yml.template ]; then
    # Check for unsubstituted variables
    if grep -q '\${.*}' config/traefik.yml.template; then
        vars_found=$(grep -o '\${[^}]*}' config/traefik.yml.template | sort -u)
        echo "Variables found in template:"
        for var in $vars_found; do
            var_name=$(echo $var | sed 's/\${//;s/:.*//')
            if [ ! -z "${!var_name}" ]; then
                print_success "  $var_name is set"
            else
                # Check if it has a default value
                if [[ "$var" == *":-"* ]]; then
                    print_success "  $var has default value"
                else
                    print_warning "  $var_name might not be set"
                fi
            fi
        done
    fi
else
    print_error "config/traefik.yml.template not found!"
fi

# Check middlewares.yml
if [ -f config/dynamic/middlewares.yml ]; then
    print_success "Middlewares configuration found"

    # Check for variable references
    if grep -q '\${.*}' config/dynamic/middlewares.yml; then
        print_warning "Middlewares config contains variables - ensure they're set"
    fi
else
    print_error "config/dynamic/middlewares.yml not found!"
fi

# ============================================
# Docker Compose Validation
# ============================================
print_header "Docker Compose Configuration"

if [ -f docker-compose.yml ]; then
    # Check if docker-compose can parse it
    if docker-compose config >/dev/null 2>&1 || docker compose config >/dev/null 2>&1; then
        print_success "Docker Compose configuration is valid"
    else
        print_error "Docker Compose configuration has errors!"
        echo "  Run: docker-compose config"
    fi

    # Check for hardcoded IPs that might conflict
    if grep -q 'ipv4_address:' docker-compose.yml; then
        print_warning "Hardcoded IP addresses found in docker-compose.yml"
        grep 'ipv4_address:' docker-compose.yml | while read line; do
            echo "    $line"
        done
    fi
else
    print_error "docker-compose.yml not found!"
fi

# ============================================
# DNS Resolution Check
# ============================================
print_header "DNS Configuration"

if [ ! -z "$DOMAIN" ]; then
    # Check if domain points somewhere
    if host "$DOMAIN" &>/dev/null 2>&1 || nslookup "$DOMAIN" &>/dev/null 2>&1; then
        IP=$(host "$DOMAIN" 2>/dev/null | grep "has address" | head -1 | awk '{print $4}')
        print_success "Domain $DOMAIN resolves to: $IP"
    else
        print_warning "Domain $DOMAIN does not resolve yet"
        echo "  Make sure to configure DNS before running Traefik"
    fi

    # Check traefik subdomain
    TRAEFIK_SUB="${SUBDOMAIN_TRAEFIK:-traefik.$DOMAIN}"
    if host "$TRAEFIK_SUB" &>/dev/null 2>&1; then
        print_success "Traefik subdomain $TRAEFIK_SUB resolves"
    else
        print_warning "Traefik subdomain $TRAEFIK_SUB does not resolve yet"
    fi
fi

# ============================================
# Permissions Check
# ============================================
print_header "File Permissions"

# Check script permissions
for script in scripts/*.sh; do
    if [ -f "$script" ]; then
        if [ -x "$script" ]; then
            print_success "$(basename $script) is executable"
        else
            print_warning "$(basename $script) is not executable"
            echo "  Fix with: chmod +x $script"
        fi
    fi
done

# Check acme.json if exists
if [ -f data/acme.json ]; then
    PERMS=$(stat -c %a data/acme.json)
    if [ "$PERMS" = "600" ]; then
        print_success "acme.json has correct permissions (600)"
    else
        print_error "acme.json has wrong permissions: $PERMS"
        echo "  Fix with: chmod 600 data/acme.json"
    fi
fi

# ============================================
# Summary
# ============================================
print_header "Validation Summary"

echo -e "Errors: ${RED}${ERRORS}${NC}"
echo -e "Warnings: ${YELLOW}${WARNINGS}${NC}"
echo ""

if [ $ERRORS -eq 0 ]; then
    if [ $WARNINGS -eq 0 ]; then
        print_success "Configuration is valid and ready!"
    else
        print_success "Configuration is valid with $WARNINGS warnings"
    fi
    echo ""
    echo "Next steps:"
    echo "  1. Review any warnings above"
    echo "  2. Run: ./scripts/preflight-check.sh"
    echo "  3. Run: ./scripts/setup.sh"
    exit 0
else
    print_error "Configuration has $ERRORS errors that must be fixed!"
    echo ""
    echo "Fix the errors above before running setup"
    exit 1
fi