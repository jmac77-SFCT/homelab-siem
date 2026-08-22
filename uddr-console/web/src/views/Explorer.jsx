import { useEffect, useState } from "react";
import { Card, Spinner, ErrorNote } from "../components/ui.jsx";
import { spec, call } from "../api/client.js";

// Generic spec-driven caller for any documented endpoint not yet given a
// bespoke view. Mirrors the standalone explorer, inside the branded shell.
export default function Explorer() {
  const [sp, setSp] = useState(null);
  const [err, setErr] = useState(null);
  const [sel, setSel] = useState(null);
  const [payload, setPayload] = useState("{}");
  const [resp, setResp] = useState(null);

  useEffect(() => { spec().then(setSp).catch(setErr); }, []);
  if (err) return <ErrorNote error={err} />;
  if (!sp) return <Spinner label="Loading API spec…" />;

  const eps = [];
  for (const [path, ops] of Object.entries(sp.paths || {}))
    for (const [method, op] of Object.entries(ops))
      if (["get", "post", "put", "delete"].includes(method))
        eps.push({ path, method, id: op.operationId, tag: (op.tags || [])[0] || "Other" });
  eps.sort((a, b) => (a.tag + a.id).localeCompare(b.tag + b.id));

  const run = async () => {
    setResp({ loading: true });
    try {
      const body = JSON.parse(payload || "{}");
      const r = await call(sel.path, body, sel.method);
      setResp(r);
    } catch (e) { setResp({ error: e.message }); }
  };

  return (
    <div>
      <h1 className="page-title">API Explorer</h1>
      <p className="page-sub">Call any documented UltraDDR endpoint through the proxy.</p>
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 20 }}>
        <Card title="Endpoint">
          <select style={{ width: "100%" }} onChange={(e) => {
            const ep = eps[Number(e.target.value)]; setSel(ep); setResp(null);
          }}>
            <option>— choose —</option>
            {eps.map((ep, i) => <option key={i} value={i}>{ep.tag} · {ep.id || ep.path}</option>)}
          </select>
          {sel && <>
            <div className="mono" style={{ margin: "12px 0", color: "var(--warning)" }}>{sel.method.toUpperCase()} {sel.path}</div>
            <textarea className="code" value={payload} onChange={(e) => setPayload(e.target.value)} />
            <div style={{ marginTop: 12 }}><button className="btn" onClick={run}>Execute</button></div>
          </>}
        </Card>
        <Card title="Response">
          {!resp && <span style={{ color: "var(--text-muted)" }}>Run a call to see the response.</span>}
          {resp?.loading && <Spinner label="Calling…" />}
          {resp?.error && <ErrorNote error={resp.error} />}
          {resp && !resp.loading && !resp.error && <>
            <div className="mono" style={{ marginBottom: 8 }}>HTTP {resp.status}</div>
            <pre className="out">{JSON.stringify(resp.data, null, 2)}</pre>
          </>}
        </Card>
      </div>
    </div>
  );
}
