# 🚀 Traefik Template - Deployment Guide

## Prezentare Generală
Acest repository este un **template reutilizabil** pentru instalarea Traefik v3.7 pe servere multiple. Include scripturi de automatizare care validează și pregătesc mediul înainte de deployment.

## ⚡ Quick Start

### Workflow Standard (Recomandat)
```bash
# 1. Clonează repo-urile în locațiile standard
git clone https://github.com/your-org/traefik-deploy.git /opt/traefik
git clone https://github.com/your-org/traefik-configs.git /opt/traefik-configs

# 2. Editează configurația
nano /opt/traefik-configs/.env

# 3. Rulează setup - va detecta automat configurația
cd /opt/traefik
./scripts/setup.sh
# Va afișa domeniul găsit și va cere confirmare
```

### Workflow Alternativ
```bash
# 1. Clonează template-ul oriunde
git clone https://github.com/your-org/traefik-deploy.git ~/traefik
cd ~/traefik

# 2. Rulează setup - va întreba pentru calea către .env
./scripts/setup.sh
# Alege opțiunea 1 și introdu calea către .env existent
```

## 📋 Ghid Detaliat de Deployment

### Pasul 1: Pregătirea Sistemului

#### Cerințe minime:
- Ubuntu 20.04+ / Debian 11+ / RHEL 8+
- Docker 20.10+
- Docker Compose 1.29+ sau Docker Compose Plugin v2+
- 1GB RAM minim, 2GB+ recomandat
- 5GB spațiu liber pe disk
- Porturi 80 și 443 libere

#### Instalare Docker (dacă nu există):
```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
# Re-login pentru a aplica modificările
```

### Pasul 2: Configurarea Template-ului

#### 2.1 Clonare repository:
```bash
git clone https://github.com/your-org/traefik-template.git /opt/traefik
cd /opt/traefik
```

#### 2.2 Creare fișier de configurare:
```bash
cp .env.example .env
```

#### 2.3 Editare configurație:
```bash
nano .env
```

**Variabile OBLIGATORII de modificat:**

| Variabilă | Descriere | Exemplu |
|-----------|-----------|---------|
| `DOMAIN` | Domeniul principal | `example.com` |
| `ACME_EMAIL` | Email pentru certificatele SSL | `admin@example.com` |
| `CLOUDNS_SUB_AUTH_ID` | ID autentificare ClouDNS | `12345` |
| `CLOUDNS_AUTH_PASSWORD` | Parolă ClouDNS | `your-password` |
| `TRAEFIK_BASIC_AUTH_USER` | Username pentru dashboard | `admin` |
| `TRAEFIK_BASIC_AUTH_PASSWORD` | Parolă hashată pentru dashboard | Vezi mai jos |

#### 2.4 Generare parolă pentru dashboard:
```bash
# Generează parola hashată
htpasswd -nb admin your_secure_password

# Copiază output-ul și adaugă-l în .env
# ATENȚIE: Dublează simbolurile $ ($ devine $$)
# Exemplu: $apr1$xxx -> $$apr1$$xxx
```

### Pasul 3: Deployment

#### Rulare setup automatizat:
```bash
./scripts/setup.sh
```

**Ce face scriptul automat:**
1. **Detectare configurație**:
   - Caută automat în `/opt/traefik-configs/.env`
   - Afișează domeniul găsit și cere confirmare
   - Permite introducerea unei căi alternative

2. **Pre-flight checks** - Verifică sistemul (Docker, porturi, resurse)
3. **Validare configurație** - Verifică .env și toate variabilele
4. **Creează rețele** - Dacă detectează conflicte, SE OPREȘTE cu instrucțiuni clare
5. **Procesează template-uri** - Înlocuiește variabilele din .env
6. **Pornește Traefik** - Docker Compose up

**Scenarii de configurare:**
- **Găsește în locația standard** → Afișează domeniul și cere confirmare
- **Nu găsește** → Oferă opțiuni: cale custom, creare din template, sau exit
- **Confirmare negativă** → Permite introducerea altei căi

**IMPORTANT**: Scriptul se oprește la prima eroare și oferă instrucțiuni clare pentru rezolvare.

### Pasul 4: Verificare Post-Deployment

```bash
# Verifică statusul
docker-compose ps

# Verifică log-urile
docker-compose logs -f traefik

# Verifică certificatele SSL
docker exec traefik-proxy cat /acme.json | jq .

# Accesează dashboard-ul
# https://traefik.your-domain.com
```

## 🔴 Troubleshooting

### Eroare: Network conflict

**Mesaj:**
```
❌ SUBNET CONFLICT: Cannot create network 'traefik-public'!
  Subnet 10.240.0.0/24 is already in use by network: other-network
```

**Soluție:**
```bash
# Opțiunea 1: Șterge rețeaua conflictuală (dacă nu e folosită)
docker network rm other-network

# Opțiunea 2: Verifică ce folosește rețeaua
docker network inspect other-network

# Opțiunea 3: Oprește containerele care o folosesc
docker stop $(docker network inspect other-network -f '{{range .Containers}}{{.Name}} {{end}}')
```

### Eroare: Port already in use

**Mesaj:**
```
❌ Port 80 is already in use by: nginx
```

**Soluție:**
```bash
# Oprește serviciul care folosește portul
sudo systemctl stop nginx
sudo systemctl disable nginx

# Sau schimbă porturile în docker-compose.yml
```

### Eroare: acme.json permissions

**Mesaj:**
```
❌ acme.json has wrong permissions: 644
```

**Soluție:**
```bash
chmod 600 data/acme.json
```

## 📁 Structura După Deployment

```
/opt/traefik/
├── .env                    # Configurația ta
├── data/
│   ├── traefik.yml        # Config procesat
│   ├── acme.json          # Certificatele SSL
│   └── configurations/    # Config dinamic
├── logs/
│   └── traefik.log        # Log-uri
└── docker-compose.yml     # Orchestrare
```

## 🔒 Securitate

### Rețele Izolate
Template-ul creează 4 rețele separate:
- `traefik-public` (10.240.0.0/24) - Pentru trafic extern
- `traefik-frontend` (10.241.0.0/24) - Pentru aplicații
- `traefik-backend` (10.242.0.0/24) - Pentru baze de date (INTERNAL)
- `traefik-management` (10.243.0.0/24) - Pentru monitoring (INTERNAL)

### Best Practices
1. **NICIODATĂ** nu expune Docker socket-ul public
2. **ÎNTOTDEAUNA** folosește parole hashate pentru dashboard
3. **VERIFICĂ** că rețelele backend sunt marcate ca `internal`
4. **ACTUALIZEAZĂ** regulat imaginea Traefik

## 🔄 Actualizare Traefik

```bash
# 1. Pull ultima imagine
docker-compose pull

# 2. Repornește cu noua imagine
docker-compose up -d

# 3. Verifică noua versiune
docker-compose exec traefik traefik version
```

## 🔍 Scripturi Auxiliare (Opționale)

Deși `setup.sh` rulează toate verificările automat, poți rula scripturile individual pentru debugging:

```bash
# Doar validare configurație
./scripts/validate-config.sh

# Doar verificare sistem
./scripts/preflight-check.sh

# Verificare rețele disponibile
./scripts/check-networks.sh
```

## 📝 Checklist Final

Înainte de a considera deployment-ul complet:

- [ ] Dashboard-ul Traefik este accesibil la https://traefik.your-domain.com
- [ ] Certificatul SSL este valid (verifică în browser)
- [ ] Log-urile nu conțin erori: `docker-compose logs traefik`
- [ ] Rețelele sunt create corect: `docker network ls`
- [ ] Backup-ul pentru `data/acme.json` este configurat

## 🆘 Suport

Pentru probleme:
1. Verifică log-urile: `docker-compose logs -f traefik`
2. Rulează validarea manuală: `./scripts/validate-config.sh`
3. Consultă [documentația oficială Traefik](https://doc.traefik.io/)

---

**Versiune Template:** 1.0.0
**Traefik Version:** v3.7.5
**Ultima Actualizare:** 2024