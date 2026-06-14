#!/usr/bin/env bash
# ============================================================================
# render-promtail-devices.sh  —  homelab-siem
#
# Renders configs/promtail/promtail-config.yaml from .template, replacing the
# __DEVICE_TEMPLATE__ placeholder with a Go template built from
# configs/devices.json (IP -> name). Then reloads Promtail so new logs get the
# `device` label.
#
# Run after import-dhcp-csv.sh (or sync-unifi-devices.sh) refreshes the map.
# If devices.json is missing, `device` simply falls back to the raw src_ip.
# Also invoked by 04-deploy-stack.sh so a fresh deploy always has a rendered
# config. No sudo needed (uses the docker group).
# ============================================================================
set -euo pipefail

c_blue=$'\033[1;34m'; c_yellow=$'\033[1;33m'; c_red=$'\033[1;31m'; c_green=$'\033[1;32m'; c_off=$'\033[0m'
info() { printf '%s[*]%s %s\n' "$c_blue"   "$c_off" "$*"; }
ok()   { printf '%s[+]%s %s\n' "$c_green"  "$c_off" "$*"; }
warn() { printf '%s[!]%s %s\n' "$c_yellow" "$c_off" "$*" >&2; }
die()  { printf '%s[x]%s %s\n' "$c_red"    "$c_off" "$*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TMPL="$REPO_DIR/configs/promtail/promtail-config.yaml.template"
OUT="$REPO_DIR/configs/promtail/promtail-config.yaml"
DEVICES="$REPO_DIR/configs/devices.json"

[[ -f "$TMPL" ]] || die "Missing template: $TMPL"
command -v python3 >/dev/null || die "python3 required."

info "Rendering Promtail config from device map..."
python3 - "$TMPL" "$OUT" "$DEVICES" <<'PY'
import json, os, sys
tmpl_path, out_path, dev_path = sys.argv[1], sys.argv[2], sys.argv[3]

devices = {}
if os.path.exists(dev_path):
    with open(dev_path, encoding='utf-8') as f:
        devices = json.load(f)

# Build a Go text/template: maps .src_ip -> device name, else the raw IP.
# Lives inside a single-quoted YAML scalar, so escape any single quotes ('').
parts = []
for i, (ip, name) in enumerate(devices.items()):
    kw = 'if' if i == 0 else 'else if'
    safe = str(name).replace("'", "''")
    parts.append('{{ %s eq .src_ip "%s" }}%s' % (kw, ip, safe))
go_tmpl = (''.join(parts) + '{{ else }}{{ .src_ip }}{{ end }}') if parts else '{{ .src_ip }}'

with open(tmpl_path, encoding='utf-8') as f:
    rendered = f.read()
if '__DEVICE_TEMPLATE__' not in rendered:
    sys.exit("Placeholder __DEVICE_TEMPLATE__ not found in template.")
rendered = rendered.replace('__DEVICE_TEMPLATE__', go_tmpl)
with open(out_path, 'w', encoding='utf-8') as f:
    f.write(rendered)
print(f"{len(devices)}")
PY
ok "Rendered $OUT ($(python3 -c 'import json,os,sys;p=sys.argv[1];print(len(json.load(open(p))) if os.path.exists(p) else 0)' "$DEVICES") device names)."

# Reload Promtail if it's running (no-op during a fresh 04 deploy).
if command -v docker >/dev/null 2>&1 && docker ps --format '{{.Names}}' 2>/dev/null | grep -qx siem-promtail; then
  info "Restarting siem-promtail to apply..."
  docker restart siem-promtail >/dev/null && ok "Promtail reloaded."
else
  info "Promtail not running yet — will pick this up on deploy."
fi
