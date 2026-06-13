#!/usr/bin/env bash
# ============================================================================
# 02-install-suricata.sh  —  homelab-siem
#
# Installs Suricata (native, not Docker), renders our config template with
# your .env values, pulls the ET Open ruleset, validates the config, and runs
# Suricata as a systemd service sniffing the port-mirror interface in IDS mode.
#
# Idempotent: re-running re-renders the config and reloads the service.
# Run as pi2 (uses sudo).
# ============================================================================
set -euo pipefail

c_blue=$'\033[1;34m'; c_yellow=$'\033[1;33m'; c_red=$'\033[1;31m'; c_green=$'\033[1;32m'; c_off=$'\033[0m'
info() { printf '%s[*]%s %s\n' "$c_blue"   "$c_off" "$*"; }
ok()   { printf '%s[+]%s %s\n' "$c_green"  "$c_off" "$*"; }
warn() { printf '%s[!]%s %s\n' "$c_yellow" "$c_off" "$*" >&2; }
die()  { printf '%s[x]%s %s\n' "$c_red"    "$c_off" "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] && die "Run as your normal user (pi2), not root."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$REPO_DIR/.env"
TEMPLATE="$REPO_DIR/configs/suricata/suricata.yaml"

[[ -f "$ENV_FILE" ]]  || die "No .env at $ENV_FILE."
[[ -f "$TEMPLATE" ]]  || die "Missing template $TEMPLATE."
# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a

# ---- validate required .env values ----------------------------------------
LOG_MOUNT="${LOG_MOUNT:-/var/lib/siem}"
: "${HOME_NET:?HOME_NET is empty in .env (e.g. 192.168.1.0/24)}"
: "${SURICATA_INTERFACE:?SURICATA_INTERFACE is empty in .env (e.g. eth0)}"

info "HOME_NET=$HOME_NET  INTERFACE=$SURICATA_INTERFACE  LOG_MOUNT=$LOG_MOUNT"

# The mirror interface must actually exist on this Pi, or capture silently
# does nothing.
if ! ip link show "$SURICATA_INTERFACE" >/dev/null 2>&1; then
  warn "Interface '$SURICATA_INTERFACE' not found. Available interfaces:"
  ip -o link show | awk -F': ' '{print "    " $2}'
  die "Fix SURICATA_INTERFACE in .env (the port-mirror destination NIC)."
fi

# ---------------------------------------------------------------------------
# 1. Install Suricata + tools
# ---------------------------------------------------------------------------
info "Installing suricata + ethtool ..."
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y suricata suricata-update ethtool
ok "Suricata $(suricata --build-info 2>/dev/null | awk '/^Version/{print $3; exit}') installed."

# ---------------------------------------------------------------------------
# 2. Render the config template (sed: only our 3 placeholders) and install it
# ---------------------------------------------------------------------------
sudo mkdir -p "$LOG_MOUNT/suricata"

if [[ -f /etc/suricata/suricata.yaml && ! -f /etc/suricata/suricata.yaml.orig ]]; then
  sudo cp /etc/suricata/suricata.yaml /etc/suricata/suricata.yaml.orig
  info "Backed up distro config to /etc/suricata/suricata.yaml.orig"
fi

info "Rendering config -> /etc/suricata/suricata.yaml"
# Use a sed delimiter that won't appear in CIDRs/paths. '|' is safe here.
sed -e "s|__HOME_NET__|${HOME_NET}|g" \
    -e "s|__SURICATA_INTERFACE__|${SURICATA_INTERFACE}|g" \
    -e "s|__LOG_MOUNT__|${LOG_MOUNT}|g" \
    "$TEMPLATE" | sudo tee /etc/suricata/suricata.yaml >/dev/null

# Guard: fail loudly if any placeholder survived (typo / missing var).
if sudo grep -q '__[A-Z_]*__' /etc/suricata/suricata.yaml; then
  die "Unsubstituted placeholder left in rendered config — check .env."
fi
ok "Config rendered."

# ---------------------------------------------------------------------------
# 3. Pull the ET Open ruleset into /var/lib/suricata/rules/suricata.rules
# ---------------------------------------------------------------------------
info "Updating rules (Emerging Threats Open)..."
sudo suricata-update --no-test || warn "suricata-update reported issues; continuing to config test."
ok "Rules updated."

# ---------------------------------------------------------------------------
# 4. Validate the config BEFORE we (re)start the service
# ---------------------------------------------------------------------------
info "Validating config (suricata -T)..."
if ! sudo suricata -T -c /etc/suricata/suricata.yaml -v; then
  die "Config test FAILED. Service not started. Fix the errors above."
fi
ok "Config test passed."

# ---------------------------------------------------------------------------
# 5. systemd: run on the mirror interface, IDS mode, foreground (Type=simple)
#    A drop-in override keeps the distro unit but pins ExecStart to OUR config
#    and prepares the NIC (promisc + offloads off) so a mirror tap is seen
#    correctly. Runs as root so it can capture and write to $LOG_MOUNT.
# ---------------------------------------------------------------------------
info "Configuring systemd service..."
sudo mkdir -p /etc/systemd/system/suricata.service.d
sudo tee /etc/systemd/system/suricata.service.d/override.conf >/dev/null <<EOF
[Service]
User=root
Group=root
# Port-mirror frames are addressed to other hosts, so the NIC must be in
# promiscuous mode; hardware offloads must be off or Suricata sees mangled
# segments. The leading '-' on ethtool tolerates NICs lacking some knobs.
ExecStartPre=/sbin/ip link set ${SURICATA_INTERFACE} promisc on
ExecStartPre=-/sbin/ethtool -K ${SURICATA_INTERFACE} gro off lro off tso off gso off
ExecStart=
ExecStart=/usr/bin/suricata -c /etc/suricata/suricata.yaml --af-packet --runmode workers
Restart=on-failure
RestartSec=5
EOF

sudo systemctl daemon-reload
sudo systemctl enable suricata
sudo systemctl restart suricata

# ---------------------------------------------------------------------------
# 6. Verify it's actually capturing
# ---------------------------------------------------------------------------
sleep 5
if ! systemctl is-active --quiet suricata; then
  sudo journalctl -u suricata --no-pager -n 40
  die "Suricata failed to start — see logs above."
fi
ok "Suricata is running on $SURICATA_INTERFACE."

EVE="$LOG_MOUNT/suricata/eve.json"
if [[ -f "$EVE" ]]; then
  ok "eve.json exists: $EVE"
else
  warn "eve.json not created yet at $EVE. It appears once Suricata logs its first"
  warn "event (or its first stats flush). Confirm again after a minute, and make"
  warn "sure the port mirror (Phase 3) is actually feeding $SURICATA_INTERFACE."
fi

info "Tip: 'sudo tail -f $EVE' to watch events; 'suricatasc -c iface-stat $SURICATA_INTERFACE' for capture stats."
ok "Suricata install complete. Next: ./install/03-install-docker.sh"
