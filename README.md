# homelab-siem

A self-contained network SIEM (Security Information and Event Management) stack for a home network, designed to run on a Raspberry Pi 5 in out-of-band / port-mirror mode.

Answers the question: **"Which device on my network is calling where, and is any of it suspicious?"**

## Stack

- **Suricata** — IDS / network traffic inspection
- **Promtail** — log shipper (Suricata `eve.json` → Loki)
- **Loki** — log storage
- **Grafana** — dashboards + alerting
- **Tailscale** — secure remote access (no public ports)
- **Telegram bot** — push alerts

All ARM64-native. No cloud dependencies.

## Architecture

```
UniFi Gateway Lite
        |
USW Ultra 60W ----(port mirror)----> Raspberry Pi 5
        |                                  |
   your devices                  Suricata -> Promtail
                                              |
                                            Loki
                                              |
                                          Grafana --(Tailscale)--> you
                                              |
                                          Telegram alerts
```

The Pi receives a **copy** of all traffic via switch port mirroring. No traffic is routed through it, so there is zero impact on network performance.

## Layout

```
homelab-siem/
  install/         numbered shell scripts, run in order on the Pi
  configs/         Suricata, Promtail, Loki, Grafana configs
  docker/          docker-compose for Loki + Grafana + Promtail
  scripts/         maintenance: backup, health check, rule updates
  dashboards/      Grafana dashboard JSON
  docs/            deployment guide, troubleshooting
  .env.example     copy to .env and fill in secrets (gitignored)
```

## Quick start

On your Mac (or wherever you develop):

```bash
git clone https://github.com/<you>/homelab-siem.git
cd homelab-siem
cp .env.example .env   # fill in Telegram token, etc. - never commit this
```

On the Pi (after OS install + SSH access):

```bash
git clone https://github.com/<you>/homelab-siem.git
cd homelab-siem
./install/01-system-prep.sh
./install/02-install-suricata.sh
./install/03-install-docker.sh
./install/04-deploy-stack.sh
./install/05-configure-tailscale.sh
./install/06-harden.sh
```

Then access Grafana at `http://<pi-tailscale-ip>:3000`.

See `docs/deployment.md` for the full walkthrough.

## Hardware

- Raspberry Pi 5 (8GB) with active cooler and 45W PSU
- 128GB+ microSD (OS)
- 2-4TB external HDD (logs, 90-day retention)
- Ethernet to a switch port configured for port mirroring (UniFi USW Ultra 60W in this build)

## Security

- All secrets live in `.env` (gitignored). Never committed.
- Pi is firewalled (UFW), SSH key-only, fail2ban enabled, unattended-upgrades on.
- No services exposed publicly. Remote access only via Tailscale.

See [SECURITY.md](SECURITY.md) for vulnerability reporting.

## License

MIT — see [LICENSE](LICENSE).
