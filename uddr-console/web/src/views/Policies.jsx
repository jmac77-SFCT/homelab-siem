import { useState } from "react";
import { Card, Spinner, ErrorNote, Badge } from "../components/ui.jsx";
import { api, health } from "../api/client.js";
import { useAsync } from "../hooks.js";

export default function Policies() {
  const [org, setOrg] = useState(null);
  const h = useAsync(() => health().then((r) => { setOrg(r.org_id); return r; }), []);
  const connected = h.data?.api_key_present;

  return (
    <div>
      <h1 className="page-title">Policies</h1>
      <p className="page-sub">Protection policies and their precedence order.</p>
      {!connected && h.data && (
        <div className="notice">Set the API key on the backend to load live policies.</div>
      )}
      {connected && <PolicyTable org={org} />}
    </div>
  );
}

function PolicyTable({ org }) {
  const p = useAsync(() => api.listPolicies(org), [org]);
  if (p.loading) return <Spinner label="Loading policies…" />;
  if (p.error) return <ErrorNote error={p.error} />;

  const list = p.data?.data?.policies || p.data?.data?.results || p.data?.data || [];
  const rows = Array.isArray(list) ? list : [];

  return (
    <Card title={`${rows.length} policies`} actions={<span className="mono">/userdata/policy/v2/list</span>}>
      <table className="tbl">
        <thead><tr><th>#</th><th>Name</th><th>Status</th><th>Assigned groups</th><th>ID</th></tr></thead>
        <tbody>
          {rows.map((pol, i) => (
            <tr key={pol.id ?? i}>
              <td>{i + 1}</td>
              <td>{pol.name}</td>
              <td><Badge kind={pol.enabled ? "on" : "off"}>{pol.enabled ? "Enabled" : "Disabled"}</Badge></td>
              <td>{(pol.groups && pol.groups.length) ? pol.groups.join(", ") : <span style={{ color: "var(--text-faint)" }}>None</span>}</td>
              <td className="mono">{pol.id}</td>
            </tr>
          ))}
          {!rows.length && <tr><td colSpan="5" style={{ color: "var(--text-muted)" }}>No policies returned.</td></tr>}
        </tbody>
      </table>
    </Card>
  );
}
