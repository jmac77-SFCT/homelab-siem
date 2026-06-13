#!/usr/bin/env bash
# ============================================================================
# 03-install-docker.sh  —  homelab-siem
#
# Installs Docker Engine + the Compose v2 plugin (ARM64) using Docker's
# official convenience script, enables the service, and adds your user to the
# docker group so 04-deploy-stack.sh can run `docker compose` without sudo.
#
# Idempotent: if Docker + Compose are already present it skips the install and
# just re-checks the service and group membership.
# Run as pi2 (uses sudo).
# ============================================================================
set -euo pipefail

c_blue=$'\033[1;34m'; c_yellow=$'\033[1;33m'; c_red=$'\033[1;31m'; c_green=$'\033[1;32m'; c_off=$'\033[0m'
info() { printf '%s[*]%s %s\n' "$c_blue"   "$c_off" "$*"; }
ok()   { printf '%s[+]%s %s\n' "$c_green"  "$c_off" "$*"; }
warn() { printf '%s[!]%s %s\n' "$c_yellow" "$c_off" "$*" >&2; }
die()  { printf '%s[x]%s %s\n' "$c_red"    "$c_off" "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] && die "Run as your normal user (pi2), not root."
TARGET_USER="$USER"

# ---------------------------------------------------------------------------
# 1. Install Docker Engine + Compose plugin (skip if already there)
# ---------------------------------------------------------------------------
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  ok "Docker + Compose already installed ($(docker --version)). Skipping install."
else
  info "Installing Docker Engine via get.docker.com (ARM64)..."
  TMP_SH="$(mktemp)"
  curl -fsSL https://get.docker.com -o "$TMP_SH"
  sudo sh "$TMP_SH"
  rm -f "$TMP_SH"
  # get.docker.com bundles docker-compose-plugin, but make sure.
  if ! docker compose version >/dev/null 2>&1; then
    info "Installing docker-compose-plugin explicitly..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y docker-compose-plugin
  fi
  ok "Installed $(docker --version) / $(docker compose version)"
fi

# ---------------------------------------------------------------------------
# 2. Enable + start the daemon
# ---------------------------------------------------------------------------
sudo systemctl enable --now docker
systemctl is-active --quiet docker || die "Docker daemon did not start."
ok "Docker daemon is running."

# ---------------------------------------------------------------------------
# 3. Add the user to the docker group (so `docker` works without sudo)
# ---------------------------------------------------------------------------
if id -nG "$TARGET_USER" | tr ' ' '\n' | grep -qx docker; then
  ok "$TARGET_USER is already in the docker group."
else
  info "Adding $TARGET_USER to the docker group..."
  sudo usermod -aG docker "$TARGET_USER"
  warn "Group change won't apply to THIS shell. Before running 04-deploy-stack.sh:"
  warn "    log out and back in   (ssh pi2@jmacpi2.local again)"
  warn "    -- or, just for now -- run:  newgrp docker"
  warn "04-deploy-stack.sh also falls back to sudo automatically if needed."
fi

ok "Docker install complete. Next: ./install/04-deploy-stack.sh"
