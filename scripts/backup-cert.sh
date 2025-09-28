#!/bin/bash

# ============================================
# Traefik Certificate Backup Script
# ============================================
# Backs up acme.json to cert_backup folder with timestamp
# Maintains only the last 5 backups to save space

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Configuration
BACKUP_DIR="${BASE_DIR}/cert_backup"
ACME_FILE="${BASE_DIR}/data/acme.json"
MAX_BACKUPS=5

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

# ============================================
# Main backup process
# ============================================

echo "🔒 Starting certificate backup..."

# Check if acme.json exists
if [ ! -f "$ACME_FILE" ]; then
    print_error "acme.json not found at $ACME_FILE"
    echo "  Nothing to backup. Certificates haven't been generated yet."
    exit 1
fi

# Create backup directory if it doesn't exist
if [ ! -d "$BACKUP_DIR" ]; then
    mkdir -p "$BACKUP_DIR"
    print_success "Created backup directory: $BACKUP_DIR"
fi

# Get file size
SIZE=$(du -h "$ACME_FILE" | cut -f1)

# Create backup with timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/acme_${TIMESTAMP}.json"

# Copy with preserved permissions
cp -p "$ACME_FILE" "$BACKUP_FILE"

# Verify backup
if [ -f "$BACKUP_FILE" ]; then
    # Check file integrity
    if [ "$(sha256sum "$ACME_FILE" | cut -d' ' -f1)" == "$(sha256sum "$BACKUP_FILE" | cut -d' ' -f1)" ]; then
        print_success "Certificate backed up successfully"
        echo "  📁 Location: $BACKUP_FILE"
        echo "  📏 Size: $SIZE"

        # Set correct permissions
        chmod 600 "$BACKUP_FILE"
        print_success "Permissions set to 600 (read/write owner only)"
    else
        print_error "Backup verification failed - checksums don't match!"
        rm "$BACKUP_FILE"
        exit 1
    fi
else
    print_error "Backup creation failed!"
    exit 1
fi

# ============================================
# Cleanup old backups (keep only last MAX_BACKUPS)
# ============================================

# Count existing backups
BACKUP_COUNT=$(ls -1 "${BACKUP_DIR}"/acme_*.json 2>/dev/null | wc -l)

if [ "$BACKUP_COUNT" -gt "$MAX_BACKUPS" ]; then
    print_warning "Found $BACKUP_COUNT backups, keeping only last $MAX_BACKUPS"

    # Get list of files to delete (oldest first)
    TO_DELETE=$((BACKUP_COUNT - MAX_BACKUPS))
    ls -1t "${BACKUP_DIR}"/acme_*.json | tail -n "$TO_DELETE" | while read OLD_BACKUP; do
        rm "$OLD_BACKUP"
        echo "  🗑️  Deleted old backup: $(basename "$OLD_BACKUP")"
    done

    print_success "Cleanup complete"
fi

# ============================================
# Show current backups
# ============================================

echo ""
echo "📋 Current certificate backups:"
ls -lht "${BACKUP_DIR}"/acme_*.json 2>/dev/null | head -n "$MAX_BACKUPS" | while read LINE; do
    echo "  $LINE"
done

echo ""
print_success "Certificate backup completed!"

# ============================================
# Show restoration instructions
# ============================================

echo ""
echo "📌 To restore a backup, run:"
echo "  cp ${BACKUP_DIR}/acme_TIMESTAMP.json ${BASE_DIR}/data/acme.json"
echo "  chmod 600 ${BASE_DIR}/data/acme.json"
echo "  docker-compose restart traefik"