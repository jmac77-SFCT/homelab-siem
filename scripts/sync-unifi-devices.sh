#!/usr/bin/env bash
# ============================================================================
# sync-unifi-devices.sh  —  homelab-siem
#
# Pulls the client list from the UniFi controller and writes an IP -> name map
# to configs/devices.json (gitignored). That map is what turns raw src_ip
# values into your human-readable UniFi labels in dashboards and Telegram
# alerts.
#
# STAGE 1 of device-name enrichment: this only produces devices.json.
# (Stage 2 renders it into Promtail + reloads — added separately.)
#
# Targets UniFi OS gateways/consoles (UDM / Cloud Gateway / Gateway Lite),
# where the Network API lives behind /proxy/network. Requires a LOCAL UniFi
# admin (read-only is fine) in .env: UNIFI_HOST/USERNAME/PASSWORD/SITE.
#
# Safe to re-run; intended to be run on a schedule (cron) later.
# ============================================================================
set -euo pipefail

c_blue=$'\033[1;34m'; c_yellow=$'\033[1;33m'; c_red=$'\033[1;31m'; c_green=$'\033[1;32m'; c_off=$'\033[0m'
info() { printf '%s[*]%s %s\n' "$c_blue"   "$c_off" "$*"; }
ok()   { printf '%s[+]%s %s\n' "$c_green"  "$c_off" "$*"; }
warn() { printf '%s[!]%s %s\n' "$c_yellow" "$c_off" "$*" >&2; }
die()  { printf '%s[x]%s %s\n' "$c_red"    "$c_off" "$*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$REPO_DIR/.env"
OUT="$REPO_DIR/configs/devices.json"

[[ -f "$ENV_FILE" ]] || die "No .env at $ENV_FILE."
# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a

: "${UNIFI_HOST:?UNIFI_HOST is empty in .env}"
: "${UNIFI_USERNAME:?UNIFI_USERNAME is empty in .env}"
: "${UNIFI_PASSWORD:?UNIFI_PASSWORD is empty in .env}"
UNIFI_SITE="${UNIFI_SITE:-default}"
command -v jq >/dev/null || die "jq not installed (apt-get install -y jq)."

COOKIES="$(mktemp)"
trap 'rm -f "$COOKIES"' EXIT

# ---- 1. Log in (UniFi OS) --------------------------------------------------
info "Logging in to UniFi at https://$UNIFI_HOST ..."
login_code="$(curl -sk -o /dev/null -w '%{http_code}' \
  -c "$COOKIES" \
  -X POST "https://$UNIFI_HOST/api/auth/login" \
  -H 'Content-Type: application/json' \
  --data "$(jq -nc --arg u "$UNIFI_USERNAME" --arg p "$UNIFI_PASSWORD" '{username:$u,password:$p}')" \
  || true)"

if [[ "$login_code" != "200" ]]; then
  warn "UniFi OS login returned HTTP $login_code."
  warn "If this is an OLD self-hosted controller (port 8443, not UniFi OS), the"
  warn "API path differs (/api/login + :8443). Tell me and I'll adapt the script."
  die  "Login failed — check UNIFI_HOST/USERNAME/PASSWORD in .env."
fi
ok "Authenticated."

# ---- 2. Fetch clients ------------------------------------------------------
info "Fetching client list (site: $UNIFI_SITE)..."
clients_json="$(curl -sk -b "$COOKIES" \
  "https://$UNIFI_HOST/proxy/network/api/s/$UNIFI_SITE/stat/sta")"

count="$(printf '%s' "$clients_json" | jq '.data | length' 2>/dev/null || echo 0)"
[[ "$count" -gt 0 ]] || die "No clients returned (site '$UNIFI_SITE' correct? Try 'default'). Raw: ${clients_json:0:200}"
info "Controller returned $count clients."

# ---- 3. Build the IP -> name map ------------------------------------------
# Prefer the user-set alias (.name), then hostname, then MAC. Only clients
# that currently have an IP.
mkdir -p "$(dirname "$OUT")"
printf '%s' "$clients_json" | jq '
  [ .data[]
    | select(.ip != null and .ip != "")
    | { key: .ip, value: (.name // .hostname // .mac) }
  ] | from_entries
' > "$OUT"

mapped="$(jq 'length' "$OUT")"
ok "Wrote $mapped IP->name mappings to $OUT"
info "Sample:"
jq -r 'to_entries | .[:8][] | "    \(.key)  ->  \(.value)"' "$OUT"

echo
ok "Stage 1 done. Next: render this into Promtail enrichment (stage 2)."
