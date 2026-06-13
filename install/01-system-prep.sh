#!/usr/bin/env bash
# ============================================================================
# 01-system-prep.sh  —  homelab-siem
#
# Prepares a fresh Raspberry Pi OS Lite (64-bit) box:
#   1. Updates the OS and installs base tooling.
#   2. Creates the SIEM data directory ($LOG_MOUNT from .env) on the SD card.
#
# Storage note: this build keeps everything on the Pi's microSD card. The
# DNS+alerts workload is only ~5-15GB over 90 days, which fits comfortably on
# a 128GB card. There is NO external drive to mount. If you later add a USB
# SSD, mount it yourself and point LOG_MOUNT at its mountpoint — nothing else
# in this script needs to change.
#
# Idempotent: safe to re-run. Run as the normal login user (pi2); it uses sudo.
# ============================================================================
set -euo pipefail

# ---- tiny logging helpers (inline so this script stands alone) -------------
c_blue=$'\033[1;34m'; c_yellow=$'\033[1;33m'; c_red=$'\033[1;31m'; c_green=$'\033[1;32m'; c_off=$'\033[0m'
info() { printf '%s[*]%s %s\n' "$c_blue"   "$c_off" "$*"; }
ok()   { printf '%s[+]%s %s\n' "$c_green"  "$c_off" "$*"; }
warn() { printf '%s[!]%s %s\n' "$c_yellow" "$c_off" "$*" >&2; }
die()  { printf '%s[x]%s %s\n' "$c_red"    "$c_off" "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] && die "Run as your normal user (pi2), not root. It will sudo where needed."

# ---- locate repo + load .env ----------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$REPO_DIR/.env"
[[ -f "$ENV_FILE" ]] || die "No .env at $ENV_FILE — copy .env.example to .env and fill it in first."
# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a
LOG_MOUNT="${LOG_MOUNT:-/var/lib/siem}"

info "Repo:      $REPO_DIR"
info "LOG_MOUNT: $LOG_MOUNT (on the SD card)"

# ---------------------------------------------------------------------------
# 1. OS update + base packages
# ---------------------------------------------------------------------------
info "Updating package lists and upgrading the OS (this can take a while)..."
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y

info "Installing base tooling..."
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  ca-certificates curl gnupg git jq lsb-release htop
ok "Base packages installed."

# ---------------------------------------------------------------------------
# 2. Create the SIEM data directory tree on the SD card
#    - $LOG_MOUNT/suricata : Suricata writes eve.json here (runs as root)
#    Loki/Grafana data dirs are created + chowned to their container UIDs in
#    04-deploy-stack.sh, since those UIDs are a Docker concern.
# ---------------------------------------------------------------------------
info "Creating $LOG_MOUNT ..."
sudo mkdir -p "$LOG_MOUNT/suricata"
ok "Created $LOG_MOUNT/suricata"

# Sanity-check there's enough free space for 90 days of logs.
AVAIL_GB="$(df -BG --output=avail "$LOG_MOUNT" | tail -1 | tr -dc '0-9')"
info "Free space on $LOG_MOUNT filesystem: ${AVAIL_GB}G"
if [[ "${AVAIL_GB:-0}" -lt 20 ]]; then
  warn "Less than 20G free. DNS+alerts/90d usually fits in ~5-15G, but keep an eye on it (scripts/ will add a disk health check)."
fi

df -h "$LOG_MOUNT"
ok "System prep complete. Next: ./install/02-install-suricata.sh"
