#!/bin/bash

# Simple network creation script - fallback for compatibility issues
# This creates the networks with minimal options

set -e

echo "Creating Docker networks (simplified mode)..."

# Create networks without custom bridge names (more compatible)
networks=(
    "traefik-public:172.20.0.0/24"
    "app-frontend:172.21.0.0/24"
    "db-backend:172.22.0.0/24"
    "management:172.23.0.0/24"
)

for network_config in "${networks[@]}"; do
    IFS=':' read -r name subnet <<< "$network_config"

    if docker network inspect "$name" >/dev/null 2>&1; then
        echo "Network '$name' already exists - skipping"
    else
        if [[ "$name" == "db-backend" ]] || [[ "$name" == "management" ]]; then
            # Create internal networks
            docker network create --subnet="$subnet" --internal "$name"
            echo "Created INTERNAL network: $name ($subnet)"
        else
            # Create external networks
            docker network create --subnet="$subnet" "$name"
            echo "Created network: $name ($subnet)"
        fi
    fi
done

echo ""
echo "✅ Networks created successfully!"
echo ""
echo "Current networks:"
docker network ls | grep -E "NAME|traefik-public|app-frontend|db-backend|management"