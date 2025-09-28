#!/bin/bash

# ============================================
# Network Pre-Check and Configuration Script
# ============================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Get all used subnets
get_used_subnets() {
    docker network ls -q | xargs -r docker network inspect -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null | grep -v '^$' | sort -u
}

# Check if subnet is available
is_subnet_available() {
    local subnet=$1
    local used_subnets
    used_subnets=$(get_used_subnets)

    # Check exact match
    if echo "$used_subnets" | grep -q "^${subnet}$"; then
        return 1
    fi

    # Check for overlaps with /16 networks
    local base="${subnet%.*.*}"
    for used in $used_subnets; do
        if [[ "$used" == *"/16" ]]; then
            local used_base="${used%.*.*}"
            if [[ "$base" == "$used_base" ]]; then
                return 1
            fi
        fi
    done

    return 0
}

# Main check
print_header "Docker Network Configuration Check"

echo "Current Docker networks using 172.x.x.x space:"
echo ""

docker network ls -q | while read -r net_id; do
    name=$(docker network inspect -f '{{.Name}}' "$net_id" 2>/dev/null)
    subnet=$(docker network inspect -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}' "$net_id" 2>/dev/null)
    if [[ "$subnet" == 172.* ]]; then
        printf "  %-30s %s\n" "$name:" "$subnet"
    fi
done

echo ""
print_header "Checking Required Networks for Traefik"

# Load current config if exists
if [ -f .env ]; then
    source .env
fi

# Define required networks with defaults
NETWORKS=(
    "traefik-public:${NETWORK_SUBNET_PUBLIC:-172.20.0.0/24}"
    "traefik-frontend:${NETWORK_SUBNET_FRONTEND:-172.21.0.0/24}"
    "traefik-backend:${NETWORK_SUBNET_BACKEND:-172.22.0.0/24}"
    "traefik-management:${NETWORK_SUBNET_MANAGEMENT:-172.23.0.0/24}"
)

# Track suggestions
SUGGESTIONS=()
HAS_CONFLICTS=false

# Try alternative subnets - avoiding common conflicts
ALTERNATIVE_SUBNETS=(
    "172.25.0.0/24"
    "172.26.0.0/24"
    "172.27.0.0/24"
    "172.28.0.0/24"
    "172.29.0.0/24"
    "172.30.0.0/24"
    "172.31.0.0/24"
    "10.10.0.0/24"
    "10.10.1.0/24"
    "10.10.2.0/24"
    "10.10.3.0/24"
)

# Index for next available subnet
alt_index=0

for network_config in "${NETWORKS[@]}"; do
    IFS=':' read -r name subnet <<< "$network_config"

    # Check if network already exists
    if docker network inspect "$name" &>/dev/null; then
        existing_subnet=$(docker network inspect -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}' "$name")
        if [ "$existing_subnet" == "$subnet" ]; then
            print_success "$name exists with correct subnet: $subnet"
            SUGGESTIONS+=("${network_config}")
        else
            print_warning "$name exists with different subnet: $existing_subnet (expected: $subnet)"
            SUGGESTIONS+=("${name}:${existing_subnet}")
        fi
    elif is_subnet_available "$subnet"; then
        print_success "$name can use: $subnet ✓"
        SUGGESTIONS+=("${network_config}")
    else
        print_error "$name cannot use: $subnet (already in use)"
        HAS_CONFLICTS=true

        # Find alternative from our list
        found_alternative=false
        for ((i=$alt_index; i<${#ALTERNATIVE_SUBNETS[@]}; i++)); do
            alt_subnet="${ALTERNATIVE_SUBNETS[$i]}"
            if is_subnet_available "$alt_subnet"; then
                echo -e "  Alternative: ${GREEN}$alt_subnet${NC}"
                SUGGESTIONS+=("${name}:${alt_subnet}")
                alt_index=$((i + 1))  # Start next search from here
                found_alternative=true
                break
            fi
        done

        if [ "$found_alternative" = false ]; then
            print_error "  No alternative subnet found!"
            exit 1
        fi
    fi
done

# Generate config if needed
if [ "$HAS_CONFLICTS" = true ]; then
    print_header "Recommended Configuration"

    echo "Add these lines to your .env file:"
    echo ""
    echo -e "${YELLOW}# Network Configuration (updated $(date +%Y-%m-%d))${NC}"

    for suggestion in "${SUGGESTIONS[@]}"; do
        IFS=':' read -r name subnet <<< "$suggestion"
        case $name in
            "traefik-public")
                echo "NETWORK_SUBNET_PUBLIC=$subnet"
                ;;
            "traefik-frontend")
                echo "NETWORK_SUBNET_FRONTEND=$subnet"
                ;;
            "traefik-backend")
                echo "NETWORK_SUBNET_BACKEND=$subnet"
                ;;
            "traefik-management")
                echo "NETWORK_SUBNET_MANAGEMENT=$subnet"
                ;;
        esac
    done

    echo ""
    print_warning "Update your .env file with the configuration above, then run setup.sh"
else
    echo ""
    print_success "All networks are available! You can run setup.sh"
fi