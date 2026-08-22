import { useEffect, useState } from "react";
import { NavLink, Outlet } from "react-router-dom";
import { brand } from "../theme/brand.js";
import { health } from "../api/client.js";

const NAV = [
  { group: "Overview", items: [["/", "Dashboard"]] },
  { group: "Protection", items: [
    ["/source-networks", "Source Networks"],
    ["/policies", "Policies"],
    ["/rulesets", "Rulesets"],
    ["/lists", "Block / Allow Lists"],
  ]},
  { group: "Operations", items: [
    ["/alerts", "Alerts"],
    ["/reports", "Reports"],
    ["/explorer", "API Explorer"],
  ]},
];

export default function AppShell() {
  const [h, setH] = useState(null);
  useEffect(() => { health().then(setH).catch(() => setH({ error: true })); }, []);
  const ok = h && h.api_key_present && !h.error;

  return (
    <div className="shell">
      <aside className="sidebar">
        <div className="logo">
          {/* Official logo drops in at web/public/brand/; falls back to wordmark */}
          <img src={brand.logoFull} alt={brand.company}
               onError={(e) => { e.target.style.display = "none"; e.target.nextSibling.style.display = "block"; }} />
          <span className="fallback" style={{ display: "none" }}>
            {brand.company}<small> DDR</small>
          </span>
        </div>
        <nav className="nav">
          {NAV.map((g) => (
            <div key={g.group}>
              <div className="group">{g.group}</div>
              {g.items.map(([to, label]) => (
                <NavLink key={to} to={to} end={to === "/"}
                  className={({ isActive }) => (isActive ? "active" : "")}>{label}</NavLink>
              ))}
            </div>
          ))}
        </nav>
      </aside>

      <div className="main">
        <header className="topbar">
          <div className="org">
            {h?.org_id ? `Organization ${h.org_id}` : brand.defaultOrg}
            <small>{brand.company} · {brand.productName}</small>
          </div>
          <div className="right">
            <span className={"health-dot " + (ok ? "ok" : "bad")}>
              {h?.error ? "backend unreachable" : ok ? `connected · ${h.endpoints} endpoints` : "API key not set"}
            </span>
          </div>
        </header>
        <div className="content"><Outlet /></div>
      </div>
    </div>
  );
}
