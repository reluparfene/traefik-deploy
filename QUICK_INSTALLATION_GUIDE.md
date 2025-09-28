# ⚡ QUICK INSTALLATION GUIDE - Traefik Deploy

**⏱️ Timp estimat: 5-10 minute**

## ✅ PRE-REQUISITE

- [ ] Server Linux cu Docker instalat
- [ ] Domeniu înregistrat (exemplu: `domeniul-tau.ro`)
- [ ] Cont ClouDNS cu domeniul adăugat
- [ ] Porturi 80 și 443 libere

## 📝 PAȘI RAPIZI

### **1️⃣ CLONARE REPOSITORY**
```bash
cd /opt
git clone https://github.com/reluparfene/traefik-deploy.git traefik
cd traefik
```

### **2️⃣ CONFIGURARE ENVIRONMENT**

**Opțiunea A: Setup automat (recomandat)**
```bash
# setup.sh va căuta automat în /opt/traefik-configs/.env
# Dacă există, va crea symlink automat
# Doar rulează direct pasul 4 (setup.sh)
```

**Opțiunea B: Configurare manuală (doar dacă nu ai backup)**
```bash
cp .env.example .env
nano .env
```

**Pentru configurare manuală, modifică aceste linii:**
```env
# OBLIGATORIU - Înlocuiește cu valorile tale
DOMAIN=domeniul-tau.ro
ACME_EMAIL=email-ul-tau@gmail.com
CLOUDNS_SUB_AUTH_ID=12345                    # Din ClouDNS > API
CLOUDNS_AUTH_PASSWORD=parola-ta-api          # Din ClouDNS > API

# IMPORTANT - Folosește serverele NS specifice domeniului tău!
# Verifică în panoul ClouDNS care sunt serverele tale NS
DNS_RESOLVERS=server1.cloudns.net:53,server2.cloudns.net:53,server3.cloudns.net:53,server4.cloudns.net:53

# OPTIONAL - Modifică dacă vrei alt subdomain pentru dashboard
SUBDOMAIN_TRAEFIK=traefik.${DOMAIN}
```

### **3️⃣ GENERARE PAROLĂ DASHBOARD** (doar pentru configurare manuală)

```bash
# Generează parola (înlocuiește 'parola-ta' cu ce vrei tu)
htpasswd -nb admin parola-ta | sed 's/\$/DOLLAR/g'

# Exemplu rezultat:
# admin:DOLLARapr1DOLLARxxxDOLLARyyyyyy
```

**Copiază rezultatul și adaugă-l în `.env`:**
```env
TRAEFIK_BASIC_AUTH_PASSWORD=DOLLARapr1DOLLARxxxDOLLARyyyyyy
```

**Notă:** Dacă folosești config din `/opt/traefik-configs`, parola există deja.

### **4️⃣ RULARE SETUP AUTOMAT**

```bash
# Rulează setup-ul
./scripts/setup.sh

# Răspunde YES când te întreabă
```

**Ce face scriptul automat:**
- ✅ Caută configurație în `/opt/traefik-configs/.env`
- ✅ Creează symlink dacă găsește
- ✅ Verifică sistemul și porturile
- ✅ Creează rețelele Docker necesare
- ✅ Procesează toate configurațiile
- ✅ Pornește Traefik
- ✅ Generează certificat SSL automat

### **5️⃣ VERIFICARE FUNCȚIONARE**

```bash
# Verifică dacă Traefik rulează
docker ps | grep traefik

# Vezi logs (trebuie să NU vezi erori roșii)
docker logs -f traefik-proxy
```

**Așteptează 30-60 secunde pentru certificat, apoi accesează:**
- 🌐 Dashboard: `https://traefik.domeniul-tau.ro`
- 👤 User: `admin`
- 🔑 Parola: cea pe care ai setat-o

## 🚀 ADAUGĂ PRIMA APLICAȚIE

### **Exemplu: Portainer pentru management Docker**

```bash
# Mergi în folder exemple
cd /opt/traefik/examples/portainer

# Editează docker-compose.yml
nano docker-compose.yml

# Modifică DOAR linia cu Host:
# Din: Host(`portainer.${DOMAIN}`)
# În:  Host(`portainer.domeniul-tau.ro`)

# Pornește Portainer
docker-compose up -d

# Accesează după 1 minut:
# https://portainer.domeniul-tau.ro
```

## ⚠️ TROUBLESHOOTING RAPID

### **Problema 1: "could not find zone"**
```bash
# Verifică că DNS_RESOLVERS sunt corecte pentru domeniul tău
# Verifică în ClouDNS care sunt serverele NS
grep DNS_RESOLVERS .env
```

### **Problema 2: Certificate invalid**
```bash
# Verifică logs pentru erori
docker logs traefik-proxy | grep -i error

# Verifică că domeniul răspunde
nslookup domeniul-tau.ro
```

### **Problema 3: 404 Page Not Found**
```bash
# Verifică că aplicația e pe rețeaua corectă
docker network ls | grep traefik
docker inspect nume-container | grep Network
```

### **Problema 4: Connection refused**
```bash
# Verifică porturile
netstat -tulpn | grep -E "80|443"

# Restart Traefik
docker-compose restart traefik
```

## 📋 CHECKLIST FINAL

- [ ] Traefik pornit fără erori
- [ ] Dashboard accesibil pe HTTPS
- [ ] Certificat valid (lacăt verde în browser)
- [ ] Fără erori în logs
- [ ] Prima aplicație funcțională

## 🆘 COMENZI UTILE

```bash
# Status
docker-compose ps

# Logs
docker logs -f traefik-proxy

# Restart
docker-compose restart traefik

# Stop
docker-compose down

# Update
docker-compose pull
docker-compose up -d

# Vezi certificate
docker exec traefik-proxy cat /acme.json | jq '.Certificates[].domain'
```

## 💡 SFATURI IMPORTANTE

1. **ÎNTOTDEAUNA** verifică DNS_RESOLVERS să fie pentru domeniul tău
2. **NU FOLOSI** DNS publice (8.8.8.8) - nu vor funcționa cu ClouDNS
3. **SALVEAZĂ** parola de dashboard într-un loc sigur
4. **FAC BACKUP** la `data/acme.json` după ce se generează certificatul
5. **VERIFICĂ** logs după fiecare modificare

---

**🎉 FELICITĂRI!** Dacă vezi dashboard-ul pe HTTPS, Traefik funcționează perfect!

**Următorii pași:**
1. Adaugă aplicațiile tale folosind exemplele din `/opt/traefik/examples/`
2. Citește `README_functionare.md` pentru detalii complete
3. Configurează monitoring (opțional)

**Probleme?** Deschide un issue: https://github.com/reluparfene/traefik-deploy/issues