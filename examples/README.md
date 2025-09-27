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
- **app-frontend**: For web-facing services
- **db-backend**: For databases (isolated)
- **management**: For admin tools

## Adding Custom Services

Use these examples as templates. Key requirements:

1. Add Traefik labels:
```yaml
labels:
  - "traefik.enable=true"
  - "traefik.docker.network=app-frontend"
  - "traefik.http.routers.[name].rule=Host(`subdomain.${DOMAIN}`)"
```

2. Connect to appropriate networks:
```yaml
networks:
  - app-frontend  # For web access
  - db-backend    # For database access (if needed)
```

3. Use external networks:
```yaml
networks:
  app-frontend:
    external: true
  db-backend:
    external: true
```

## Security Notes

- All examples use HTTPS by default
- Databases are on isolated networks
- Passwords should be changed from defaults
- Consider adding rate limiting for public services