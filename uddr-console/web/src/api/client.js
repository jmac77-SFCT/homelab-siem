// API client — talks only to the local FastAPI proxy, which injects the API key
// and forwards to UltraDDR. Never call api.ddr.ultradns.com directly from here.

async function j(res) {
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(body.detail || `HTTP ${res.status}`);
  return body;
}

export function health() {
  return fetch("/api/health").then(j);
}

export function spec() {
  return fetch("/api/spec").then(j);
}

// Forward a call through the proxy. Returns { status, data } from upstream.
export async function call(path, payload = {}, method = "post") {
  const res = await fetch("/api/call", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ method, path, payload }),
  });
  const wrapped = await j(res);
  return wrapped; // { status, data }
}

// Convenience wrappers for the documented endpoints the views use.
export const api = {
  listPolicies: (org) => call("/userdata/policy/v2/list", { organization_id: org }),
  readPolicy: (org, id) => call("/userdata/policy/v2/read", { organization_id: org, id }),
  orgStats: (org, body = {}) => call("/account/organization/stats", { organization_id: org, ...body }),
  orgSettings: (org) => call("/account/organization/settings", { organization_id: org }),
  listRulesets: (org) => call("/userdata/ruleset/v2/list", { organization_id: org }),
  listLists: (org, body = {}) => call("/data/list", { organization_id: org, ...body }),
};
