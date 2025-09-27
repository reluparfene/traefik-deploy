# 📁 Traefik Installation Location Guide

## Recommended Directory Structures

### 🏆 Production Environment

#### Option 1: `/opt/traefik/` (RECOMMENDED)
```bash
/opt/traefik/
├── docker-compose.yml
├── .env
├── data/
│   ├── traefik.yml
│   ├── acme.json
│   └── configurations/
├── logs/
└── backups/
```

**Why `/opt/traefik/`?**
- ✅ Industry standard for third-party applications
- ✅ Requires sudo for modifications (better security)
- ✅ Separate from user home directories
- ✅ Easy to include in backup strategies
- ✅ Clear separation from system files

**Setup Commands:**
```bash
# Create directory structure
sudo mkdir -p /opt/traefik
cd /opt/traefik

# Clone template
sudo git clone https://github.com/YOUR_USERNAME/traefik-template.git .

# Set proper ownership
sudo chown -R root:docker /opt/traefik
sudo chmod 750 /opt/traefik

# Configure
sudo cp .env.example .env
sudo nano .env

# Run setup
sudo ./scripts/setup.sh

# Set acme.json permissions
sudo chmod 600 /opt/traefik/data/acme.json
```

#### Option 2: `/srv/traefik/` (Alternative)
```bash
/srv/traefik/
```
- ✅ FHS compliant for service data
- ✅ Dedicated for server data
- ✅ Isolated from system and users

### 🧪 Development/Testing Environment

#### Option 3: `/home/docker/traefik/`
```bash
/home/docker/traefik/
```
- ✅ Easy access without sudo
- ✅ Good for development
- ✅ Simple permissions management
- ⚠️ Not recommended for production

#### Option 4: `/docker/traefik/` (Docker-dedicated servers)
```bash
/docker/
├── traefik/
├── wordpress/
├── nextcloud/
└── portainer/
```
- ✅ Clear Docker service organization
- ✅ All containers in one place
- ✅ Good for Docker-only servers

## Directory Organization

### Recommended Full Structure
```bash
/opt/traefik/                      # Traefik reverse proxy
├── docker-compose.yml
├── .env
├── data/
│   ├── traefik.yml               # Generated from template
│   ├── acme.json                 # SSL certificates (chmod 600)
│   └── configurations/           # Dynamic configurations
├── logs/                         # Optional log files
│   ├── traefik.log
│   └── access.log
└── backups/                      # Backup directory
    └── acme-backup-2024.json

/opt/docker-services/              # Other services
├── wordpress/
│   ├── docker-compose.yml
│   └── .env
├── nextcloud/
│   ├── docker-compose.yml
│   └── .env
└── portainer/
    ├── docker-compose.yml
    └── .env
```

## Security Permissions

### Production Permissions Setup
```bash
# Set ownership
sudo chown -R root:docker /opt/traefik

# Directory permissions
sudo find /opt/traefik -type d -exec chmod 750 {} \;

# File permissions
sudo find /opt/traefik -type f -exec chmod 640 {} \;

# Special permissions
sudo chmod 600 /opt/traefik/data/acme.json
sudo chmod 750 /opt/traefik/scripts/*.sh

# Allow docker group to read necessary files
sudo chmod 640 /opt/traefik/.env
sudo chmod 640 /opt/traefik/docker-compose.yml
```

## Migration Guide

### Moving from Development to Production
```bash
# From /home/docker/traefik to /opt/traefik

# 1. Stop current instance
cd /home/docker/traefik
docker-compose down

# 2. Create production directory
sudo mkdir -p /opt/traefik

# 3. Copy files (excluding runtime data)
sudo cp -r docker-compose.yml .env config/ scripts/ examples/ docs/ /opt/traefik/

# 4. Set permissions
sudo chown -R root:docker /opt/traefik
sudo chmod 750 /opt/traefik
sudo chmod 600 /opt/traefik/data/acme.json

# 5. Update any absolute paths in .env if needed
sudo nano /opt/traefik/.env

# 6. Start from new location
cd /opt/traefik
sudo docker-compose up -d
```

## Backup Considerations

### Backup Strategy by Location

#### For `/opt/traefik/`:
```bash
# Backup script location
/opt/traefik/scripts/backup.sh

# Backup command
sudo tar -czf /backups/traefik-$(date +%Y%m%d).tar.gz \
  -C /opt/traefik \
  .env docker-compose.yml data/acme.json data/configurations/

# Automated backup via cron
0 3 * * * /opt/traefik/scripts/backup.sh
```

## Docker Volumes vs Bind Mounts

### Current Template (Bind Mounts)
```yaml
volumes:
  - ./data/traefik.yml:/traefik.yml:ro
  - ./data/acme.json:/acme.json
```

### Alternative with Named Volumes
```yaml
volumes:
  - traefik-config:/etc/traefik:ro
  - traefik-acme:/acme

volumes:
  traefik-config:
    driver: local
  traefik-acme:
    driver: local
```

## Platform-Specific Considerations

### Linux (Ubuntu/Debian)
- Use `/opt/traefik/` for production
- Ensure docker group exists
- Use systemd for auto-start

### CentOS/RHEL
- May need SELinux context:
```bash
sudo semanage fcontext -a -t container_file_t "/opt/traefik(/.*)?"
sudo restorecon -Rv /opt/traefik
```

### Docker Desktop (Development)
- Use home directory locations
- Simpler permission model
- Good for testing

## Decision Matrix

| Location | Production | Development | Security | Backup | Complexity |
|----------|------------|-------------|----------|--------|------------|
| `/opt/traefik/` | ⭐⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ |
| `/srv/traefik/` | ⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ |
| `/home/docker/` | ⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐ | ⭐ |
| `/docker/` | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐ |

## Final Recommendation

**For Production**: `/opt/traefik/`
- Industry standard
- Secure permissions
- Clear separation
- Easy backups
- Professional structure

**For Development**: `/home/USER/projects/traefik/`
- Easy access
- No sudo needed
- Quick iterations
- Simple testing