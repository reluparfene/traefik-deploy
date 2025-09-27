# 🚀 Traefik Template - Production-Ready Reverse Proxy

A comprehensive, security-focused Traefik v3.2 template with automated setup, network segmentation, and best practices built-in.

## ✨ Features

- **🔒 Security First**: Network segmentation, rate limiting, security headers
- **🌐 Auto SSL**: Let's Encrypt with DNS & HTTP challenges
- **🎯 Easy Setup**: Automated installation with one script
- **📦 Docker Native**: Optimized for Docker environments
- **🔄 Hot Reload**: Dynamic configuration updates
- **📊 Monitoring Ready**: Prometheus metrics support
- **🎨 Multiple Examples**: WordPress, Nextcloud, Portainer configs included

## 📋 Prerequisites

- Docker 20.10+
- Docker Compose 1.29+
- A domain with DNS management access
- Linux host (Ubuntu/Debian recommended)

## 📍 Installation Location

For production environments, we recommend installing Traefik in `/opt/traefik/`. See [Installation Location Guide](docs/INSTALLATION_LOCATION.md) for detailed recommendations.

## 🚀 Quick Start

```bash
# 1. Clone the template (to recommended location)
sudo mkdir -p /opt/traefik
cd /opt/traefik
sudo git clone https://github.com/yourusername/traefik-template.git .

# Or for development
git clone https://github.com/yourusername/traefik-template.git
cd traefik-template

# 2. Configure environment
cp .env.example .env
nano .env  # Edit with your values

# 3. Run automated setup
./scripts/setup.sh

# 4. Start Traefik
docker-compose up -d

# 5. Check status
docker-compose ps
docker-compose logs -f
```

## 📁 Project Structure

```
.
├── docker-compose.yml         # Main Traefik configuration
├── .env.example              # Environment variables template
├── config/                   # Configuration templates
│   ├── traefik.yml.template # Static configuration
│   └── dynamic/             # Dynamic configurations
├── data/                    # Runtime data (auto-created)
│   ├── traefik.yml         # Generated config
│   ├── acme.json          # SSL certificates
│   └── configurations/    # Dynamic configs
├── scripts/               # Automation scripts
│   ├── setup.sh          # Main setup script
│   └── backup.sh        # Backup script
├── examples/           # Service examples
│   ├── wordpress/     # WordPress setup
│   ├── nextcloud/    # Nextcloud setup
│   └── portainer/   # Portainer setup
└── docs/           # Documentation
    ├── NETWORK_SEGMENTATION.md
    └── SECURITY.md
```

## 🔧 Configuration

### Required Environment Variables

Edit `.env` file with your values:

```env
# Domain Configuration
DOMAIN=example.com
SUBDOMAIN_TRAEFIK=traefik.example.com
ACME_EMAIL=admin@example.com

# DNS Provider (for SSL)
CLOUDNS_SUB_AUTH_ID=your_id
CLOUDNS_AUTH_PASSWORD=your_password

# DNS Servers for certificate validation
DNS_RESOLVERS=your_provider_dns_servers
DNS_CHECK_DELAY=30

# Security
TRAEFIK_BASIC_AUTH_USER=admin
TRAEFIK_BASIC_AUTH_PASSWORD=your_encrypted_password
```

### Generate Basic Auth Password

```bash
# Using htpasswd
htpasswd -nb admin your_password

# Or using openssl
openssl passwd -apr1 your_password
```

## 🌐 Network Architecture

The template implements a secure 4-tier network architecture:

| Network | Subnet | Purpose |
|---------|--------|---------|
| traefik-public | 172.20.0.0/24 | External traffic entry |
| app-frontend | 172.21.0.0/24 | Application services |
| db-backend | 172.22.0.0/24 | Databases (isolated) |
| management | 172.23.0.0/24 | Monitoring tools |

## 🔒 Security Features

- **Network Segmentation**: Isolated network tiers
- **Rate Limiting**: DDoS protection
- **Security Headers**: HSTS, CSP, X-Frame-Options
- **Basic Auth**: Dashboard protection
- **Auto HTTPS**: Forced SSL redirect
- **Certificate Management**: Auto-renewal with Let's Encrypt

## 📦 Adding Services

### Example: Adding a WordPress Site

1. Create service docker-compose:

```yaml
# examples/wordpress/docker-compose.yml
services:
  wordpress:
    image: wordpress:latest
    networks:
      - app-frontend
      - db-backend
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=app-frontend"
      - "traefik.http.routers.wordpress.rule=Host(`blog.${DOMAIN}`)"
      - "traefik.http.routers.wordpress.entrypoints=websecure"
      - "traefik.http.routers.wordpress.tls.certresolver=le-dns"
```

2. Connect to networks and deploy:

```bash
docker-compose -f examples/wordpress/docker-compose.yml up -d
```

## 🛠️ Maintenance

### Backup Certificates

```bash
./scripts/backup.sh
```

### Update Traefik

```bash
docker-compose pull
docker-compose up -d
```

### View Logs

```bash
# All logs
docker-compose logs -f

# Only Traefik logs
docker-compose logs -f traefik

# Access logs
tail -f data/access.log
```

## 📊 Monitoring & Logging

### Logging Configuration

By default, logs go to stdout (viewable with `docker logs`). To customize:

#### Enable File Logging
Edit `config/traefik.yml.template` and uncomment:
```yaml
log:
  filePath: /traefik.log  # Saves logs to file
```

#### Enable Access Logs
Edit `config/traefik.yml.template` and uncomment:
```yaml
accessLog:
  format: json
  filePath: /access.log
```

⚠️ **Warning**: Access logs can grow quickly. Consider:
- Log rotation (`logrotate`)
- External log management (ELK, Loki)
- Filtering only errors (default: 400-599)

### Enable Prometheus Metrics

Set in `.env`:
```env
METRICS_ENABLED=true
METRICS_PORT=8080
```

Access metrics at: `http://localhost:8080/metrics`

## 🚨 Troubleshooting

### Certificate Issues

```bash
# Check certificate status
docker exec traefik-proxy cat /acme.json | jq

# Force renewal
docker-compose down
rm data/acme.json
touch data/acme.json
chmod 600 data/acme.json
docker-compose up -d
```

### Network Connectivity

```bash
# Check networks
docker network ls

# Inspect network
docker network inspect app-frontend

# Test connectivity
docker exec traefik-proxy ping service_name
```

### Dashboard Access

Default URL: `https://traefik.yourdomain.com`

If not accessible:
1. Check DNS resolution
2. Verify port 443 is open
3. Check credentials in `.env`
4. Review logs: `docker-compose logs traefik`

## 📚 Advanced Configuration

### Custom Middleware

Add to `data/configurations/custom-middleware.yml`:

```yaml
http:
  middlewares:
    my-middleware:
      headers:
        customRequestHeaders:
          X-Custom-Header: "value"
```

### Multiple Domains

```yaml
- "traefik.http.routers.app.rule=Host(`app.domain1.com`) || Host(`app.domain2.com`)"
```

## 🤝 Contributing

1. Fork the repository
2. Create feature branch
3. Commit changes
4. Push to branch
5. Open Pull Request

## 📄 License

MIT License - See LICENSE file

## 🆘 Support

- Issues: [GitHub Issues](https://github.com/yourusername/traefik-template/issues)
- Docs: [Traefik Documentation](https://doc.traefik.io/)
- Community: [Traefik Community Forum](https://community.traefik.io/)

## 🏆 Credits

Built with ❤️ using Traefik v3.2

---

**⭐ Star this repo if it helped you!**