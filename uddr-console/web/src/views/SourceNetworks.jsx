import { useState } from "react";
import { Card } from "../components/ui.jsx";

// The Source Network (server-group) create/list endpoints are NOT in the
// documented Swagger. This view is the branded UI, ready to wire to the real
// endpoint once captured from the portal's DevTools → Network tab and added to
// EXTRA_ALLOWED in the backend. Until then it manages rows locally so the UX is
// reviewable end-to-end.
const EMPTY = { name: "", address: "", policy: "Group Policy" };

export default function SourceNetworks() {
  const [rows, setRows] = useState([
    { name: "Digicert Labs", address: "74.88.57.189/32", policy: "Group Policy" },
  ]);
  const [draft, setDraft] = useState(EMPTY);

  const add = () => {
    if (!draft.name || !draft.address) return;
    setRows((r) => [...r, draft]);
    setDraft(EMPTY);
  };
  const remove = (i) => setRows((r) => r.filter((_, k) => k !== i));

  return (
    <div>
      <h1 className="page-title">Source Networks</h1>
      <p className="page-sub">
        Define the source networks you wish to protect and assign each to a protection policy.
      </p>

      <div className="notice" style={{ marginBottom: 24 }}>
        This screen is wired to local state. The UltraDDR API for creating source
        networks (server groups) isn’t in the published spec — capture it from the
        portal and add the path to <span className="mono">EXTRA_ALLOWED</span> in the
        backend, then swap the handlers here to call it.
      </div>

      <Card title="Add a source network">
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 220px auto", gap: 12, alignItems: "end" }}>
          <Field label="Source Network Name">
            <input value={draft.name} onChange={(e) => setDraft({ ...draft, name: e.target.value })} />
          </Field>
          <Field label="Address (IP / CIDR)">
            <input placeholder="70.185.138.0/24" value={draft.address}
                   onChange={(e) => setDraft({ ...draft, address: e.target.value })} />
          </Field>
          <Field label="Assigned Policy">
            <select value={draft.policy} onChange={(e) => setDraft({ ...draft, policy: e.target.value })}>
              <option>Group Policy</option>
              <option>Default</option>
            </select>
          </Field>
          <button className="btn" onClick={add}>Add</button>
        </div>
      </Card>

      <div style={{ height: 20 }} />
      <Card title={`${rows.length} Source Network${rows.length === 1 ? "" : "s"}`}>
        <table className="tbl">
          <thead><tr><th>Name</th><th>Address</th><th>Assigned Policy</th><th></th></tr></thead>
          <tbody>
            {rows.map((r, i) => (
              <tr key={i}>
                <td>{r.name}</td>
                <td className="mono">{r.address}</td>
                <td>{r.policy}</td>
                <td style={{ textAlign: "right" }}>
                  <button className="btn ghost sm" onClick={() => remove(i)}>Delete</button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </Card>
    </div>
  );
}

function Field({ label, children }) {
  return (
    <label style={{ display: "block" }}>
      <div style={{ fontSize: "var(--fs-xs)", color: "var(--text-muted)", marginBottom: 6, fontWeight: 600 }}>{label}</div>
      {children}
    </label>
  );
}
