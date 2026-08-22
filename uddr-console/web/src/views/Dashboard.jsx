import { useState } from "react";
import { Card, Stat, Spinner, ErrorNote } from "../components/ui.jsx";
import { api, health } from "../api/client.js";
import { useAsync } from "../hooks.js";

export default function Dashboard() {
  const [org, setOrg] = useState(null);
  const h = useAsync(() => health().then((r) => { setOrg(r.org_id); return r; }), []);

  return (
    <div>
      <h1 className="page-title">Dashboard</h1>
      <p className="page-sub">Protective DNS overview for your organization.</p>

      {h.loading && <Spinner />}
      {h.error && <ErrorNote error={h.error} />}
      {h.data && !h.data.api_key_present && (
        <div className="notice">
          Set <span className="mono">UDDR_API_KEY</span> on the backend to load live stats.
          The console is running; it just has no credential yet.
        </div>
      )}
      {h.data && h.data.api_key_present && <Stats org={org} />}
    </div>
  );
}

function Stats({ org }) {
  const s = useAsync(() => api.orgStats(org), [org]);
  if (s.loading) return <Spinner label="Loading stats…" />;
  if (s.error) return <ErrorNote error={s.error} />;

  // The exact stats shape depends on the account; render what we can and show
  // the raw payload so you can map fields into tiles precisely.
  const d = s.data?.data || {};
  const pick = (...keys) => keys.map((k) => d[k]).find((v) => v != null);
  const total = pick("total", "total_queries", "queries", "count");
  const blocked = pick("blocked", "blocks", "blocked_queries");

  return (
    <div style={{ display: "grid", gap: 24 }}>
      <div className="stat-grid">
        <Stat label="Total queries (period)" value={fmt(total)} />
        <Stat label="Blocked" value={fmt(blocked)} block />
        <Stat label="Allowed" value={fmt(total != null && blocked != null ? total - blocked : undefined)} />
        <Stat label="Block rate" value={pct(blocked, total)} />
      </div>
      <Card title="Raw stats payload" actions={<span className="mono">/account/organization/stats</span>}>
        <pre className="out">{JSON.stringify(s.data?.data, null, 2)}</pre>
      </Card>
    </div>
  );
}

const fmt = (n) => (n == null ? "—" : Number(n).toLocaleString());
const pct = (a, b) => (a == null || !b ? "—" : ((a / b) * 100).toFixed(1) + "%");
