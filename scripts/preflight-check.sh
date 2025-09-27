#!/bin/bash

# ============================================
# Traefik Pre-flight Check Script
# Complete validation before deployment
# ============================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Counters
ERRORS=0
WARNINGS=0

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
    ((WARNINGS++))
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
    ((ERRORS++))
}

print_info() {
    echo -e "${MAGENTA}ℹ️  $1${NC}"
}

# ============================================
# System Requirements Check
# ============================================
print_header "System Requirements"

# Check OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    print_info "OS: $NAME $VERSION"
else
    print_warning "Cannot determine OS version"
fi

# Check Docker
if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker --version | cut -d' ' -f3 | cut -d',' -f1)
    print_success "Docker installed: $DOCKER_VERSION"

    # Check Docker daemon
    if docker info &>/dev/null; then
        print_success "Docker daemon is running"
    else
        print_error "Docker daemon is not running or not accessible"
        echo "  Try: sudo usermod -aG docker $USER"
    fi
else
    print_error "Docker is not installed"
    echo "  Install: curl -fsSL https://get.docker.com | sh"
fi

# Check Docker Compose
COMPOSE_FOUND=false
if command -v docker-compose &> /dev/null; then
    COMPOSE_VERSION=$(docker-compose --version | cut -d' ' -f3 | cut -d',' -f1)
    print_success "Docker Compose (standalone) installed: $COMPOSE_VERSION"
    COMPOSE_CMD="docker-compose"
    COMPOSE_FOUND=true
elif docker compose version &>/dev/null 2>&1; then
    COMPOSE_VERSION=$(docker compose version --short)
    print_success "Docker Compose (plugin) installed: $COMPOSE_VERSION"
    COMPOSE_CMD="docker compose"
    COMPOSE_FOUND=true
else
    print_error "Docker Compose is not installed"
    echo "  Install standalone: sudo curl -L https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose"
    echo "  Or plugin: sudo apt-get install docker-compose-plugin"
fi

# Check required commands
for cmd in git curl wget jq; do
    if command -v $cmd &> /dev/null; then
        print_success "$cmd is available"
    else
        print_warning "$cmd is not installed (optional but recommended)"
    fi
done

# ============================================
# Port Availability Check
# ============================================
print_header "Port Availability"

check_port() {
    local port=$1
    if netstat -tuln 2>/dev/null | grep -q ":$port "; then
        local process=$(sudo ss -lptn "sport = :$port" 2>/dev/null | grep -oP '(?<=").*?(?=")')
        print_error "Port $port is already in use by: ${process:-unknown}"
        return 1
    else
        print_success "Port $port is available"
        return 0
    fi
}

# Check if netstat/ss is available
if command -v netstat &> /dev/null || command -v ss &> /dev/null; then
    check_port 80
    check_port 443
else
    print_warning "Cannot check port availability (netstat/ss not found)"
fi

# ============================================
# Environment Configuration Check
# ============================================
print_header "Environment Configuration"

# Check .env file
if [ -f .env ]; then
    print_success ".env file exists"

    # Source and validate
    set -a
    source .env
    set +a

    # Required variables
    REQUIRED_VARS=(
        "DOMAIN"
        "ACME_EMAIL"
        "CLOUDNS_SUB_AUTH_ID"
        "CLOUDNS_AUTH_PASSWORD"
        "TRAEFIK_BASIC_AUTH_USER"
        "TRAEFIK_BASIC_AUTH_PASSWORD"
    )

    for var in "${REQUIRED_VARS[@]}"; do
        if [ -z "${!var}" ]; then
            print_error "$var is not set or empty"
        else
            # Hide sensitive values
            case $var in
                *PASSWORD*|*AUTH_ID*)
                    print_success "$var is set (hidden)"
                    ;;
                DOMAIN)
                    print_success "$var = ${!var}"
                    # Check domain format
                    if [[ ! "${!var}" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]]; then
                        print_warning "  Domain format might be invalid"
                    fi
                    ;;
                ACME_EMAIL)
                    print_success "$var = ${!var}"
                    # Check email format
                    if [[ ! "${!var}" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
                        print_warning "  Email format might be invalid"
                    fi
                    ;;
                *)
                    print_success "$var = ${!var}"
                    ;;
            esac
        fi
    done

    # Check htpasswd format
    if [ ! -z "$TRAEFIK_BASIC_AUTH_PASSWORD" ]; then
        if [[ "$TRAEFIK_BASIC_AUTH_PASSWORD" =~ ^\$apr1\$|\$2[aby]\$ ]]; then
            print_success "Password is properly hashed"
        else
            print_error "Password is not hashed with htpasswd"
            echo "  Generate with: htpasswd -nb $TRAEFIK_BASIC_AUTH_USER yourpassword"
        fi
    fi

else
    print_warning ".env file not found (will be configured during setup)"
    if [ -f .env.example ]; then
        print_info "Template found: .env.example"
    fi
fi

# ============================================
# Docker Networks Check
# ============================================
print_header "Docker Networks"

# Required networks
NETWORKS=(
    "traefik-public:${NETWORK_SUBNET_PUBLIC:-172.20.0.0/24}"
    "traefik-frontend:${NETWORK_SUBNET_FRONTEND:-172.21.0.0/24}"
    "traefik-backend:${NETWORK_SUBNET_BACKEND:-172.22.0.0/24}"
    "traefik-management:${NETWORK_SUBNET_MANAGEMENT:-172.23.0.0/24}"
)

for network_config in "${NETWORKS[@]}"; do
    IFS=':' read -r name subnet <<< "$network_config"

    if docker network inspect "$name" &>/dev/null 2>&1; then
        existing_subnet=$(docker network inspect -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}' "$name" 2>/dev/null)
        if [ "$existing_subnet" == "$subnet" ]; then
            print_success "Network '$name' exists with correct subnet"
        else
            print_warning "Network '$name' exists with different subnet: $existing_subnet"
        fi
    else
        print_info "Network '$name' will be created with subnet: $subnet"
    fi
done

# Check for conflicting networks
print_info "Checking for subnet conflicts..."
if docker network ls -q | xargs -r docker network inspect -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null | grep -q "^172\.1[6-9]\.\|^172\.2[0-9]\.\|^172\.3[0-1]\."; then
    print_warning "Found Docker networks in 172.16-31.x.x range that might conflict"
fi

# ============================================
# File Structure Check
# ============================================
print_header "File Structure"

# Required directories
DIRS=(
    "config"
    "config/dynamic"
    "scripts"
)

for dir in "${DIRS[@]}"; do
    if [ -d "$dir" ]; then
        print_success "Directory exists: $dir"
    else
        print_error "Directory missing: $dir"
    fi
done

# Required files
FILES=(
    "docker-compose.yml"
    "config/traefik.yml.template"
    "config/dynamic/middlewares.yml"
    "scripts/setup.sh"
)

for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
        print_success "File exists: $file"
    else
        print_error "File missing: $file"
    fi
done

# Check data directory
if [ -d "data" ]; then
    print_info "Data directory exists (will be preserved)"
    if [ -f "data/acme.json" ]; then
        PERMS=$(stat -c %a data/acme.json)
        if [ "$PERMS" = "600" ]; then
            print_success "acme.json has correct permissions (600)"
        else
            print_warning "acme.json has incorrect permissions: $PERMS (should be 600)"
        fi
    fi
else
    print_info "Data directory will be created during setup"
fi

# ============================================
# DNS Resolution Check
# ============================================
print_header "DNS Resolution"

if [ ! -z "$DOMAIN" ]; then
    # Check main domain
    if host "$DOMAIN" &>/dev/null || nslookup "$DOMAIN" &>/dev/null 2>&1; then
        print_success "Domain $DOMAIN resolves"
    else
        print_warning "Domain $DOMAIN does not resolve yet"
    fi

    # Check traefik subdomain
    TRAEFIK_DOMAIN="${SUBDOMAIN_TRAEFIK:-traefik.$DOMAIN}"
    if host "$TRAEFIK_DOMAIN" &>/dev/null || nslookup "$TRAEFIK_DOMAIN" &>/dev/null 2>&1; then
        print_success "Traefik domain $TRAEFIK_DOMAIN resolves"
    else
        print_warning "Traefik domain $TRAEFIK_DOMAIN does not resolve yet"
    fi
fi

# ============================================
# Memory and Disk Check
# ============================================
print_header "System Resources"

# Memory check
if [ -f /proc/meminfo ]; then
    TOTAL_MEM=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    TOTAL_MEM_GB=$((TOTAL_MEM / 1024 / 1024))
    if [ $TOTAL_MEM_GB -ge 1 ]; then
        print_success "Memory: ${TOTAL_MEM_GB}GB (sufficient)"
    else
        print_warning "Memory: ${TOTAL_MEM_GB}GB (minimum 1GB recommended)"
    fi
fi

# Disk space check
if command -v df &> /dev/null; then
    DISK_AVAIL=$(df -BG . | tail -1 | awk '{print $4}' | sed 's/G//')
    if [ $DISK_AVAIL -ge 5 ]; then
        print_success "Disk space: ${DISK_AVAIL}GB available (sufficient)"
    else
        print_warning "Disk space: ${DISK_AVAIL}GB available (minimum 5GB recommended)"
    fi
fi

# ============================================
# Summary
# ============================================
print_header "Pre-flight Check Summary"

echo -e "Errors: ${RED}${ERRORS}${NC}"
echo -e "Warnings: ${YELLOW}${WARNINGS}${NC}"
echo ""

if [ $ERRORS -eq 0 ]; then
    if [ $WARNINGS -eq 0 ]; then
        print_success "All checks passed! Ready for deployment."
    else
        print_success "Ready for deployment with $WARNINGS warnings."
        echo ""
        echo "Warnings are non-critical but should be reviewed."
    fi
    echo ""
    echo "Next steps:"
    echo "  1. Run: ./scripts/setup.sh"
    echo "  2. Check: docker-compose ps"
    echo "  3. Logs: docker-compose logs -f traefik"
    exit 0
else
    print_error "Found $ERRORS critical errors that must be fixed!"
    echo ""
    echo "Fix the errors above before running setup.sh"
    exit 1
fi