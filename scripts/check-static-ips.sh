#!/bin/bash

# ============================================
# Static IP Audit for traefik-* networks
# ============================================
# Rule: every container attached to a traefik-* network declares an explicit
# ipv4_address in the STATIC zone (subnet minus ip-range). Traefik owns .2.
#
# This script inspects the LIVE networks and reports, per container:
#   OK       IP in the static zone (an explicit ipv4_address)
#   WARNING  IP inside the dynamic pool (ip-range): the container has no static
#            IP -> add ipv4_address to its compose file
#   ERROR    network has no ip-range at all (whole subnet dynamic): a container
#            without static IP can take Traefik's .2 at boot -> recreate the
#            network (docs/NETWORK_SEGMENTATION.md, "Migrating existing networks")
#   ERROR    Traefik missing from a network it must be on, or not on .2
#
# Exit code: 0 clean, 1 warnings only, 2 errors. Safe to run from cron.
#
# Why: on 2026-09-19 a container without static IP started before Traefik after
# a host reboot, took 10.241.0.2 from the pool and Traefik failed with
# "failed to set up container networking: Address already in use" for 36 h.

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header()  { echo ""; echo -e "${BLUE}============================================${NC}"; echo -e "${BLUE}   $1${NC}"; echo -e "${BLUE}============================================${NC}"; echo ""; }
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; WARNINGS=$((WARNINGS + 1)); }
print_error()   { echo -e "${RED}❌ $1${NC}"; ERRORS=$((ERRORS + 1)); }

WARNINGS=0
ERRORS=0
TRAEFIK_CONTAINER="${TRAEFIK_CONTAINER:-traefik-proxy}"
# Networks Traefik must be attached to (with .2). backend is intentionally excluded.
TRAEFIK_NETWORKS="traefik-public traefik-frontend traefik-management"

# --- IPv4 helpers ---
ip2int() { local IFS=.; read -r a b c d <<< "$1"; echo $(( (a<<24) | (b<<16) | (c<<8) | d )); }
in_cidr() {
    local ip=$1 cidr=$2 net bits mask
    net=${cidr%/*}; bits=${cidr#*/}
    mask=$(( bits == 0 ? 0 : (0xFFFFFFFF << (32 - bits)) & 0xFFFFFFFF ))
    [ $(( $(ip2int "$ip") & mask )) -eq $(( $(ip2int "$net") & mask )) ]
}

if ! command -v docker &>/dev/null; then
    echo "docker not found"; exit 2
fi

print_header "Static IP audit - traefik-* networks"

NETWORKS=$(docker network ls --format '{{.Name}}' | grep '^traefik-' | sort)
if [ -z "$NETWORKS" ]; then
    print_error "No traefik-* networks found (run scripts/setup.sh)"
    echo ""; exit 2
fi

for net in $NETWORKS; do
    subnet=$(docker network inspect -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}' "$net")
    iprange=$(docker network inspect -f '{{range .IPAM.Config}}{{.IPRange}}{{end}}' "$net")
    # Docker >= 29 renders an unset IPRange as "invalid Prefix" instead of ""
    case "$iprange" in ""|"invalid Prefix"|"<no value>"|"<nil>") iprange="" ;; esac
    reserved="${subnet%.*}.2"

    echo -e "${BLUE}$net${NC}  subnet $subnet  dynamic pool ${iprange:-<none>}"

    if [ -z "$iprange" ]; then
        print_error "$net has NO ip-range: whole subnet is dynamic, static IPs are not protected"
        echo "   Recreate the network with --ip-range (see docs/NETWORK_SEGMENTATION.md)"
    fi

    # name ip/prefix per attached container
    members=$(docker network inspect -f '{{range $k,$v := .Containers}}{{$v.Name}} {{$v.IPv4Address}}{{"\n"}}{{end}}' "$net" | sed '/^$/d' | sort)

    traefik_ip=""
    while read -r name addr; do
        [ -z "$name" ] && continue
        ip=${addr%/*}
        if [ "$name" == "$TRAEFIK_CONTAINER" ]; then
            traefik_ip=$ip
        fi
        if [ -n "$iprange" ] && in_cidr "$ip" "$iprange"; then
            print_warning "$name -> $ip is in the DYNAMIC pool: no ipv4_address declared (rule violation)"
            echo "   Add to its compose file:  networks: { $net: { ipv4_address: \"${subnet%.*}.N\" } }  with N in the static zone"
        elif [ -z "$iprange" ]; then
            echo "   ?  $name -> $ip (cannot tell static from dynamic without ip-range)"
        else
            print_success "$name -> $ip (static zone)"
        fi
    done <<< "$members"

    if [[ " $TRAEFIK_NETWORKS " == *" $net "* ]]; then
        if [ -z "$traefik_ip" ]; then
            print_error "$TRAEFIK_CONTAINER is not attached to $net (is it running?)"
        elif [ "$traefik_ip" != "$reserved" ]; then
            print_error "$TRAEFIK_CONTAINER is on $traefik_ip, expected $reserved"
        fi
    fi
    echo ""
done

print_header "Summary"
echo -e "Errors: ${RED}${ERRORS}${NC}   Warnings: ${YELLOW}${WARNINGS}${NC}"
echo ""
if [ "$ERRORS" -gt 0 ]; then
    print_error "Fix the errors above - Traefik is at risk of failing to start after a reboot"
    exit 2
elif [ "$WARNINGS" -gt 0 ]; then
    print_warning "Rule violations found: give those containers a static IP in the static zone"
    exit 1
else
    print_success "All containers on traefik-* networks use static IPs; pools are protected"
    exit 0
fi
