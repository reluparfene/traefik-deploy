# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a production-ready Traefik v3.5 template repository with automated setup, network segmentation, and security best practices. It is designed exclusively as a reusable template for new Traefik installations, not as a working deployment.

## Key Architecture

### Core Components (Template Structure)
- **Traefik Container**: `traefik-proxy` - Main reverse proxy service (configured name)
- **Service Name**: `traefik` (for docker-compose commands)
- **Static Configuration Template**: `/config/traefik.yml.template` - base configuration with variables
- **Dynamic Configuration Templates**: `/config/dynamic/` - reusable middleware definitions
- **Runtime Configuration**: `/data/` directory (created during setup)
- **Environment Config**: `.env.example` - template for customization

### Network Segmentation (4-tier architecture)
- **traefik-public** (172.20.0.0/24) - DMZ/Edge network for external traffic
- **traefik-frontend** (172.21.0.0/24) - Application services layer
- **traefik-backend** (172.22.0.0/24) - Isolated database tier (internal only)
- **traefik-management** (172.23.0.0/24) - Monitoring and admin tools (internal only)

### Security Features
- Rate limiting middleware (100 req avg, 50 burst)
- Security headers (HSTS, CSP, X-Frame-Options)
- Network isolation between tiers
- Forced HTTPS redirect
- Dashboard protection with basic auth
- No direct database exposure

## Common Development Commands

### Initial Setup (required before first use)
```bash
# Option 1: Automatic setup with standard configuration
./scripts/setup.sh
# Will auto-detect config from /opt/traefik-configs/.env if available

# Option 2: Manual setup with custom configuration
cp .env.example .env
nano .env  # Edit with your actual values
./scripts/setup.sh

# Option 3: Setup with branch-specific configuration
./scripts/setup.sh branch-name
# Will clone config from github.com/reluparfene/traefik-configs.git
```

**Note**: This template will NOT work without configuration. All placeholder values must be replaced.

### Network Setup
```bash
# Networks are created automatically by setup.sh
./scripts/setup.sh

# Check network status
docker network ls | grep -E "traefik|frontend|backend|management"
```

### Service Management
```bash
# Deploy/restart Traefik
docker-compose up -d
docker-compose restart traefik

# Check status
docker-compose ps
docker logs -f traefik-proxy --tail 100

# Stop Traefik
docker-compose down
```

### Certificate Management
```bash
# Backup certificates (manual)
./scripts/backup-cert.sh

# Restore certificates (interactive)
./scripts/restore-cert.sh

# Check certificate status
docker exec traefik-proxy cat /acme.json | jq .

# Force certificate renewal
docker-compose down
rm data/acme.json
touch data/acme.json
chmod 600 data/acme.json
docker-compose up -d
```

## Project Structure

```
traefik/
├── .env                    # Environment variables (create from .env.example)
├── .env.example           # Template for environment variables
├── docker-compose.yml     # Main Traefik configuration
├── config/                # Configuration templates
│   ├── traefik.yml.template
│   └── dynamic/
│       └── middlewares.yml
├── data/                  # Runtime data
│   ├── traefik.yml       # Generated static config
│   ├── acme.json         # SSL certificates
│   └── configurations/   # Dynamic configs
├── scripts/              # Automation scripts
│   ├── setup.sh         # Main setup script (single entry point)
│   ├── preflight-check.sh # System requirements validation
│   ├── validate-config.sh # Configuration validation
│   ├── check-networks.sh # Pre-check network availability
│   ├── setup-networks-safe.sh # Safe network setup
│   ├── backup-cert.sh   # Certificate backup with rotation
│   ├── restore-cert.sh  # Interactive certificate restoration
├── cert_backup/         # Certificate backups directory
│   └── .gitkeep        # Keeps directory in git
├── examples/            # Service examples
│   ├── wordpress/
│   ├── nextcloud/
│   └── portainer/
└── docs/               # Documentation
    ├── NETWORK_SEGMENTATION.md
    ├── SCRIPTS.md       # Complete scripts documentation
    └── [other docs...]
```

## Adding New Services

### Using Docker Labels (Recommended)
```yaml
services:
  my-app:
    networks:
      - traefik-frontend
      - traefik-backend  # Only if database access needed
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=traefik-frontend"
      - "traefik.http.routers.my-app.rule=Host(`app.${DOMAIN}`)"
      - "traefik.http.routers.my-app.entrypoints=websecure"
      - "traefik.http.routers.my-app.tls.certresolver=le-dns"
      - "traefik.http.routers.my-app.middlewares=security-chain@file"
```

### Using Dynamic Configuration
Add to `/data/configurations/dynamic.yml`:
```yaml
http:
  routers:
    my-app:
      entrypoints: ["websecure"]
      rule: "Host(`app.domain.com`)"
      service: my-app-service
      tls:
        certresolver: le-dns
  services:
    my-app-service:
      loadBalancer:
        servers:
          - url: "http://172.21.0.50:8080"
```

## Environment Variables (.env)

Key variables to configure:
- `DOMAIN` - Your main domain
- `ACME_EMAIL` - Email for Let's Encrypt
- `CLOUDNS_SUB_AUTH_ID` - ClouDNS authentication
- `CLOUDNS_AUTH_PASSWORD` - ClouDNS password
- `DNS_RESOLVERS` - DNS servers for ACME challenge (ClouDNS servers format: "server1:53,server2:53")
- `DNS_CHECK_DELAY` - Delay before DNS check in seconds (default: 30)
- `TRAEFIK_BASIC_AUTH_USER` - Dashboard username
- `TRAEFIK_BASIC_AUTH_PASSWORD` - Dashboard password (htpasswd format with DOLLAR placeholder)

### Password Generation
```bash
# Generate password with DOLLAR placeholder to avoid shell expansion issues
htpasswd -nb admin your_password | sed 's/\$/DOLLAR/g'
# Example result: DOLLARapr1DOLLARxxxDOLLARyyyyyy
# The setup.sh script will convert DOLLAR back to $ during processing
```

## Security Considerations

- **Credentials**: Stored in `.env` file (not in docker-compose.yml)
- **acme.json**: Must have 600 permissions
- **Networks**: Databases should never be on public networks
- **Dashboard**: Protected with basic auth, accessible only via HTTPS
- **Middleware**: Security headers and rate limiting enabled by default

## Troubleshooting

### Service Not Accessible
1. Check if service is on `traefik-frontend` network
2. Verify label: `traefik.docker.network=traefik-frontend`
3. Ensure `traefik.enable=true` is set
4. Check DNS resolution for the domain
5. Review logs: `docker logs traefik-proxy`

### Certificate Issues
- Verify DNS provider credentials in `.env`
- Check DNS propagation for DNS challenge
- Ensure acme.json has correct permissions (600)
- Review Traefik logs for ACME errors

### Network Connectivity
```bash
# Test from Traefik to service
docker exec traefik-proxy ping <service-name>

# Check network membership
docker inspect <service-name> | grep NetworkMode

# List containers in network
docker network inspect traefik-frontend
```

## Template Usage

This repository is a template only - it requires configuration before use:

### For New Projects
1. Fork or clone this template repository
2. Copy `.env.example` to `.env`
3. Update `.env` with your specific values (domain, credentials, etc.)
4. Run `./scripts/setup.sh` for automated configuration
5. Customize configurations as needed
6. Deploy with `docker-compose up -d`

### Important Notes
- This is NOT a working deployment - configuration is required
- All example values (domains, credentials) must be replaced
- The `.env` file must be created from `.env.example`
- Networks must be created before first deployment
- See `examples/` directory for service integration patterns

## Version Information

- **Current Traefik Version**: v3.5
- **Minimum Docker Version**: 20.10.0
- **Docker Compose Version**: v2 recommended
- **Tested on**: Ubuntu 22.04, Debian 11/12

## Production Deployment Workflow

### For Production Servers
```bash
# 1. Pull latest changes
git pull

# 2. Stop services
docker-compose down

# 3. Update Docker images
docker-compose pull

# 4. Start services
docker-compose up -d

# 5. Verify deployment
docker logs -f traefik-proxy --tail 100
```

### Rollback Procedure
```bash
# If issues occur after update
git log --oneline -5  # Find previous commit
git checkout <commit-hash>
docker-compose down
docker-compose up -d
```

## Common Issues and Solutions

### DNS Resolution Issues
- **Problem**: "could not find zone for domain"
- **Solution**: Verify DNS_RESOLVERS match your ClouDNS nameservers
- **Check**: `nslookup -type=NS yourdomain.com`

### Certificate Generation Fails
- **Problem**: ACME challenge fails
- **Solution**:
  - Check ClouDNS API credentials
  - Ensure domain NS records point to ClouDNS
  - Increase DNS_CHECK_DELAY if needed

### Port Conflicts
- **Problem**: "bind: address already in use"
- **Solution**:
  ```bash
  # Find process using the port
  sudo netstat -tulpn | grep :80
  sudo netstat -tulpn | grep :443
  # Stop conflicting service or change Traefik ports
  ```

## Repository Maintenance

### Keeping Template Updated
```bash
# Add upstream remote (once)
git remote add upstream https://github.com/reluparfene/traefik-deploy.git

# Fetch and merge updates
git fetch upstream
git merge upstream/main --allow-unrelated-histories
```

### Configuration Backup Strategy
```bash
# Configuration is stored in separate traefik-configs repository
# Located at: /opt/traefik-configs/.env
# This keeps credentials separate from code

# Certificate backup
./scripts/backup-cert.sh
```

## Important Files to Never Commit

These files contain sensitive data and should NEVER be in version control:
- `.env` (except in private deployment repos)
- `data/acme.json` (certificates with private keys)
- `cert_backup/*.json` (certificate backups)
- Any file with passwords, tokens, or API keys

## Development vs Production

### Development Mode
- Can use self-signed certificates
- Debug logging enabled
- Dashboard accessible without auth (for testing)

### Production Mode (default)
- Let's Encrypt certificates via DNS challenge
- Error/warn logging only
- Dashboard requires authentication
- All security middlewares enabled

## Support and Resources

- **Documentation**: See `/docs/` directory
- **Examples**: Check `/examples/` for service configurations
- **Issues**: Report at github.com/reluparfene/traefik-deploy/issues
- **Traefik Docs**: https://doc.traefik.io/traefik/