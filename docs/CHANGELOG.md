# Changelog

## [1.1.0] - 2026-09-20 - IP allocation rule + ip-range safety net

### Added
- **Rule**: every container on a `traefik-*` network declares `ipv4_address` from the
  static zone (`.3`–`.127`); `.2` is reserved for Traefik
- Networks are created with `--ip-range .128/25` (`NETWORK_IPRANGE_*` in `.env`,
  defaults in scripts): containers without a static IP land in the dynamic pool and can
  never take Traefik's address (safety net for the rule)
- `scripts/check-static-ips.sh` — read-only audit of live networks (exit 0/1/2)
- `docs/NETWORK_SEGMENTATION.md`: "IP allocation" section, migration procedure for
  existing networks, troubleshooting for `Address already in use`, incident 2026-09-19
- Static IPs in all `examples/` (WordPress `.10`/`.11`, Nextcloud `.20`–`.22`, Portainer `.30`/`.31`)

### Changed
- `setup.sh` / `setup-networks-safe.sh`: `docker network create` now passes
  `--gateway` and `--ip-range`; an existing network without ip-range aborts setup
  with the migration steps (it cannot be changed in place)
- `check-networks.sh` / `preflight-check.sh`: report the dynamic pool, warn when missing
- `validate-config.sh`: `NETWORK_IPRANGE_*` validated (format, inside subnet, leaves a
  static zone, excludes `.2`); `ipv4_address` in `docker-compose.yml` is now
  **required** for Traefik on public/frontend/management and must sit in the static
  zone (was: a warning about "hardcoded IPs")
- Examples: obsolete `version: '3.8'` removed
- Docs: Traefik version references aligned to v3.7.5 (compose was already there)

### Why
On 2026-09-19 a host reboot restored containers in arbitrary order; a container without
a static IP took `10.241.0.2` from the pool, Traefik failed with
`failed to set up container networking: Address already in use` and stayed down 36 h
(`unless-stopped` does not retry a failed restore).

## [1.0.0] - Template Release

### Added
- Complete Traefik v3.5 template with automated setup
- Network segmentation with 4-tier architecture
- Automated setup script (`scripts/setup.sh`)
- Environment-based configuration (`.env.example`)
- Reusable middleware configurations
- Example configurations for WordPress, Nextcloud, and Portainer
- Comprehensive documentation (README, CLAUDE.md, NETWORK_SEGMENTATION.md)

### Security Features
- Rate limiting middleware (configurable)
- Security headers (HSTS, CSP, X-Frame-Options)
- Network isolation between tiers
- Forced HTTPS redirect
- Dashboard protection with basic authentication
- Credentials stored in `.env` file (not in docker-compose)

### Certificate Management
- Simplified to single Let's Encrypt DNS resolver
- Configurable DNS servers with ClouDNS default
- Quad9 fallback DNS servers for reliability
- Configurable DNS propagation delay

### Network Architecture
- `traefik-public` (10.240.0.0/24) - DMZ for external traffic
- `app-frontend` (10.241.0.0/24) - Application services
- `db-backend` (10.242.0.0/24) - Isolated database tier
- `management` (10.243.0.0/24) - Monitoring and admin tools

### Configuration
- Template-based configuration system
- Environment variable substitution
- Dynamic configuration loading
- Hot-reload support

### Scripts
- `setup.sh` - Main automated setup
- Network creation integrated in `setup.sh`
- `create-networks.sh` - Legacy network setup

### Documentation
- Comprehensive README with quick start guide
- CLAUDE.md for AI assistant guidance
- Network segmentation documentation
- Example service configurations

## Notes
- This is a template repository, not a working deployment
- Configuration is required before first use
- All example values must be replaced with actual values