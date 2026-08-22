# UltraDDR Console

A self-hosted management UI for UltraDDR, built on the documented API
(`https://api.ddr.ultradns.com`). A small FastAPI backend holds the API key
**server-side** and proxies whitelisted calls; a spec-driven frontend renders
every documented endpoint from the bundled `swagger.json`.

```
uddr-console/
  backend/    FastAPI auth proxy (app.py) + swagger.json
  frontend/   static console (index.html / app.js / style.css)
```

## Why a proxy

The UltraDDR API authenticates with an `X-Api-Key` header. That key is a
credential and must never reach the browser, so the frontend only ever talks to
this backend, which injects the key and forwards to UltraDDR. The proxy also
whitelists paths to the documented endpoints (no arbitrary SSRF target).

## Run

```bash
cd uddr-console/backend
python3 -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt

export UDDR_API_KEY=your-ultraddr-api-key   # never commit this
export UDDR_ORG_ID=12345                     # optional: auto-fills organization_id

uvicorn app:app --host 0.0.0.0 --port 8080
```

Open http://localhost:8080 — the health bar shows connection status, and the
sidebar lists every endpoint grouped by API tag. Pick one, edit the auto-filled
JSON body, Execute.

## Coverage

Everything in the Swagger is available immediately: Policy, Ruleset, List
Management, Categories, Organization (settings/stats), Alerts, Reports, Users,
Teams.

**Not in the Swagger:** the **Source Network** (server-group) create/update the
portal uses. Capture the real call from the portal's DevTools → Network tab,
then add its path to `EXTRA_ALLOWED` in `app.py` and it becomes callable through
the proxy (and the explorer) like any other endpoint.

## Security notes

- `.env` and `.venv` are gitignored; never commit the API key.
- The proxy only forwards to `UDDR_BASE` and only to whitelisted paths.
- Serve behind your homelab network / Tailscale; this has no auth of its own yet
  (add one before exposing it beyond localhost).
