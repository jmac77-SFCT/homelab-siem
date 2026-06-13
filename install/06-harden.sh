#!/usr/bin/env bash
# ============================================================================
# 06-harden.sh  —  homelab-siem
#
# Applies the SECURITY.md threat-model hardening to the Pi:
#   - UFW: default-deny inbound; allow SSH from the LAN + everything on the
#     tailnet (tailscale0). Outbound open.
#   - fail2ban on SSH.
#   - unattended-upgrades (automatic security patches).
#   - SSH: key-only auth, root login disabled.
#
# ORDER MATTERS: SSH access is allowed in UFW BEFORE the firewall is enabled,
# and password auth is only disabled AFTER confirming a key is authorized, so
# you cannot lock yourself out by running this over SSH.
#
# Idempotent. Run as pi2 (uses sudo).
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
[[ -f "$ENV_FILE" ]] || die "No .env at $ENV_FILE."
# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a
: "${HOME_NET:?HOME_NET is empty in .env}"

info "Installing ufw, fail2ban, unattended-upgrades..."
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ufw fail2ban unattended-upgrades

# ---------------------------------------------------------------------------
# 1. UFW — allow SSH + Tailscale FIRST, then flip to default-deny.
# ---------------------------------------------------------------------------
info "Configuring UFW..."
sudo ufw --force reset >/dev/null
sudo ufw default deny incoming
sudo ufw default allow outgoing

# SSH from each LAN CIDR in HOME_NET (comma-separated supported). This keeps
# your current ssh pi2@jmacpi2.local session alive.
IFS=',' read -ra NETS <<< "$HOME_NET"
for net in "${NETS[@]}"; do
  net="$(echo "$net" | xargs)"   # trim whitespace
  [[ -n "$net" ]] || continue
  info "  allow SSH from $net"
  sudo ufw allow from "$net" to any port 22 proto tcp
done

# Everything arriving over the tailnet is trusted (this is how you reach
# Grafana:3000 and SSH remotely). Grafana is NOT opened to the LAN.
if ip link show tailscale0 >/dev/null 2>&1; then
  info "  allow all inbound on tailscale0"
  sudo ufw allow in on tailscale0
else
  warn "tailscale0 not present yet. Run 05-configure-tailscale.sh first, then"
  warn "re-run this script (or: sudo ufw allow in on tailscale0) for remote access."
fi

sudo ufw --force enable
sudo ufw status verbose
ok "UFW enabled (default-deny inbound)."

# ---------------------------------------------------------------------------
# 2. fail2ban on SSH
# ---------------------------------------------------------------------------
info "Configuring fail2ban (sshd jail)..."
sudo tee /etc/fail2ban/jail.d/sshd.local >/dev/null <<'EOF'
[sshd]
enabled  = true
backend  = systemd
maxretry = 5
findtime = 10m
bantime  = 1h
EOF
sudo systemctl enable --now fail2ban
sudo systemctl restart fail2ban
ok "fail2ban active on SSH."

# ---------------------------------------------------------------------------
# 3. unattended-upgrades (security patches applied automatically)
# ---------------------------------------------------------------------------
info "Enabling unattended-upgrades..."
sudo tee /etc/apt/apt.conf.d/20auto-upgrades >/dev/null <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
sudo systemctl enable --now unattended-upgrades
ok "unattended-upgrades enabled."

# ---------------------------------------------------------------------------
# 4. SSH hardening — LAST, and only if a key is already authorized.
# ---------------------------------------------------------------------------
info "Hardening SSH..."
AUTH_KEYS="$HOME/.ssh/authorized_keys"
if [[ -s "$AUTH_KEYS" ]]; then
  sudo tee /etc/ssh/sshd_config.d/99-siem-hardening.conf >/dev/null <<'EOF'
# homelab-siem SSH hardening (06-harden.sh)
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PermitRootLogin no
EOF
  # Validate BEFORE applying; never reload a broken sshd config.
  if sudo sshd -t; then
    # 'reload' keeps your current session alive (unlike 'restart').
    sudo systemctl reload ssh 2>/dev/null || sudo systemctl reload sshd
    ok "SSH is now key-only, root login disabled."
  else
    sudo rm -f /etc/ssh/sshd_config.d/99-siem-hardening.conf
    die "sshd config test failed — reverted. SSH left unchanged."
  fi
else
  warn "No authorized_keys found at $AUTH_KEYS — NOT disabling password auth"
  warn "(that would lock you out). Add your public key first:"
  warn "    ssh-copy-id pi2@jmacpi2.local"
  warn "then re-run this script."
fi

echo
ok "Hardening complete. Summary:"
sudo ufw status verbose | sed 's/^/    /'
echo
ok "Phase 2 install scripts are done. The Pi is firewalled, patched, and locked down."
info "Verify remote access works (Grafana over Tailscale, SSH) BEFORE you close this session."
