import { useState } from "react";
import { Card, Spinner, ErrorNote } from "../components/ui.jsx";
import { api, health } from "../api/client.js";
import { useAsync } from "../hooks.js";

export default function Lists() {
  const [org, setOrg] = useState(null);
  const h = useAsync(() => health().then((r) => { setOrg(r.org_id); return r; }), []);
  const connected = h.data?.api_key_present;
  return (
    <div>
      <h1 className="page-title">Block / Allow Lists</h1>
      <p className="page-sub">Custom domain, FQDN, IP and CIDR lists.</p>
      {!connected && h.data && <div className="notice">Set the API key on the backend to load lists.</div>}
      {connected && <ListTable org={org} />}
    </div>
  );
}

function ListTable({ org }) {
  const r = useAsync(() => api.listLists(org), [org]);
  if (r.loading) return <Spinner label="Loading lists…" />;
  if (r.error) return <ErrorNote error={r.error} />;
  return (
    <Card title="Lists" actions={<span className="mono">/data/list</span>}>
      <pre className="out">{JSON.stringify(r.data?.data, null, 2)}</pre>
    </Card>
  );
}
