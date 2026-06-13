# Security

This is a personal home-network SIEM. It is not commercial software, but it does run a sensitive workload (sniffing all home network traffic), so security is taken seriously.

## Reporting a vulnerability

If you find a security issue in any config, script, or default in this repo, please open a private GitHub Security Advisory rather than a public issue.

## Secrets handling in this repo

- All secrets live in `.env`, which is gitignored. The `.env.example` file documents the variables but contains no real values.
- No IP addresses, hostnames, MAC addresses, Tailscale auth keys, Telegram tokens, or Grafana passwords are committed.
- If you fork this repo, run `git log --all -p | grep -iE 'token|password|secret|authkey'` before pushing to make sure nothing leaked.

## Threat model for the deployed Pi

The Pi is a high-value target because it sees all network traffic. The deployment scripts in `install/06-harden.sh` apply:

- UFW firewall, default-deny inbound (allow only Tailscale + LAN SSH)
- SSH key-only authentication, root login disabled
- fail2ban on SSH
- `unattended-upgrades` for automatic security patches
- No services bound to public interfaces
- Grafana, Loki, Promtail bound to `127.0.0.1` and Tailscale interface only

If you deviate from these defaults, understand the trade-off.
