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
- **Addressing**: every service declares `ipv4_address` in `10.241.0.3`–`.127` (see *IP allocation*)

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

**A static IP is only as reliable as the network around it.** Docker does not
reserve `.2` for Traefik: if another container on the same network starts first
*without* an `ipv4_address`, Docker's IPAM hands it the lowest free address —
which is `.2` — and Traefik then fails with
`failed to set up container networking: Address already in use`. This is exactly
what happened on 2026-09-19 (see [Incident](#incident-2026-09-19-traefik-down-36-h-after-a-host-reboot)).
The next section is the fix.

## IP allocation: static zone vs dynamic pool

Every `traefik-*` network (a `/24`) is split in two zones by Docker's `--ip-range`:

| Network | Subnet | Gateway | Traefik (reserved) | **Static zone** (explicit `ipv4_address`) | **Dynamic pool** (`--ip-range`) |
|---|---|---|---|---|---|
| traefik-public | 10.240.0.0/24 | .1 | 10.240.0.2 | 10.240.0.3 – .127 | 10.240.0.128/25 (.128 – .254) |
| traefik-frontend | 10.241.0.0/24 | .1 | 10.241.0.2 | 10.241.0.3 – .127 | 10.241.0.128/25 |
| traefik-backend | 10.242.0.0/24 | .1 | — (not attached) | 10.242.0.2 – .127 | 10.242.0.128/25 |
| traefik-management | 10.243.0.0/24 | .1 | 10.243.0.2 | 10.243.0.3 – .127 | 10.243.0.128/25 |

(`--ip-range` values come from `NETWORK_IPRANGE_*` in `.env`; `setup.sh` creates the
networks with them and refuses to continue if an existing network lacks one.)

### The rule

> **Every container attached to a `traefik-*` network declares `ipv4_address`
> from the static zone (`.3`–`.127`). `.2` is Traefik's. No exceptions — not for
> "temporary" or "test" containers either.**

```yaml
services:
  my-app:
    networks:
      traefik-frontend:
        ipv4_address: "10.241.0.10"   # static zone, unused, documented below
      traefik-backend:
        ipv4_address: "10.242.0.10"
```

Why a rule and not just the pool: fixed, documented addresses make firewall rules,
monitoring and debugging predictable, and two people adding services on the same
host cannot collide by accident if the allocation table is kept.

### The safety net

`--ip-range` is what makes the rule *enforced by Docker instead of by memory*:
a container that forgets `ipv4_address` gets an address from `.128`+ and can
**never** take Traefik's `.2` — regardless of start order after a reboot. It still
violates the rule, and `scripts/check-static-ips.sh` reports it:

```bash
./scripts/check-static-ips.sh     # exit 0 clean, 1 rule violations, 2 errors (network without ip-range, Traefik not on .2)
```

Run it after adding a service, after a reboot, or from cron.

### Allocation table (per host)

Keep the real table for each host in that host's operational documentation, e.g.:

| Network | IP | Container | Stack |
|---|---|---|---|
| traefik-frontend | 10.241.0.2 | traefik-proxy | /opt/traefik |
| traefik-frontend | 10.241.0.10 | autoconfig | /opt/autoconfig |

The examples in `examples/` use `.10`/`.11` (WordPress), `.20`–`.22` (Nextcloud),
`.30`/`.31` (Portainer) — change them to whatever is free on your host.

### Migrating existing networks

`--ip-range` cannot be changed on an existing network. Networks created before this
rule (no `IPRange` in `docker network inspect`) must be recreated. Every stack on
the network is down for the duration (~20 s if done in one go):

```bash
# 0. See what is attached and what will move
./scripts/check-static-ips.sh
docker network inspect traefik-frontend -f '{{range .Containers}}{{.Name}} {{.IPv4Address}}{{"\n"}}{{end}}'

# 1. Stop every stack attached to the networks (Traefik last is fine, order does not matter here)
docker compose -f /opt/autoconfig/docker-compose.yml down
cd /opt/traefik && docker compose down

# 2. Remove the networks (fails if something is still attached - good)
docker network rm traefik-public traefik-frontend traefik-backend traefik-management

# 3. Recreate them with --ip-range (reads NETWORK_* from .env, defaults otherwise).
#    setup-networks-safe.sh touches ONLY the networks; setup.sh would also regenerate
#    data/traefik.yml from the template and start Traefik - use it only on a fresh host.
./scripts/setup-networks-safe.sh

# 4. Start the stacks again
docker compose up -d
docker compose -f /opt/autoconfig/docker-compose.yml up -d

# 5. Verify
docker network inspect traefik-frontend -f '{{json .IPAM.Config}}'   # must show "IPRange"
./scripts/check-static-ips.sh                                        # must exit 0
curl -sI https://<your-domain>                                       # 200
```

Before step 1, give a static IP to every container that does not have one yet
(the audit in step 0 lists them) — otherwise they come back in the dynamic pool.

### Incident 2026-09-19: Traefik down 36 h after a host reboot

- The hypervisor powered the host off (`qemu-ga: guest-shutdown ... powerdown`); at
  boot, Docker restored containers in arbitrary order.
- `autoconfig` (no `ipv4_address` at the time) started first and received
  `10.241.0.2` from the pool — Traefik's address.
- Traefik failed: `failed to set up container networking: Address already in use`.
  `restart: unless-stopped` does **not** retry after a failed restore, so it stayed
  down until someone noticed. Nothing listened on 80/443; every site on the host was down.
- Immediate fix: `docker stop autoconfig && docker compose up -d traefik && docker start autoconfig`.
  A plain `docker restart autoconfig` does **not** help — IPAM hands it the same
  lowest free address again.
- Permanent fix: this page (static IP for every container + `--ip-range` on every network).

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

1. **Update docker-compose.yml** to use new networks, with a static IP on each:

```yaml
services:
  my-app:
    networks:
      traefik-frontend:                 # For Traefik routing
        ipv4_address: "10.241.0.10"     # static zone .3-.127, unused
      traefik-backend:                  # For database access
        ipv4_address: "10.242.0.10"
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
      traefik-backend:                  # Only backend, isolated from internet and Traefik
        ipv4_address: "10.242.0.11"
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

1. **Networks are created automatically during setup** (with `--ip-range`):
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

4. **Verify connectivity and IP allocation**:
```bash
# Check network connections
docker network inspect traefik-public
docker network inspect traefik-frontend
docker network inspect traefik-backend
docker network inspect traefik-management

# Every container on a static IP, every network with an ip-range
./scripts/check-static-ips.sh
```

## Best Practices

1. **Never** connect databases directly to public networks
2. **Always** declare `ipv4_address` from the static zone for **every** container on a
   `traefik-*` network — never rely on start order (see *IP allocation* above)
3. **Never** create a `traefik-*` network without `--ip-range` (use `setup.sh`)
4. **Keep** the per-host IP allocation table up to date
5. **Document** all inter-network communication requirements
6. **Test** connectivity after each service migration
7. **Monitor** network traffic between segments

## Troubleshooting

### Traefik fails to start: `Address already in use`
Full message: `failed to set up container networking: Address already in use`
(`docker inspect traefik-proxy -f '{{.State.Error}}'`). Another container holds one
of Traefik's `.2` addresses.
```bash
# who has it?
docker network inspect traefik-frontend -f '{{range .Containers}}{{.Name}} {{.IPv4Address}}{{"\n"}}{{end}}'
# free it and start Traefik first (restart alone does NOT work - IPAM gives the same IP again)
docker stop <intruder> && docker compose up -d traefik && docker start <intruder>
# then fix the cause: static IP for <intruder> + ip-range on the network
./scripts/check-static-ips.sh
```

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