#!/bin/bash

# ============================================
# Safe Network Setup for Traefik
# Handles conflicts and validates everything
# ============================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================
# Utility Functions
# ============================================

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
    local cmd=$1
    local package=$2
    if ! command -v $cmd &> /dev/null; then
        print_error "$cmd is not installed!"
        if [ ! -z "$package" ]; then
            echo "  Install with: apt-get install $package"
        fi
        return 1
    fi
    return 0
}

# Check if subnet is already in use
check_subnet_conflict() {
    local subnet=$1
    local network_name=$2

    # Get all existing Docker network subnets
    local existing_subnets=$(docker network ls -q | xargs -r docker network inspect -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null | grep -v '^$' || true)

    if echo "$existing_subnets" | grep -q "^${subnet}$"; then
        # Find which network uses this subnet
        local conflicting_network=$(docker network ls -q | while read net; do
            if docker network inspect -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}' "$net" 2>/dev/null | grep -q "^${subnet}$"; then
                docker network inspect -f '{{.Name}}' "$net"
                break
            fi
        done)

        if [ "$conflicting_network" != "$network_name" ]; then
            print_warning "Subnet $subnet is already used by network: $conflicting_network"
            return 1
        fi
    fi
    return 0
}

# Find next available subnet in 172.x.0.0/24 range
find_available_subnet() {
    local base_subnet=$1  # e.g., "172.20"
    local third_octet=${base_subnet##*.}
    local base_prefix=${base_subnet%.*}

    # Try up to 10 increments
    for i in {0..10}; do
        local new_third=$((third_octet + i))
        local test_subnet="${base_prefix}.${new_third}.0/24"

        if ! check_subnet_conflict "$test_subnet" "test" >/dev/null 2>&1; then
            continue
        fi

        echo "$test_subnet"
        return 0
    done

    return 1
}

# Create or validate network
create_or_validate_network() {
    local name=$1
    local desired_subnet=$2
    local gateway=$3
    local internal=$4
    local description=$5

    # Check if network already exists
    if docker network inspect "$name" >/dev/null 2>&1; then
        local existing_subnet=$(docker network inspect -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}' "$name")

        if [ "$existing_subnet" == "$desired_subnet" ]; then
            print_success "Network '$name' exists with correct subnet ($existing_subnet)"
        else
            print_warning "Network '$name' exists with different subnet ($existing_subnet)"
            print_warning "Expected: $desired_subnet"
            echo "  To fix: docker network rm $name (only if no containers attached)"
        fi
        return 0
    fi

    # Check for subnet conflict
    if ! check_subnet_conflict "$desired_subnet" "$name"; then
        # Try to find alternative
        local base_prefix="${desired_subnet%.*.*}"
        local third_octet="${desired_subnet#*.*.}"
        third_octet="${third_octet%%.*}"

        local alternative=$(find_available_subnet "${base_prefix}.${third_octet}")
        if [ ! -z "$alternative" ]; then
            print_warning "Using alternative subnet: $alternative"
            desired_subnet="$alternative"
            gateway="${alternative%.*}.1"
        else
            print_error "Cannot find available subnet for $name"
            return 1
        fi
    fi

    # Create the network
    local cmd="docker network create --driver=bridge --subnet=$desired_subnet --gateway=$gateway"

    if [ "$internal" == "true" ]; then
        cmd="$cmd --internal"
    fi

    cmd="$cmd --label purpose=\"$description\" $name"

    if eval $cmd; then
        if [ "$internal" == "true" ]; then
            print_success "Created INTERNAL network: $name ($desired_subnet)"
        else
            print_success "Created network: $name ($desired_subnet)"
        fi
    else
        print_error "Failed to create network: $name"
        return 1
    fi
}

# ============================================
# Main Execution
# ============================================

print_header "Docker Network Setup for Traefik"

# Step 1: Check prerequisites
echo "Checking prerequisites..."

if ! check_command docker "docker.io"; then
    exit 1
fi

if ! check_command docker-compose "docker-compose" && ! docker compose version >/dev/null 2>&1; then
    print_error "Neither docker-compose nor 'docker compose' is available!"
    echo "  Install with: apt-get install docker-compose"
    exit 1
fi

print_success "Prerequisites verified"

# Step 2: Check existing networks
print_header "Existing Docker Networks"

echo "Current Docker networks:"
docker network ls --format "table {{.Name}}\t{{.Driver}}\t{{.Scope}}" | head -10

echo ""
echo "Networks using 172.x.x.x subnets:"
docker network ls -q | while read net; do
    subnet=$(docker network inspect -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}' "$net" 2>/dev/null | grep "^172\." || true)
    if [ ! -z "$subnet" ]; then
        name=$(docker network inspect -f '{{.Name}}' "$net")
        printf "  %-20s %s\n" "$name:" "$subnet"
    fi
done

# Step 3: Load configuration
print_header "Network Configuration"

# Load from .env if exists
if [ -f .env ]; then
    source .env
    print_success "Loaded configuration from .env"
fi

# Define networks with defaults
NETWORKS=(
    "traefik-public:${NETWORK_SUBNET_PUBLIC:-172.20.0.0/24}:false:DMZ/Edge network for Traefik"
    "app-frontend:${NETWORK_SUBNET_FRONTEND:-172.21.0.0/24}:false:Frontend applications"
    "db-backend:${NETWORK_SUBNET_BACKEND:-172.22.0.0/24}:true:Database backend (isolated)"
    "management:${NETWORK_SUBNET_MANAGEMENT:-172.23.0.0/24}:true:Management and monitoring"
)

echo "Planned networks:"
for network_config in "${NETWORKS[@]}"; do
    IFS=':' read -r name subnet internal description <<< "$network_config"
    echo "  - $name: $subnet $([ "$internal" == "true" ] && echo "[INTERNAL]")"
done

# Step 4: Create networks
print_header "Creating Networks"

FAILED=0
for network_config in "${NETWORKS[@]}"; do
    IFS=':' read -r name subnet internal description <<< "$network_config"
    gateway="${subnet%.*}.1"

    if ! create_or_validate_network "$name" "$subnet" "$gateway" "$internal" "$description"; then
        FAILED=$((FAILED + 1))
    fi
done

# Step 5: Summary
print_header "Setup Summary"

if [ $FAILED -eq 0 ]; then
    print_success "All networks ready!"
    echo ""
    echo "Active Traefik networks:"
    docker network ls | grep -E "NAME|traefik-public|app-frontend|db-backend|management" | column -t
else
    print_error "$FAILED network(s) failed to create"
    echo ""
    echo "Troubleshooting:"
    echo "1. Check for conflicting subnets: docker network ls"
    echo "2. Remove unused networks: docker network prune"
    echo "3. Check specific network: docker network inspect <name>"
    echo "4. Remove specific network: docker network rm <name>"
    exit 1
fi

echo ""
echo "Network architecture:"
echo "  🌐 traefik-public  - External traffic entry"
echo "  🔧 app-frontend    - Application services"
echo "  🗄️  db-backend     - Database tier [INTERNAL]"
echo "  🔐 management      - Monitoring tools [INTERNAL]"