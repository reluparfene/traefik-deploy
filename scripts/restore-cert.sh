#!/bin/bash

# ============================================
# Traefik Certificate Restore Script
# ============================================
# Restores acme.json from cert_backup folder
# Interactive selection of backup to restore

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
BACKUP_DIR="${BASE_DIR}/cert_backup"
ACME_FILE="${BASE_DIR}/data/acme.json"

# Functions
print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# ============================================
# Main restore process
# ============================================

echo "🔄 Traefik Certificate Restore Tool"
echo "===================================="
echo ""

# Check if backup directory exists
if [ ! -d "$BACKUP_DIR" ]; then
    print_error "Backup directory not found: $BACKUP_DIR"
    echo "  Run backup-cert.sh first to create backups."
    exit 1
fi

# Check for available backups
BACKUPS=($(ls -1t "${BACKUP_DIR}"/acme_*.json 2>/dev/null))

if [ ${#BACKUPS[@]} -eq 0 ]; then
    print_error "No backup files found in $BACKUP_DIR"
    exit 1
fi

# Display available backups
echo "📋 Available certificate backups:"
echo ""

for i in "${!BACKUPS[@]}"; do
    BACKUP="${BACKUPS[$i]}"
    FILENAME=$(basename "$BACKUP")
    SIZE=$(du -h "$BACKUP" | cut -f1)
    DATE=$(stat -c %y "$BACKUP" | cut -d' ' -f1,2 | cut -d'.' -f1)

    echo "  $((i+1)). $FILENAME"
    echo "      📅 Created: $DATE"
    echo "      📏 Size: $SIZE"
    echo ""
done

# Ask user to select
echo -n "Select backup to restore (1-${#BACKUPS[@]}) or 'q' to quit: "
read -r SELECTION

# Validate selection
if [[ "$SELECTION" == "q" ]] || [[ "$SELECTION" == "Q" ]]; then
    echo "Restore cancelled."
    exit 0
fi

if ! [[ "$SELECTION" =~ ^[0-9]+$ ]] || [ "$SELECTION" -lt 1 ] || [ "$SELECTION" -gt ${#BACKUPS[@]} ]; then
    print_error "Invalid selection: $SELECTION"
    exit 1
fi

# Get selected backup
SELECTED_BACKUP="${BACKUPS[$((SELECTION-1))]}"
SELECTED_NAME=$(basename "$SELECTED_BACKUP")

echo ""
print_info "Selected: $SELECTED_NAME"

# Create current backup before restore
if [ -f "$ACME_FILE" ]; then
    print_warning "Current acme.json exists. Creating safety backup..."
    SAFETY_BACKUP="${BACKUP_DIR}/acme_before_restore_$(date +%Y%m%d_%H%M%S).json"
    cp -p "$ACME_FILE" "$SAFETY_BACKUP"
    chmod 600 "$SAFETY_BACKUP"
    print_success "Safety backup created: $(basename "$SAFETY_BACKUP")"
fi

# Ask for confirmation
echo ""
print_warning "This will replace the current certificate file!"
echo -n "Are you sure you want to restore $SELECTED_NAME? (yes/NO): "
read -r CONFIRM

if [[ "$CONFIRM" != "yes" ]]; then
    echo "Restore cancelled."
    exit 0
fi

# ============================================
# Perform restoration
# ============================================

echo ""
echo "🔄 Starting restoration..."

# Ensure data directory exists
mkdir -p "$(dirname "$ACME_FILE")"

# Copy backup to acme.json
cp "$SELECTED_BACKUP" "$ACME_FILE"

# Set correct permissions
chmod 600 "$ACME_FILE"

# Verify restoration
if [ -f "$ACME_FILE" ]; then
    if [ "$(sha256sum "$SELECTED_BACKUP" | cut -d' ' -f1)" == "$(sha256sum "$ACME_FILE" | cut -d' ' -f1)" ]; then
        print_success "Certificate restored successfully!"

        # Get certificate info
        if command -v jq &> /dev/null; then
            echo ""
            echo "📜 Restored certificates for domains:"
            cat "$ACME_FILE" | jq -r '.le-dns.Certificates[].domain.main' 2>/dev/null | while read DOMAIN; do
                echo "  • $DOMAIN"
            done
        fi
    else
        print_error "Restoration verification failed - checksums don't match!"
        exit 1
    fi
else
    print_error "Restoration failed - acme.json not created!"
    exit 1
fi

# ============================================
# Restart Traefik
# ============================================

echo ""
print_info "To apply the restored certificates, restart Traefik:"
echo "  docker-compose restart traefik"
echo ""
echo -n "Do you want to restart Traefik now? (yes/NO): "
read -r RESTART

if [[ "$RESTART" == "yes" ]]; then
    echo "Restarting Traefik..."
    cd "$BASE_DIR"

    if docker-compose restart traefik; then
        print_success "Traefik restarted successfully!"

        # Wait a moment and check status
        sleep 3
        if docker ps | grep -q traefik-proxy; then
            print_success "Traefik is running"

            # Show last few log lines
            echo ""
            echo "📋 Recent Traefik logs:"
            docker logs traefik-proxy --tail 10
        else
            print_error "Traefik is not running! Check logs: docker logs traefik-proxy"
        fi
    else
        print_error "Failed to restart Traefik!"
        echo "  Try manually: docker-compose restart traefik"
    fi
else
    echo ""
    print_info "Remember to restart Traefik manually to apply changes:"
    echo "  docker-compose restart traefik"
fi

echo ""
print_success "Restoration process complete!"