#!/usr/bin/env bash
# ============================================================================
# 04-deploy-stack.sh  —  homelab-siem
#
# Brings up the Docker stack (Loki + Promtail + Grafana), then VERIFIES the
# pipeline end to end: Suricata -> eve.json -> Promtail -> Loki.
#
# After this script succeeds you have a working SIEM. Grafana is on
# 127.0.0.1:3000 for now; 05-configure-tailscale.sh adds remote access.
#
# Idempotent: re-running re-applies the compose state.
# Run as pi2 (uses sudo only if your shell isn't in the docker group yet).
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
COMPOSE_FILE="$REPO_DIR/docker/docker-compose.yml"

[[ -f "$ENV_FILE" ]]      || die "No .env at $ENV_FILE."
[[ -f "$COMPOSE_FILE" ]]  || die "Missing $COMPOSE_FILE."
# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a
LOG_MOUNT="${LOG_MOUNT:-/var/lib/siem}"
: "${GRAFANA_ADMIN_PASSWORD:?GRAFANA_ADMIN_PASSWORD is empty in .env}"

# ---------------------------------------------------------------------------
# 1. Data directories owned by the container UIDs
#    Loki image runs as uid 10001; Grafana as uid 472. If the bind-mounted
#    dirs aren't owned by those, the containers can't write and crash-loop.
# ---------------------------------------------------------------------------
info "Preparing data dirs under $LOG_MOUNT ..."
sudo mkdir -p "$LOG_MOUNT/loki" "$LOG_MOUNT/grafana" "$LOG_MOUNT/suricata"
sudo chown -R 10001:10001 "$LOG_MOUNT/loki"
sudo chown -R 472:472     "$LOG_MOUNT/grafana"
ok "loki -> uid 10001, grafana -> uid 472."

# ---------------------------------------------------------------------------
# 2. Decide whether we need sudo for docker (group may not be active yet)
# ---------------------------------------------------------------------------
if docker info >/dev/null 2>&1; then
  SUDO=""
else
  warn "Can't reach Docker as $USER in this shell (docker group not active)."
  warn "Falling back to sudo. To avoid this, re-login after 03 or run 'newgrp docker'."
  SUDO="sudo"
fi
compose() { $SUDO docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"; }

# ---------------------------------------------------------------------------
# 3. Pull + launch
# ---------------------------------------------------------------------------
info "Pulling images (ARM64)..."
compose pull
info "Starting stack..."
compose up -d
compose ps

# ---------------------------------------------------------------------------
# 4. Wait for Loki to report healthy (its healthcheck hits /ready)
# ---------------------------------------------------------------------------
info "Waiting for Loki to become healthy..."
healthy=no
for _ in $(seq 1 40); do
  status="$($SUDO docker inspect -f '{{.State.Health.Status}}' siem-loki 2>/dev/null || echo none)"
  if [[ "$status" == "healthy" ]]; then healthy=yes; break; fi
  sleep 3
done
if [[ "$healthy" != yes ]]; then
  $SUDO docker logs --tail 40 siem-loki || true
  die "Loki did not become healthy. See logs above."
fi
ok "Loki is healthy."

# ---------------------------------------------------------------------------
# 5. VERIFY the pipeline: get Suricata to emit an event, then confirm it
#    landed in Loki via Promtail.
#
#    Even before the Phase 3 port mirror, Suricata (sniffing the interface)
#    will see the Pi's OWN traffic, so we force a few real DNS lookups
#    (random names defeat the resolver cache) to seed eve.json.
# ---------------------------------------------------------------------------
info "Seeding DNS lookups so Suricata produces events to ship..."
for n in 1 2 3 4 5; do
  getent hosts "siem-selftest-${n}-${RANDOM}.example.com" >/dev/null 2>&1 || true
done

LOKI="http://127.0.0.1:3100"
info "Checking that Promtail shipped a 'job=suricata' stream into Loki..."
shipped=no
for _ in $(seq 1 20); do
  if curl -fsS "$LOKI/loki/api/v1/label/job/values" 2>/dev/null | grep -q '"suricata"'; then
    shipped=yes; break
  fi
  sleep 3
done

echo
if [[ "$shipped" == yes ]]; then
  ok "PIPELINE VERIFIED: Suricata -> Promtail -> Loki is flowing."
  # Show a sample count of what's arrived in the last 15 minutes.
  cnt="$(curl -fsS --get "$LOKI/loki/api/v1/query" \
        --data-urlencode 'query=sum(count_over_time({job="suricata"}[15m]))' 2>/dev/null \
        | jq -r '.data.result[0].value[1] // "0"' 2>/dev/null || echo "?")"
  ok "Events in Loki over the last 15m: ${cnt}"
else
  warn "No 'job=suricata' stream in Loki yet. The stack is UP, but no Suricata"
  warn "events have shipped. Usually means no traffic on $SURICATA_INTERFACE yet."
  warn "Checklist:"
  warn "  - Suricata running?   systemctl is-active suricata"
  warn "  - eve.json growing?   sudo tail -f $LOG_MOUNT/suricata/eve.json"
  warn "  - Promtail logs?      $SUDO docker logs siem-promtail"
  warn "  - This is EXPECTED if the Phase 3 port mirror isn't set up yet."
fi

echo
ok "Stack deployed. Containers:"
compose ps --format 'table {{.Name}}\t{{.Status}}\t{{.Ports}}'
echo
info "Grafana (local only for now): http://127.0.0.1:3000  (admin / your GRAFANA_ADMIN_PASSWORD)"
info "From your laptop you can tunnel:  ssh -L 3000:127.0.0.1:3000 pi2@jmacpi2.local"
ok "Next: ./install/05-configure-tailscale.sh  (adds remote access + Telegram comes in Phase 5)."
