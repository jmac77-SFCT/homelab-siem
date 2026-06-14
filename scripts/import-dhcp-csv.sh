#!/usr/bin/env bash
# ============================================================================
# import-dhcp-csv.sh  —  homelab-siem
#
# Builds the IP -> name map (configs/devices.json, gitignored) from a UniFi
# DHCP/clients CSV export. Use this when the controller's API isn't reachable
# from the Pi: in UniFi, export your client/DHCP list to CSV, copy it to the
# Pi, and run:
#     ./scripts/import-dhcp-csv.sh /path/to/dhcp-export.csv
#
# Expects columns including "IP Address" and "Name" (UniFi's friendly label),
# falling back to "Hostname". Re-run after a fresh export when devices change.
# NOTE: most leases are dynamic, so set DHCP reservations on devices you want
# stably named, or re-import periodically.
# ============================================================================
set -euo pipefail

c_blue=$'\033[1;34m'; c_red=$'\033[1;31m'; c_green=$'\033[1;32m'; c_off=$'\033[0m'
info() { printf '%s[*]%s %s\n' "$c_blue"  "$c_off" "$*"; }
ok()   { printf '%s[+]%s %s\n' "$c_green" "$c_off" "$*"; }
die()  { printf '%s[x]%s %s\n' "$c_red"   "$c_off" "$*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT="$REPO_DIR/configs/devices.json"

CSV="${1:-}"
[[ -n "$CSV" ]] || die "Usage: $0 <dhcp-export.csv>"
[[ -f "$CSV" ]] || die "CSV not found: $CSV"
command -v python3 >/dev/null || die "python3 required."

mkdir -p "$(dirname "$OUT")"
python3 - "$CSV" "$OUT" <<'PY'
import csv, json, sys
src, out = sys.argv[1], sys.argv[2]
m = {}
with open(src, newline='', encoding='utf-8-sig') as f:
    for row in csv.DictReader(f):
        ip = (row.get('IP Address') or '').strip()
        name = (row.get('Name') or row.get('Hostname') or '').strip()
        if ip and name:
            m[ip] = name
with open(out, 'w', encoding='utf-8') as o:
    json.dump(m, o, indent=2, sort_keys=True, ensure_ascii=False)
print(f"{len(m)}")
PY

n="$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))))' "$OUT")"
ok "Wrote $n IP->name mappings to $OUT"
info "Sample:"
python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));[print(f"    {k}  ->  {v}") for k,v in list(d.items())[:10]]' "$OUT"
echo
ok "Next: ./scripts/render-promtail-devices.sh to apply names to Promtail."
