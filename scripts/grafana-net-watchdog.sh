#!/usr/bin/env bash
# ============================================================================
# grafana-net-watchdog.sh  —  homelab-siem
#
# Self-heal for the Grafana boot race: if Docker starts siem-grafana before
# tailscale0 has its IP, the port bind fails and the container can come up
# attached to NO docker network — it can't reach Loki (rule evals error) or
# api.telegram.org (so not even the DatasourceError page gets out). The SIEM
# goes silently blind. This has happened twice (2026-08-16, 2026-08-21).
#
# Run from cron every 5 minutes as pi2 (docker group, no sudo):
#     */5 * * * * /home/pi2/homelab-siem/scripts/grafana-net-watchdog.sh
#
# It only acts when (a) the container exists with zero networks and
# (b) tailscale0 is up with an address — so at boot it waits out the race
# instead of recreating into the same failure.
# ============================================================================
set -u

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

nets="$(docker inspect siem-grafana --format '{{len .NetworkSettings.Networks}}' 2>/dev/null)" || exit 0
[ "$nets" = "0" ] || exit 0

# Don't recreate until tailscale0 actually has an IP, or the bind fails again.
ip -4 addr show tailscale0 2>/dev/null | grep -q 'inet ' || exit 0

logger -t siem-watchdog "siem-grafana has no docker network (boot race); force-recreating"
cd "$REPO_DIR" || exit 1
docker compose --env-file .env \
  -f docker/docker-compose.yml \
  -f docker/docker-compose.override.yml \
  up -d --force-recreate grafana \
  && logger -t siem-watchdog "siem-grafana recreated OK" \
  || logger -t siem-watchdog "siem-grafana recreate FAILED"
