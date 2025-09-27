#!/bin/bash

# Script to create segregated Docker networks for improved security
# Run this before starting Traefik

echo "Creating segregated Docker networks..."

# Remove old network if exists (only if no containers are attached)
docker network inspect traefik-public >/dev/null 2>&1 && \
  echo "Network traefik-public already exists" || \
  docker network create --driver=bridge \
    --subnet=172.20.0.0/24 \
    --gateway=172.20.0.1 \
    --opt com.docker.network.bridge.name=br-traefik \
    traefik-public && \
  echo "✅ Created traefik-public network (172.20.0.0/24)"

# Create internal backend network
docker network inspect backend-net >/dev/null 2>&1 && \
  echo "Network backend-net already exists" || \
  docker network create --driver=bridge \
    --subnet=172.21.0.0/24 \
    --gateway=172.21.0.1 \
    --internal \
    --opt com.docker.network.bridge.name=br-backend \
    backend-net && \
  echo "✅ Created backend-net network (172.21.0.0/24) - internal only"

# Create isolated database network
docker network inspect database-net >/dev/null 2>&1 && \
  echo "Network database-net already exists" || \
  docker network create --driver=bridge \
    --subnet=172.22.0.0/24 \
    --gateway=172.22.0.1 \
    --internal \
    --opt com.docker.network.bridge.name=br-database \
    database-net && \
  echo "✅ Created database-net network (172.22.0.0/24) - internal only"

# Keep traefik-net for backward compatibility but recommend migration
echo ""
echo "⚠️  Note: The existing 'traefik-net' network should be migrated to the new structure"
echo "    - Use 'traefik-public' for services that need external access"
echo "    - Use 'backend-net' for internal application services"
echo "    - Use 'database-net' for database containers"

echo ""
echo "Network creation complete!"
docker network ls | grep -E "traefik|backend|database"