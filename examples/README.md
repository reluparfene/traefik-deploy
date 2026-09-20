# 📦 Service Examples

This directory contains ready-to-use configurations for popular services.

## Available Examples

### 🌐 WordPress
A complete WordPress setup with MariaDB database.

```bash
cd wordpress
docker-compose up -d
```
Access at: `https://blog.yourdomain.com`

### ☁️ Nextcloud
Full Nextcloud installation with PostgreSQL and Redis.

```bash
cd nextcloud
docker-compose up -d
```
Access at: `https://cloud.yourdomain.com`

### 🎛️ Portainer
Docker management UI with agent support.

```bash
cd portainer
docker-compose up -d
```
Access at: `https://portainer.yourdomain.com`

## Usage Instructions

1. **Update .env** in the root directory with your domain
2. **Navigate** to the example directory
3. **Deploy** with `docker-compose up -d`
4. **Access** via the configured subdomain

## Network Configuration

All examples follow the network segmentation pattern:
- **traefik-frontend**: For web-facing services
- **traefik-backend**: For databases (isolated)
- **traefik-management**: For admin tools

**Every service has a static IP** (`ipv4_address`) from the static zone `.3`–`.127`
of its network — `.2` is Traefik's. The examples use `.10`/`.11` (WordPress),
`.20`–`.22` (Nextcloud) and `.30`/`.31` (Portainer); change them to free addresses on
your host and record them. Why this is mandatory: [docs/NETWORK_SEGMENTATION.md](../docs/NETWORK_SEGMENTATION.md#ip-allocation-static-zone-vs-dynamic-pool).

## Adding Custom Services

Use these examples as templates. Key requirements:

1. Add Traefik labels:
```yaml
labels:
  - "traefik.enable=true"
  - "traefik.docker.network=traefik-frontend"
  - "traefik.http.routers.[name].rule=Host(`subdomain.${DOMAIN}`)"
```

2. Connect to the appropriate networks **with a static IP on each**:
```yaml
networks:
  traefik-frontend:
    ipv4_address: "10.241.0.40"   # For web access - free address in .3-.127
  traefik-backend:
    ipv4_address: "10.242.0.40"   # For database access (if needed)
```

3. Use external networks:
```yaml
networks:
  traefik-frontend:
    external: true
  traefik-backend:
    external: true
```

4. Verify: `../../scripts/check-static-ips.sh` must exit 0.

## Security Notes

- All examples use HTTPS by default
- Databases are on isolated networks
- Passwords should be changed from defaults
- Consider adding rate limiting for public services