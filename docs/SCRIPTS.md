# 📚 Scripts Documentation

## Overview
This document provides comprehensive documentation for all scripts in the `/scripts/` directory.

## Script Hierarchy and Dependencies

```
setup.sh (Main Entry Point)
├── preflight-check.sh
├── validate-config.sh
├── check-networks.sh
└── (creates networks internally)

backup-cert.sh ←→ restore-cert.sh (Certificate Management)
update-from-template.sh (Standalone Template Updates)
setup-networks-safe.sh (Alternative Network Creation)
```

---

## 🚀 Core Scripts

### **setup.sh**
**Purpose**: Main automated setup script - single entry point for Traefik deployment

**Location**: `/scripts/setup.sh`

**Usage**:
```bash
./scripts/setup.sh                    # Standard setup
./scripts/setup.sh branch-name        # Setup with specific config branch
```

**Features**:
- Auto-detects configuration in `/opt/traefik-configs/.env`
- Creates symlink if existing config found
- Validates system requirements via `preflight-check.sh`
- Validates configuration via `validate-config.sh`
- Creates Docker networks automatically
- Processes templates with envsubst
- Sets proper permissions (acme.json = 600)
- Starts Traefik container

**Environment Variables Required**:
- `DOMAIN` - Main domain
- `ACME_EMAIL` - Let's Encrypt email
- `CLOUDNS_SUB_AUTH_ID` - ClouDNS auth ID
- `CLOUDNS_AUTH_PASSWORD` - ClouDNS password
- `DNS_RESOLVERS` - DNS servers for ACME
- `TRAEFIK_BASIC_AUTH_PASSWORD` - Dashboard password

**Exit Codes**:
- `0` - Success
- `1` - Configuration error or validation failure

---

### **preflight-check.sh**
**Purpose**: System requirements validation before deployment

**Location**: `/scripts/preflight-check.sh`

**Usage**:
```bash
./scripts/preflight-check.sh
```

**Checks**:
- Docker installation and daemon status
- Docker Compose availability
- Port 80 and 443 availability
- User permissions
- System resources

**Called By**: `setup.sh` (automatic)

**Exit Codes**:
- `0` - All checks passed
- `1` - System requirements not met

---

### **validate-config.sh**
**Purpose**: Configuration and template validation

**Location**: `/scripts/validate-config.sh`

**Usage**:
```bash
./scripts/validate-config.sh
```

**Validates**:
- `.env` file existence and syntax
- Required environment variables
- Template files existence
- Configuration consistency
- Password format (htpasswd with DOLLAR placeholder)

**Called By**: `setup.sh` (automatic)

**Exit Codes**:
- `0` - Configuration valid
- `1` - Configuration errors found

---

## 🔒 Certificate Management Scripts

### **backup-cert.sh**
**Purpose**: Automated backup of acme.json certificates with rotation

**Location**: `/scripts/backup-cert.sh`

**Usage**:
```bash
./scripts/backup-cert.sh
```

**Features**:
- Creates timestamped backups in `/cert_backup/`
- Maintains last 5 backups (configurable via `MAX_BACKUPS`)
- Verifies backup integrity with SHA256 checksum
- Sets secure permissions (600)
- Shows current backup status

**Output Example**:
```
🔒 Starting certificate backup...
✅ Certificate backed up successfully
  📁 Location: /opt/traefik/cert_backup/acme_20241228_143022.json
  📏 Size: 15K
✅ Permissions set to 600 (read/write owner only)
```

**Requirements**:
- `data/acme.json` must exist
- Write permission to `cert_backup/` directory

---

### **restore-cert.sh**
**Purpose**: Interactive certificate restoration from backups

**Location**: `/scripts/restore-cert.sh`

**Usage**:
```bash
./scripts/restore-cert.sh
```

**Features**:
- Interactive backup selection menu
- Shows backup date and size
- Creates safety backup before restoration
- Checksum verification
- Optional Traefik restart
- Shows restored domains (if jq available)

**Interactive Flow**:
1. Lists available backups with metadata
2. User selects backup by number
3. Confirms restoration action
4. Creates safety backup
5. Restores selected backup
6. Optionally restarts Traefik

**Safety Features**:
- Backup of current certificate before restore
- SHA256 checksum verification
- User confirmation required

---

## 🔧 Utility Scripts

### **update-from-template.sh**
**Purpose**: Update from upstream template repository

**Location**: `/scripts/update-from-template.sh`

**Usage**:
```bash
./scripts/update-from-template.sh
```

**Features**:
- Fetches latest template changes
- Preserves local configuration
- Handles merge conflicts
- Shows change summary

**Workflow**:
1. Adds template repository as remote
2. Fetches latest changes
3. Merges template updates
4. Preserves `.env` and local customizations

---

## 🌐 Network Management Scripts

### **check-networks.sh**
**Purpose**: Pre-check network availability and detect conflicts

**Location**: `/scripts/check-networks.sh`

**Usage**:
```bash
./scripts/check-networks.sh
```

**Checks**:
- Network name conflicts
- Subnet conflicts
- IP range availability
- Existing containers on networks

**Exit Codes**:
- `0` - Networks available
- `1` - Conflicts detected

---

### **setup-networks-safe.sh**
**Purpose**: Alternative network creation with extensive conflict handling

**Location**: `/scripts/setup-networks-safe.sh`

**Usage**:
```bash
./scripts/setup-networks-safe.sh
```

**Features**:
- Comprehensive conflict detection
- Automatic fallback to alternative subnets
- Container migration warnings
- Detailed error reporting

**Networks Created**:
- `traefik-public` (172.20.0.0/24 or fallback)
- `traefik-frontend` (172.21.0.0/24 or fallback)
- `traefik-backend` (172.22.0.0/24 or fallback, internal)
- `traefik-management` (172.23.0.0/24 or fallback, internal)

**Note**: Network creation is normally handled by `setup.sh`. This script provides an alternative for complex scenarios.

---

## 📋 Script Best Practices

### Running Scripts
1. Always run from the traefik root directory
2. Ensure proper permissions: `chmod +x scripts/*.sh`
3. Use `./scripts/script-name.sh` format

### Error Handling
- All scripts use `set -e` for fail-fast behavior
- Check exit codes when calling from other scripts
- Review colored output for success/warning/error messages

### Environment Variables
- Always source from `.env` file
- Use DOLLAR placeholder for passwords to avoid shell expansion
- Validate variables before use

---

## 🎯 Common Tasks

### Initial Setup
```bash
cp .env.example .env
nano .env  # Edit configuration
./scripts/setup.sh
```

### Backup Certificates
```bash
# Manual backup
./scripts/backup-cert.sh

# Cron job for daily backup
echo "0 2 * * * /opt/traefik/scripts/backup-cert.sh" | crontab -
```

### Restore Certificates
```bash
./scripts/restore-cert.sh
# Follow interactive prompts
```

### Update from Template
```bash
./scripts/update-from-template.sh
docker-compose down
docker-compose up -d
```

### Configuration Management
```bash
# Configuration is stored in separate traefik-configs repository
# Located at: /opt/traefik-configs/.env
# This keeps credentials separate from code
```

---

## ⚠️ Troubleshooting

### Script Won't Execute
```bash
chmod +x scripts/*.sh
```

### Networks Already Exist
```bash
docker network ls | grep traefik
docker network rm traefik-public traefik-frontend traefik-backend traefik-management
./scripts/setup.sh
```

### Certificate Backup Fails
```bash
# Check permissions
ls -la data/acme.json
chmod 600 data/acme.json

# Check directory
mkdir -p cert_backup
chmod 755 cert_backup
```

### Configuration Not Found
```bash
# Check symlink
ls -la .env

# Check actual file
ls -la /opt/traefik-configs/.env

# Recreate if needed
ln -sf /opt/traefik-configs/.env .env
```

---

## 📚 Related Documentation
- [README.md](../README.md) - Main project documentation
- [CLAUDE.md](../CLAUDE.md) - AI assistant instructions
- [NETWORK_SEGMENTATION.md](NETWORK_SEGMENTATION.md) - Network architecture
- [DEPLOYMENT.md](DEPLOYMENT.md) - Deployment guide