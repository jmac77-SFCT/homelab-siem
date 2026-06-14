#!/usr/bin/env bash
# ============================================================================
# sync-unifi-devices.sh  —  homelab-siem
#
# Pulls the client list from the UniFi Network *Integration API* (API-key auth)
# and writes an IP -> name map to configs/devices.json (gitignored). That map
# turns raw src_ip values into your human-readable UniFi labels in dashboards
# and Telegram alerts.
#
# STAGE 1 of device-name enrichment: this only produces devices.json.
#
# Requires (in .env): UNIFI_HOST, UNIFI_API_KEY, UNIFI_SITE (default "default").
# Create the key in UniFi: Settings -> Control Plane -> Integrations -> API Key.
# Needs Network 9.x+ (the Integration API). Safe to re-run / schedule via cron.
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
: "${UNIFI_API_KEY:?UNIFI_API_KEY is empty in .env (Settings->Control Plane->Integrations)}"
UNIFI_SITE="${UNIFI_SITE:-default}"
command -v jq >/dev/null || die "jq not installed (apt-get install -y jq)."

BASE="https://$UNIFI_HOST/proxy/network/integration/v1"
api() {  # api <path>  -> body on stdout; verifies HTTP 200
  local path="$1" tmp code
  tmp="$(mktemp)"
  code="$(curl -sk -o "$tmp" -w '%{http_code}' \
    -H "X-API-KEY: $UNIFI_API_KEY" -H 'Accept: application/json' \
    "$BASE$path" || true)"
  if [[ "$code" != "200" ]]; then
    warn "GET $path -> HTTP $code"
    warn "Body: $(head -c 200 "$tmp")"
    rm -f "$tmp"
    [[ "$code" == "401" || "$code" == "403" ]] && die "Auth failed — check UNIFI_API_KEY."
    [[ "$code" == "404" ]] && die "Integration API not found — Network version may be <9.0, or wrong UNIFI_HOST."
    die "UniFi API request failed."
  fi
  cat "$tmp"; rm -f "$tmp"
}

# ---- 1. Resolve the site id (Integration API uses a UUID, not "default") ---
info "Connecting to UniFi Integration API at $BASE ..."
sites="$(api /sites)"
site_id="$(jq -r --arg ref "$UNIFI_SITE" \
  'first(.data[] | select((.internalReference // .name | ascii_downcase) == ($ref|ascii_downcase)) | .id) // ""' \
  <<<"$sites")"
[[ -n "$site_id" ]] || site_id="$(jq -r '.data[0].id // ""' <<<"$sites")"
[[ -n "$site_id" ]] || die "Could not resolve a site id. Raw: $(head -c 200 <<<"$sites")"
ok "Site id: $site_id"

# ---- 2. Fetch clients (paginated) -----------------------------------------
info "Fetching clients..."
all='[]'; offset=0; limit=200
while :; do
  page="$(api "/sites/$site_id/clients?offset=$offset&limit=$limit")"
  all="$(jq -c --argjson a "$all" '$a + (.data // [])' <<<"$page")"
  total="$(jq -r '.totalCount // (.data|length) // 0' <<<"$page")"
  offset=$((offset + limit))
  [[ "$offset" -ge "$total" || "$offset" -gt 5000 ]] && break
done
got="$(jq 'length' <<<"$all")"
info "Retrieved $got client records."

# ---- 3. Build the IP -> name map ------------------------------------------
# Field names vary slightly by version, so try the common ones.
mkdir -p "$(dirname "$OUT")"
jq '
  [ .[]
    | (.ipAddress // .ip) as $ip
    | select($ip != null and $ip != "")
    | { key: $ip, value: (.name // .hostname // .displayName // .macAddress // .mac) }
  ] | from_entries
' <<<"$all" > "$OUT"

mapped="$(jq 'length' "$OUT")"
[[ "$mapped" -gt 0 ]] || warn "0 mappings — clients may lack IPs, or field names differ (show me a sample)."
ok "Wrote $mapped IP->name mappings to $OUT"
jq -r 'to_entries | .[:8][] | "    \(.key)  ->  \(.value)"' "$OUT" 2>/dev/null || true

echo
ok "Stage 1 done. Next: render this into Promtail enrichment (stage 2)."
