import { Card } from "../components/ui.jsx";

export default function Placeholder({ title }) {
  return (
    <div>
      <h1 className="page-title">{title}</h1>
      <p className="page-sub">This view is scaffolded and ready to build out.</p>
      <Card>
        <p style={{ margin: 0, color: "var(--text-muted)" }}>
          Wire this page to the relevant API tag using the same pattern as the
          Policies view — <span className="mono">useAsync(() =&gt; api.…())</span> and
          render into branded components.
        </p>
      </Card>
    </div>
  );
}
