#!/bin/bash

# Network Segmentation Setup Script for Docker Environment
# This script creates a secure, segmented network architecture

set -e

echo "================================================"
echo "   Docker Network Segmentation Setup"
echo "================================================"
echo ""

# Function to create network if not exists
create_network() {
    local name=$1
    local subnet=$2
    local gateway=$3
    local internal=$4
    local description=$5

    if docker network inspect "$name" >/dev/null 2>&1; then
        echo "⚠️  Network '$name' already exists - skipping"
    else
        if [ "$internal" == "true" ]; then
            docker network create \
                --driver=bridge \
                --subnet="$subnet" \
                --gateway="$gateway" \
                --internal \
                --opt com.docker.network.bridge.name="br-$name" \
                --label "purpose=$description" \
                "$name"
            echo "✅ Created INTERNAL network: $name ($subnet)"
        else
            docker network create \
                --driver=bridge \
                --subnet="$subnet" \
                --gateway="$gateway" \
                --opt com.docker.network.bridge.name="br-$name" \
                --label "purpose=$description" \
                "$name"
            echo "✅ Created network: $name ($subnet)"
        fi
    fi
}

echo "🔄 Creating segmented networks..."
echo ""

# 1. Public/DMZ Network - Entry point for external traffic
create_network "traefik-public" "172.20.0.0/24" "172.20.0.1" "false" "DMZ/Edge network for Traefik"

# 2. Frontend Application Network - Web applications
create_network "app-frontend" "172.21.0.0/24" "172.21.0.1" "false" "Frontend applications"

# 3. Backend Database Network - Isolated database tier
create_network "db-backend" "172.22.0.0/24" "172.22.0.1" "true" "Database backend - no internet"

# 4. Management Network - Monitoring and admin tools
create_network "management" "172.23.0.0/24" "172.23.0.1" "true" "Management and monitoring"

echo ""
echo "================================================"
echo "   Network Creation Complete!"
echo "================================================"
echo ""
echo "📊 Current Docker Networks:"
docker network ls | grep -E "NAME|traefik-public|app-frontend|db-backend|management" | column -t

echo ""
echo "================================================"
echo "   Network Architecture:"
echo "================================================"
echo ""
echo "  🌐 traefik-public (172.20.0.0/24)"
echo "     └─ External traffic entry point"
echo ""
echo "  🔧 app-frontend (172.21.0.0/24)"
echo "     └─ Web applications layer"
echo ""
echo "  🗄️ db-backend (172.22.0.0/24) [INTERNAL]"
echo "     └─ Database tier (isolated)"
echo ""
echo "  🔐 management (172.23.0.0/24) [INTERNAL]"
echo "     └─ Monitoring & admin tools"
echo ""
echo "================================================"

# Cleanup old network if empty
echo ""
echo "🧹 Checking old traefik-net network..."
if docker network inspect traefik-net >/dev/null 2>&1; then
    CONTAINERS=$(docker network inspect traefik-net -f '{{len .Containers}}')
    if [ "$CONTAINERS" -eq "0" ]; then
        echo "   Removing empty traefik-net network..."
        docker network rm traefik-net
        echo "   ✅ Old network removed"
    else
        echo "   ⚠️  Network traefik-net still has $CONTAINERS containers attached"
        echo "   Migration required for attached containers"
    fi
fi

echo ""
echo "✅ Network segmentation setup complete!"
echo ""
echo "Next steps:"
echo "1. Update docker-compose files to use new networks"
echo "2. Restart services with: docker-compose down && docker-compose up -d"
echo "3. Verify connectivity between services"