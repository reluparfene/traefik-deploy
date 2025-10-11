# Network Segmentation Documentation

## Overview
This document describes the network segmentation strategy for the Docker environment with Traefik as the reverse proxy.

## Network Architecture

### 1. **traefik-public** (10.240.0.0/24)
- **Purpose**: DMZ/Edge network - entry point for all external traffic
- **Type**: Bridge network with internet access
- **Internet Access**: Yes (required for external connections)
- **Services**:
  - `traefik-proxy` (10.240.0.2) - Reverse proxy with static IP
- **Security**: Only Traefik should be on this network

### 2. **traefik-frontend** (10.241.0.0/24)
- **Purpose**: Frontend application tier - services accessible via Traefik
- **Type**: Bridge network with internet access
- **Internet Access**: Yes (for pulling updates, external APIs)
- **Traefik Connection**: traefik-proxy (10.241.0.2) - static IP
- **Services** (examples):
  - Web applications (WordPress, Nextcloud)
  - API services
  - Frontend containers
- **Routing**: All services here must use `traefik.docker.network=traefik-frontend` label

### 3. **traefik-backend** (10.242.0.0/24)
- **Purpose**: Database tier - completely isolated from internet and Traefik
- **Type**: Internal bridge network (no internet access, no external routes)
- **Internet Access**: No (maximum security)
- **Traefik Connection**: None (Traefik is NOT on this network by design)
- **Services** (examples):
  - PostgreSQL databases
  - MySQL/MariaDB databases
  - Redis/MongoDB instances
- **Security Model**:
  - Applications on traefik-frontend connect to databases on traefik-backend
  - Databases are never directly exposed to Traefik or internet
  - Zero-trust architecture for data persistence layer

### 4. **traefik-management** (10.243.0.0/24)
- **Purpose**: Management, monitoring, and administrative tools
- **Type**: Internal bridge network (no internet access)
- **Internet Access**: No (internal monitoring only)
- **Traefik Connection**: traefik-proxy (10.243.0.2) - static IP for dashboard access
- **Services** (examples):
  - Portainer (if deployed)
  - Traefik Dashboard (via routing)
  - Prometheus (future)
  - Grafana (future)
  - Backup services
  - Log aggregation tools
- **Access**: Admin tools accessible via Traefik dashboard routing

## Traefik Network Configuration

Traefik is uniquely positioned in the architecture by connecting to **three networks** simultaneously:

### Connected Networks:
1. **traefik-public** (10.240.0.2) - Receives external traffic
2. **traefik-frontend** (10.241.0.2) - Routes to application services
3. **traefik-management** (10.243.0.2) - Serves admin dashboard

### Not Connected:
- **traefik-backend** - Traefik has NO access to database network by design

### Why This Architecture?

**Security Principle**: Separation of concerns
- Traefik routes HTTP/HTTPS traffic to applications
- Applications connect to databases (not Traefik)
- Databases remain completely isolated from the edge proxy
- Even if Traefik is compromised, databases remain protected

### Static IP Assignments:
```yaml
networks:
  traefik-public:
    ipv4_address: "10.240.0.2"
  traefik-frontend:
    ipv4_address: "10.241.0.2"
  traefik-management:
    ipv4_address: "10.243.0.2"
```

Static IPs ensure:
- Predictable routing for monitoring
- Consistent firewall rules
- Reliable health checks

## Network Flow

```
                        Internet
                           ↓
                 ┌─────────────────────┐
                 │  traefik-public     │ (10.240.0.0/24)
                 │  [External/DMZ]     │ Internet: YES
                 └─────────┬───────────┘
                           ↓
                    traefik-proxy (10.240.0.2)
                           │
         ┌─────────────────┼─────────────────┐
         ↓                 ↓                  ↓
    (10.241.0.2)      (10.243.0.2)           ✗ (not connected)
         │                 │
┌────────┴─────────┐  ┌───┴──────────┐  ┌──────────────────┐
│ traefik-frontend │  │ traefik-     │  │ traefik-backend  │
│ [Applications]   │  │ management   │  │ [Databases]      │
│ (10.241.0.0/24)  │  │(10.243.0.0/24)│  │ (10.242.0.0/24)  │
│ Internet: YES    │  │ Internet: NO │  │ Internet: NO     │
└────────┬─────────┘  └───┬──────────┘  └────────┬─────────┘
         │                 │                      ↑
         │                 │                      │
    Applications      Monitoring           (app connects here,
    (WordPress,        (Portainer,          NOT traefik)
     Nextcloud)         Grafana)                  │
         │                                        │
         └────────────────────────────────────────┘
              Applications connect to databases
                   (traefik-backend network)
```

**Key Points:**
- External traffic: Internet → traefik-public → Traefik → traefik-frontend → Apps
- Database access: Apps (on both frontend + backend) → Databases (backend only)
- Admin access: Users → Traefik → traefik-management → Admin tools
- Traefik NEVER directly connects to databases

## Security Benefits

1. **Layer Isolation**: Each tier is isolated in its own subnet with defined boundaries
2. **No Direct Internet Access**: Databases (`traefik-backend`) and management tools (`traefik-management`) have no internet routes
3. **Controlled Access Points**: All external traffic MUST pass through Traefik on traefik-public
4. **Reduced Attack Surface**:
   - Services only expose necessary network connections
   - Databases are never exposed to the edge proxy
   - Even compromised Traefik cannot directly access databases
5. **Zero-Trust Database Layer**: Applications explicitly connect to both networks to reach databases
6. **Static IP Monitoring**: Traefik's fixed IPs enable reliable network monitoring and firewall rules
7. **Network Segmentation Enforcement**: Docker enforces network boundaries at the kernel level

## Migration Guide

### For Existing Services

1. **Update docker-compose.yml** to use new networks:

```yaml
services:
  my-app:
    networks:
      - traefik-frontend  # For Traefik routing
      - traefik-backend   # For database access
```

2. **Update Traefik labels**:
```yaml
labels:
  - "traefik.docker.network=traefik-frontend"
```

3. **Connect databases** to backend network only:
```yaml
services:
  my-database:
    networks:
      - traefik-backend  # Only backend, isolated from internet and Traefik
```

### For Traefik

Traefik should be connected to three networks (public, frontend, management):

```yaml
services:
  traefik:
    networks:
      traefik-public:
        ipv4_address: "10.240.0.2"
      traefik-frontend:
        ipv4_address: "10.241.0.2"
      traefik-management:
        ipv4_address: "10.243.0.2"
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
docker network inspect traefik-frontend
docker network inspect traefik-backend
docker network inspect traefik-management
```

## Best Practices

1. **Never** connect databases directly to public networks
2. **Always** use specific IP assignments for critical services
3. **Document** all inter-network communication requirements
4. **Test** connectivity after each service migration
5. **Monitor** network traffic between segments

## Troubleshooting

### Service Cannot Connect to Database
- Ensure both services are on the `traefik-backend` network
- Check firewall rules within containers
- Verify service discovery using container names

### Traefik Cannot Reach Service
- Confirm service is on `traefik-frontend` network
- Check Traefik label: `traefik.docker.network=traefik-frontend`
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