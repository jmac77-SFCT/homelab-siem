"""
UltraDDR Console — backend proxy.

Holds the UltraDDR API key server-side (env var, never sent to the browser) and
forwards whitelisted calls to https://api.ddr.ultradns.com with the X-Api-Key
header injected. Everything the browser can reach goes through /api/* here.

Run:
    export UDDR_API_KEY=...        # your UltraDDR API key (X-Api-Key)
    export UDDR_ORG_ID=12345       # optional default organization_id
    uvicorn app:app --host 0.0.0.0 --port 8080

The frontend is served from ../frontend at /.
"""
import json
import os
import re
from pathlib import Path

import httpx
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles

BASE_URL = os.environ.get("UDDR_BASE", "https://api.ddr.ultradns.com")
API_KEY = os.environ.get("UDDR_API_KEY", "")
ORG_ID = os.environ.get("UDDR_ORG_ID", "")
SPEC_PATH = Path(__file__).with_name("swagger.json")
FRONTEND_DIR = Path(__file__).resolve().parent.parent / "frontend"

spec = json.loads(SPEC_PATH.read_text(encoding="utf-8"))

# Build a set of allowed (method, path-regex) pairs from the spec so the proxy
# can only reach documented UltraDDR endpoints — no arbitrary SSRF target.
_allowed: list[tuple[str, re.Pattern]] = []
for _path, _ops in spec.get("paths", {}).items():
    pat = re.compile("^" + re.sub(r"\{[^/}]+\}", r"[^/]+", _path) + "$")
    for _method in _ops:
        if _method.lower() in ("get", "post", "put", "delete", "patch"):
            _allowed.append((_method.lower(), pat))

# Endpoints the portal uses but the Swagger omits (e.g. Source Network / server
# groups). Add discovered paths here to allow them through the proxy.
EXTRA_ALLOWED: list[tuple[str, str]] = [
    # ("post", r"^/userdata/servergroup/v2/create$"),
]
for _m, _rx in EXTRA_ALLOWED:
    _allowed.append((_m, re.compile(_rx)))


def _is_allowed(method: str, path: str) -> bool:
    method = method.lower()
    return any(m == method and rx.match(path) for m, rx in _allowed)


app = FastAPI(title="UltraDDR Console")


@app.get("/api/health")
def health():
    return {
        "ok": True,
        "base_url": BASE_URL,
        "api_key_present": bool(API_KEY),
        "org_id": ORG_ID or None,
        "endpoints": len(_allowed),
    }


@app.get("/api/spec")
def get_spec():
    """Serve the Swagger so the frontend can build its UI from it."""
    return JSONResponse(spec)


@app.post("/api/call")
async def call(req: Request):
    """
    Generic authenticated forwarder.
    Body: {"method": "post", "path": "/userdata/policy/v2/list", "payload": {...}}
    Injects X-Api-Key and forwards to BASE_URL. Returns upstream status + body.
    """
    try:
        body = await req.json()
    except Exception:
        raise HTTPException(400, "body must be JSON")

    method = (body.get("method") or "post").lower()
    path = body.get("path") or ""
    payload = body.get("payload", {})
    if not path.startswith("/"):
        path = "/" + path
    if not _is_allowed(method, path):
        raise HTTPException(403, f"path not allowed: {method.upper()} {path}")
    if not API_KEY:
        raise HTTPException(500, "UDDR_API_KEY is not set on the server")

    # Convenience: auto-fill organization_id if the caller left it blank.
    if isinstance(payload, dict) and ORG_ID and "organization_id" in payload and not payload["organization_id"]:
        payload["organization_id"] = int(ORG_ID)

    headers = {"X-Api-Key": API_KEY, "Content-Type": "application/json"}
    url = BASE_URL + path
    async with httpx.AsyncClient(timeout=30) as client:
        try:
            resp = await client.request(method.upper(), url, headers=headers, json=payload)
        except httpx.RequestError as e:
            raise HTTPException(502, f"upstream request failed: {e}")

    try:
        data = resp.json()
    except Exception:
        data = {"raw": resp.text}
    return JSONResponse({"status": resp.status_code, "data": data}, status_code=200)


# Serve the frontend (mounted last so /api/* wins).
if FRONTEND_DIR.is_dir():
    app.mount("/", StaticFiles(directory=str(FRONTEND_DIR), html=True), name="frontend")
