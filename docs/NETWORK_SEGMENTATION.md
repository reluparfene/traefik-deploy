# Network Segmentation Documentation

## Overview
This document describes the network segmentation strategy for the Docker environment with Traefik as the reverse proxy.

## Network Architecture

### 1. **traefik-public** (172.20.0.0/24)
- **Purpose**: DMZ/Edge network - entry point for external traffic
- **Type**: Bridge network with internet access
- **Services**:
  - `traefik-proxy` (172.20.0.2) - Reverse proxy

### 2. **app-frontend** (172.21.0.0/24)
- **Purpose**: Frontend application tier
- **Type**: Bridge network with internet access
- **Services** (examples):
  - Web applications
  - API services
  - Frontend containers

### 3. **db-backend** (172.22.0.0/24)
- **Purpose**: Database tier - isolated from internet
- **Type**: Internal bridge network (no internet access)
- **Services** (examples):
  - PostgreSQL databases
  - MySQL/MariaDB databases
  - Redis/MongoDB instances

### 4. **management** (172.23.0.0/24)
- **Purpose**: Management, monitoring, and administrative tools
- **Type**: Internal bridge network (no internet access)
- **Future Services**:
  - Prometheus
  - Grafana
  - Backup services
  - Log aggregation

## Network Flow

```
Internet
    ↓
[traefik-public]
    ↓
traefik-proxy ←→ [app-frontend]
                      ↓
                 Applications ←→ [db-backend]
                                      ↓
                                  Databases
    ↓
[management] → Monitoring all layers
```

## Security Benefits

1. **Layer Isolation**: Each tier is isolated in its own network
2. **No Direct Internet Access**: Databases and management tools are on internal networks
3. **Controlled Access Points**: All external traffic must pass through Traefik
4. **Reduced Attack Surface**: Services only expose necessary network connections

## Migration Guide

### For Existing Services

1. **Update docker-compose.yml** to use new networks:

```yaml
services:
  my-app:
    networks:
      - app-frontend  # Instead of traefik-net
      - db-backend    # For database access
```

2. **Update Traefik labels**:
```yaml
labels:
  - "traefik.docker.network=app-frontend"
```

3. **Connect databases** to backend network only:
```yaml
services:
  my-database:
    networks:
      - db-backend  # Only backend, no frontend access
```

### For Traefik

Traefik should be connected to both public and frontend networks:

```yaml
services:
  traefik:
    networks:
      traefik-public:
        ipv4_address: "172.20.0.2"
      app-frontend:
        ipv4_address: "172.21.0.2"
```

## Implementation Steps

1. **Networks are created automatically during setup**:
```bash
./scripts/setup.sh
```

2. **Update service configurations**:
- Modify docker-compose files
- Update network connections
- Adjust Traefik labels

3. **Migrate services** (one at a time):
```bash
docker-compose down
docker-compose up -d
```

4. **Verify connectivity**:
```bash
# Check network connections
docker network inspect traefik-public
docker network inspect app-frontend
docker network inspect db-backend
docker network inspect management
```

## Best Practices

1. **Never** connect databases directly to public networks
2. **Always** use specific IP assignments for critical services
3. **Document** all inter-network communication requirements
4. **Test** connectivity after each service migration
5. **Monitor** network traffic between segments

## Troubleshooting

### Service Cannot Connect to Database
- Ensure both services are on the `db-backend` network
- Check firewall rules within containers
- Verify service discovery using container names

### Traefik Cannot Reach Service
- Confirm service is on `app-frontend` network
- Check Traefik label: `traefik.docker.network=app-frontend`
- Verify service has `traefik.enable=true`

### DNS Resolution Issues
- Use container names for internal communication
- Ensure services are on the same network
- Check Docker's embedded DNS is working

## Network Monitoring

Monitor network traffic between segments:
```bash
# Show network statistics
docker network inspect traefik-public | jq '.[0].Containers'

# Check connectivity
docker exec <container> ping <target-container>

# View network interfaces
docker exec <container> ip addr show
```