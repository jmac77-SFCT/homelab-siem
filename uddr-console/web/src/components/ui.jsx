// Small reusable presentational components.
export function Card({ title, actions, children }) {
  return (
    <div className="card">
      {(title || actions) && (
        <div className="card-h"><span>{title}</span>{actions}</div>
      )}
      <div className="card-b">{children}</div>
    </div>
  );
}

export function Stat({ label, value, block }) {
  return (
    <div className="stat">
      <div className="label">{label}</div>
      <div className={"value" + (block ? " block" : "")}>{value}</div>
    </div>
  );
}

export function Badge({ kind, children }) {
  return <span className={`badge ${kind || ""}`}>{children}</span>;
}

export function BlockAllowToggle({ value, onChange }) {
  return (
    <span className="toggle">
      <button className={"block" + (value === "block" ? " active" : "")} onClick={() => onChange("block")}>Block</button>
      <button className={"allow" + (value === "allow" ? " active" : "")} onClick={() => onChange("allow")}>Allow</button>
    </span>
  );
}

export function Spinner({ label = "Loading…" }) {
  return <div className="spinner">{label}</div>;
}

export function ErrorNote({ error }) {
  return <div className="err">⚠ {String(error?.message || error)}</div>;
}
