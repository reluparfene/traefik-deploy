# 📁 .env Files Management Workflow

## Option 1: Private Git Repository (RECOMMENDED)

### Setup
```bash
# Create a PRIVATE repository: traefik-configs
# Structure:
traefik-configs/               # PRIVATE REPO
├── README.md
├── echo-misavan/
│   └── .env
├── server2-prod/
│   └── .env
├── client-x/
│   └── .env
└── scripts/
    ├── deploy.sh
    └── backup-all.sh
```

### Workflow

#### Initial Setup on Each Server:
```bash
# 1. Clone both repos
cd /opt
git clone https://github.com/reluparfene/traefik-deploy.git traefik
git clone https://github.com/reluparfene/traefik-configs.git configs  # PRIVATE!

# 2. Link the correct .env
cd /opt/traefik
ln -sf /opt/configs/echo-misavan/.env .env

# 3. Deploy
./scripts/setup.sh
docker-compose up -d
```

#### Update Configuration:
```bash
# Edit locally
cd /opt/configs/echo-misavan
nano .env

# Commit and push
git add .env
git commit -m "Update echo-misavan config: changed domain"
git push

# Apply
cd /opt/traefik
docker-compose restart
```

#### Deploy to New Server:
```bash
#!/bin/bash
# deploy-server.sh
SERVER_NAME=$1

cd /opt
git clone https://github.com/reluparfene/traefik-deploy.git traefik
git clone https://github.com/reluparfene/traefik-configs.git configs

cd traefik
ln -sf /opt/configs/$SERVER_NAME/.env .env
./scripts/setup.sh
docker-compose up -d
```

---

## Option 2: Encrypted Files in Main Repo

### Setup with git-crypt
```bash
# Install git-crypt
apt-get install git-crypt

# In traefik-deploy repo
cd /opt/traefik
git-crypt init

# Create .gitattributes
echo "envs/**/.env filter=git-crypt diff=git-crypt" > .gitattributes

# Structure:
traefik-deploy/
├── envs/                    # Encrypted in repo
│   ├── echo-misavan.env
│   ├── server2-prod.env
│   └── client-x.env
├── .gitattributes
└── [other files]

# Add GPG key
git-crypt add-gpg-user YOUR_GPG_KEY_ID
```

### Workflow:
```bash
# Deploy
cd /opt/traefik
git-crypt unlock  # Decrypt files
cp envs/echo-misavan.env .env
./scripts/setup.sh
```

---

## Option 3: Central Configuration Server

### Using Ansible Vault
```yaml
# inventory/host_vars/echo-misavan.yml (encrypted)
traefik_env:
  DOMAIN: echo.misavan.com
  ACME_EMAIL: admin@misavan.com
  CLOUDNS_SUB_AUTH_ID: xxx
  CLOUDNS_AUTH_PASSWORD: yyy
```

### Ansible Playbook:
```yaml
---
- name: Deploy Traefik
  hosts: all
  tasks:
    - name: Clone repository
      git:
        repo: https://github.com/reluparfene/traefik-deploy.git
        dest: /opt/traefik

    - name: Create .env file
      template:
        src: env.j2
        dest: /opt/traefik/.env
        mode: '0600'

    - name: Run setup
      shell: |
        cd /opt/traefik
        ./scripts/setup.sh

    - name: Start services
      docker_compose:
        project_src: /opt/traefik
        state: present
```

### Deploy Command:
```bash
ansible-playbook -i inventory/hosts deploy-traefik.yml --limit echo-misavan
```

---

## Option 4: Simple Secure Backup

### Local Encrypted Backup Script
```bash
#!/bin/bash
# /usr/local/bin/backup-traefik-configs.sh

BACKUP_DIR="/secure/backups/traefik"
DATE=$(date +%Y%m%d)
SERVERS=("echo-misavan" "server2" "client-x")

for server in "${SERVERS[@]}"; do
    ssh root@$server "cat /opt/traefik/.env" > $BACKUP_DIR/$server-$DATE.env
    # Encrypt with GPG
    gpg --encrypt --recipient YOUR_KEY $BACKUP_DIR/$server-$DATE.env
    rm $BACKUP_DIR/$server-$DATE.env
done

# Push to private cloud
rclone copy $BACKUP_DIR backblaze:traefik-configs/
```

---

## Option 5: GitHub Secrets (CI/CD)

### Store in GitHub Secrets:
```
Repository Settings → Secrets → New repository secret
Name: ENV_ECHO_MISAVAN
Value: [paste entire .env content]
```

### GitHub Action Deploy:
```yaml
name: Deploy to Server
on:
  workflow_dispatch:
    inputs:
      server:
        description: 'Server to deploy to'
        required: true
        type: choice
        options:
        - echo-misavan
        - server2
        - client-x

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2

      - name: Deploy to server
        env:
          ENV_CONFIG: ${{ secrets[format('ENV_{0}', github.event.inputs.server)] }}
        run: |
          ssh root@${{ github.event.inputs.server }}.domain.com << 'EOF'
            cd /opt/traefik
            git pull
            echo "$ENV_CONFIG" > .env
            docker-compose up -d
          EOF
```

---

## Best Practices Summary

### For Small Teams (2-5 servers):
✅ **Option 1: Private Git Repo** - Simple, version controlled, easy access control

### For Medium Teams (5-20 servers):
✅ **Option 3: Ansible Vault** - Scalable, automated, encrypted

### For Large Teams (20+ servers):
✅ **HashiCorp Vault or AWS Secrets Manager** - Enterprise features, audit logs, rotation

### Security Checklist:
- [ ] Never commit plain .env to public repos
- [ ] Use different passwords per server
- [ ] Rotate credentials regularly
- [ ] Limit access to config repo/secrets
- [ ] Backup encrypted configs
- [ ] Use SSH keys not passwords
- [ ] Enable 2FA on GitHub

---

## Quick Implementation: Private Repo Method

```bash
# 1. Create private repo "traefik-configs" on GitHub

# 2. On your workstation
mkdir traefik-configs
cd traefik-configs

# 3. Create structure
mkdir -p echo-misavan server2 client-x

# 4. Copy configs from servers
scp root@echo.misavan.com:/opt/traefik/.env echo-misavan/.env
scp root@server2.com:/opt/traefik/.env server2/.env

# 5. Create deploy script
cat > scripts/deploy.sh << 'EOF'
#!/bin/bash
SERVER=${1:-echo-misavan}
ssh root@$SERVER.domain.com << ENDSSH
  cd /opt
  [ -d traefik ] || git clone https://github.com/reluparfene/traefik-deploy.git traefik
  [ -d configs ] || git clone https://github.com/reluparfene/traefik-configs.git configs
  cd traefik
  git pull
  ln -sf /opt/configs/$SERVER/.env .env
  ./scripts/setup.sh
  docker-compose up -d
ENDSSH
EOF

# 6. Push to GitHub
git init
git add .
git commit -m "Initial configs"
git remote add origin https://github.com/reluparfene/traefik-configs.git
git push -u origin main

# 7. Deploy to any server
./scripts/deploy.sh echo-misavan
./scripts/deploy.sh server2
```

This way you have:
- Public repo: `traefik-deploy` (all common files)
- Private repo: `traefik-configs` (only .env files)
- Simple deployment: `./deploy.sh server-name`
- Version control for both code and configs
- Easy rollback if needed