import { useState } from "react";
import { Card, Spinner, ErrorNote } from "../components/ui.jsx";
import { api, health } from "../api/client.js";
import { useAsync } from "../hooks.js";

export default function Rulesets() {
  const [org, setOrg] = useState(null);
  const h = useAsync(() => health().then((r) => { setOrg(r.org_id); return r; }), []);
  const connected = h.data?.api_key_present;
  return (
    <div>
      <h1 className="page-title">Rulesets</h1>
      <p className="page-sub">Custom decision rules (e.g. Exfiltration and Tunneling).</p>
      {!connected && h.data && <div className="notice">Set the API key on the backend to load rulesets.</div>}
      {connected && <RulesetTable org={org} />}
    </div>
  );
}

function RulesetTable({ org }) {
  const r = useAsync(() => api.listRulesets(org), [org]);
  if (r.loading) return <Spinner label="Loading rulesets…" />;
  if (r.error) return <ErrorNote error={r.error} />;
  return (
    <Card title="Rulesets" actions={<span className="mono">/userdata/ruleset/v2/list</span>}>
      <pre className="out">{JSON.stringify(r.data?.data, null, 2)}</pre>
    </Card>
  );
}
