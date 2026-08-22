// UltraDDR Console — spec-driven API explorer.
// Reads /api/spec, lists every documented endpoint grouped by tag, builds a
// request template from the endpoint's body schema, and calls it through the
// backend proxy (/api/call) which injects the API key server-side.

let SPEC = null;
let ORG_ID = null;

const $ = (s) => document.querySelector(s);

async function boot() {
  // Health banner
  try {
    const h = await (await fetch("/api/health")).json();
    ORG_ID = h.org_id;
    const el = $("#health");
    if (h.api_key_present) {
      el.textContent = `● connected · ${h.base_url} · ${h.endpoints} endpoints${h.org_id ? " · org " + h.org_id : ""}`;
      el.className = "health ok";
    } else {
      el.textContent = "● UDDR_API_KEY not set on server";
      el.className = "health bad";
    }
  } catch (e) {
    $("#health").textContent = "● backend unreachable";
    $("#health").className = "health bad";
  }

  SPEC = await (await fetch("/api/spec")).json();
  renderNav();
  $("#filter").addEventListener("input", renderNav);
}

function endpoints() {
  const out = [];
  for (const [path, ops] of Object.entries(SPEC.paths || {})) {
    for (const [method, op] of Object.entries(ops)) {
      if (!["get", "post", "put", "delete", "patch"].includes(method)) continue;
      out.push({
        path, method,
        id: op.operationId || "",
        summary: op.summary || "",
        tag: (op.tags && op.tags[0]) || "Other",
        op,
      });
    }
  }
  return out;
}

function renderNav() {
  const q = ($("#filter").value || "").toLowerCase();
  const eps = endpoints().filter(
    (e) => !q || (e.path + e.id + e.summary + e.tag).toLowerCase().includes(q)
  );
  const byTag = {};
  for (const e of eps) (byTag[e.tag] ||= []).push(e);
  const box = $("#endpoints");
  box.innerHTML = "";
  for (const tag of Object.keys(byTag).sort()) {
    const t = document.createElement("div");
    t.className = "tag"; t.textContent = tag;
    box.appendChild(t);
    for (const e of byTag[tag]) {
      const d = document.createElement("div");
      d.className = "ep";
      d.innerHTML = `<span class="m">${e.method.toUpperCase()}</span><span class="name">${e.id || e.path}</span>`;
      d.onclick = () => { document.querySelectorAll(".ep").forEach(x => x.classList.remove("active")); d.classList.add("active"); showDetail(e); };
      box.appendChild(d);
    }
  }
}

// Resolve a $ref/schema into an example JSON object (shallow, cycle-safe).
function example(schema, seen = new Set(), depth = 0) {
  if (!schema || depth > 4) return null;
  if (schema.$ref) {
    const name = schema.$ref.split("/").pop();
    if (seen.has(name)) return {};
    seen = new Set(seen); seen.add(name);
    const def = (SPEC.definitions || {})[name];
    return example(def, seen, depth + 1);
  }
  if (schema.type === "array") return [example(schema.items, seen, depth + 1)].filter(x => x !== null);
  if (schema.type === "object" || schema.properties) {
    const o = {};
    for (const [k, v] of Object.entries(schema.properties || {})) o[k] = example(v, seen, depth + 1);
    return o;
  }
  if (schema.type === "integer" || schema.type === "number") return 0;
  if (schema.type === "boolean") return false;
  return "";
}

function bodyTemplate(op) {
  const p = (op.parameters || []).find((x) => x.in === "body");
  let tpl = p ? example(p.schema) : {};
  if (tpl && typeof tpl === "object" && !Array.isArray(tpl)) {
    if ("organization_id" in tpl && ORG_ID) tpl.organization_id = Number(ORG_ID);
  }
  return tpl;
}

function showDetail(e) {
  const tpl = bodyTemplate(e.op);
  $("#detail").className = "";
  $("#detail").innerHTML = `
    <h2>${e.id || e.path}</h2>
    <p class="sub">${e.summary || ""} <em>· ${e.tag}</em></p>
    <div class="pathline">${e.method.toUpperCase()} ${e.path}</div>
    <label>Request body (JSON)</label>
    <textarea id="payload">${JSON.stringify(tpl, null, 2)}</textarea>
    <button id="exec">Execute</button>
    <div id="resp" class="resp"></div>`;
  $("#exec").onclick = () => execute(e);
}

async function execute(e) {
  const resp = $("#resp");
  let payload;
  try { payload = JSON.parse($("#payload").value || "{}"); }
  catch (err) { resp.innerHTML = `<span class="status err">invalid JSON: ${err.message}</span>`; return; }
  resp.innerHTML = `<span class="status">calling…</span>`;
  try {
    const r = await fetch("/api/call", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ method: e.method, path: e.path, payload }),
    });
    const j = await r.json();
    const ok = j.status >= 200 && j.status < 300;
    resp.innerHTML = `<span class="status ${ok ? "ok" : "err"}">HTTP ${j.status}</span>
      <pre>${JSON.stringify(j.data, null, 2).replace(/</g, "&lt;")}</pre>`;
  } catch (err) {
    resp.innerHTML = `<span class="status err">proxy error: ${err.message}</span>`;
  }
}

boot();
