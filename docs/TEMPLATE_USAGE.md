# 🚀 Using This Template

## Quick Start

### 1️⃣ Create Your Repository

Click the green **"Use this template"** button above to create your own copy.

- **Repository name**: Use descriptive names like `server1-traefik`, `prod-traefik`, `client-name-traefik`
- **Visibility**: Choose **Private** for production servers (recommended)
- **Include all branches**: Not needed (uncheck)

### 2️⃣ Clone and Configure

```bash
# Clone YOUR new repository (not the template!)
git clone git@github.com:YOUR_USERNAME/YOUR-NEW-REPO.git
cd YOUR-NEW-REPO

# Create your configuration
cp .env.example .env
nano .env  # Add your actual values
```

### 3️⃣ Important: Save Your Configuration

For server repositories where you want configuration backup:

```bash
# Remove .env from gitignore to save your configuration
sed -i '/^\.env$/d' .gitignore

# Commit your configuration
git add .env .gitignore
git commit -m "Configure for production server: $(hostname)"
git push
```

### 4️⃣ Deploy

```bash
# Run automated setup
./scripts/setup.sh

# Start Traefik
docker-compose up -d

# Verify
docker-compose ps
docker-compose logs -f traefik
```

---

## 📁 Repository Types

### Option A: Template Usage (Recommended)
Each server gets its own repository with saved configuration:
- ✅ Full backup of each server
- ✅ Independent version control
- ✅ Server-specific customizations
- ✅ Disaster recovery ready

### Option B: Direct Clone (Simple)
Clone template directly without creating new repository:
- ✅ Simpler for single-use
- ❌ No configuration backup
- ❌ No version control
- ❌ Manual backup needed

---

## 🔄 Updating From Template

To pull improvements from the original template:

```bash
# Add template as remote (one time)
git remote add template https://github.com/ORIGINAL_OWNER/traefik-template.git

# Fetch and merge updates
git fetch template
git merge template/main --allow-unrelated-histories

# Handle conflicts (keep your .env and custom configs)
# Then commit
git commit -m "Merge updates from template"
git push
```

### Selective Updates

Update only specific files:

```bash
# Update only scripts and docker-compose
git fetch template
git checkout template/main -- scripts/
git checkout template/main -- docker-compose.yml
git commit -m "Update scripts from template"
```

---

## 🏗️ Typical Workflow

### First Time Setup
```
1. Use this template → Create "prod-traefik" (private)
2. Clone prod-traefik locally
3. Configure .env with real values
4. Remove .env from .gitignore
5. Commit everything (including .env)
6. Run ./scripts/setup.sh
7. Deploy with docker-compose up -d
```

### Disaster Recovery
```
1. Server crashed? New server ready
2. Clone your repository: git clone prod-traefik
3. Run ./scripts/setup.sh
4. Deploy: docker-compose up -d
5. Everything restored in < 5 minutes!
```

### Configuration Changes
```
1. Edit .env or docker-compose.yml
2. Commit changes: git commit -am "Update domain"
3. Push to GitHub: git push
4. Apply: docker-compose up -d
```

---

## 📝 Configuration Checklist

Before deploying, ensure you've configured in `.env`:

- [ ] `DOMAIN` - Your main domain
- [ ] `SUBDOMAIN_TRAEFIK` - Traefik dashboard subdomain
- [ ] `ACME_EMAIL` - Valid email for Let's Encrypt
- [ ] `CLOUDNS_SUB_AUTH_ID` - Your DNS provider credentials
- [ ] `CLOUDNS_AUTH_PASSWORD` - Your DNS provider password
- [ ] `DNS_RESOLVERS` - Your DNS provider's nameservers
- [ ] `TRAEFIK_BASIC_AUTH_USER` - Dashboard username
- [ ] `TRAEFIK_BASIC_AUTH_PASSWORD` - Generated with htpasswd

---

## 🔐 Security Best Practices

### For Your Server Repository:
1. **Always use PRIVATE repositories** for production servers
2. **Enable 2FA** on your GitHub account
3. **Use deploy keys** instead of personal access tokens
4. **Rotate credentials** periodically
5. **Audit access** to your private repositories

### Sensitive Data Options:
- **Option 1**: Commit .env to private repo (simple, good enough for most)
- **Option 2**: Use GitHub Secrets + CI/CD (more complex, higher security)
- **Option 3**: External secret management (Vault, AWS Secrets Manager)

---

## 🛠️ Customization Examples

### Add Custom Middleware
Create `data/configurations/custom.yml`:
```yaml
http:
  middlewares:
    my-auth:
      basicAuth:
        users:
          - "user:$2y$10$..."
```

### Add New Service
```bash
# Copy example as starting point
cp examples/wordpress/docker-compose.yml my-service.yml
# Edit for your service
nano my-service.yml
# Deploy alongside Traefik
docker-compose -f docker-compose.yml -f my-service.yml up -d
```

---

## 🚨 Troubleshooting

### Certificate Issues
```bash
# Check ACME logs
docker-compose logs traefik | grep acme
# Force renewal
rm data/acme.json
touch data/acme.json
chmod 600 data/acme.json
docker-compose restart traefik
```

### Can't Access Dashboard
1. Check DNS points to your server
2. Verify credentials in .env
3. Check firewall allows 443
4. Review logs: `docker-compose logs traefik`

### Network Issues
```bash
# Recreate networks
./scripts/setup-network-segmentation.sh
# Restart everything
docker-compose down
docker-compose up -d
```

---

## 📚 Further Reading

- [README.md](README.md) - Main documentation
- [docs/NETWORK_SEGMENTATION.md](docs/NETWORK_SEGMENTATION.md) - Network architecture
- [examples/](examples/) - Service configuration examples
- [CLAUDE.md](CLAUDE.md) - AI assistant documentation