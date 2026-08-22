import React from "react";
import ReactDOM from "react-dom/client";
import { createBrowserRouter, RouterProvider } from "react-router-dom";
import "./styles.css";
import AppShell from "./components/AppShell.jsx";
import Dashboard from "./views/Dashboard.jsx";
import SourceNetworks from "./views/SourceNetworks.jsx";
import Policies from "./views/Policies.jsx";
import Rulesets from "./views/Rulesets.jsx";
import Lists from "./views/Lists.jsx";
import Placeholder from "./views/Placeholder.jsx";
import Explorer from "./views/Explorer.jsx";

const router = createBrowserRouter([
  {
    path: "/",
    element: <AppShell />,
    children: [
      { index: true, element: <Dashboard /> },
      { path: "source-networks", element: <SourceNetworks /> },
      { path: "policies", element: <Policies /> },
      { path: "rulesets", element: <Rulesets /> },
      { path: "lists", element: <Lists /> },
      { path: "alerts", element: <Placeholder title="Alerts" /> },
      { path: "reports", element: <Placeholder title="Reports" /> },
      { path: "explorer", element: <Explorer /> },
    ],
  },
]);

ReactDOM.createRoot(document.getElementById("root")).render(
  <React.StrictMode>
    <RouterProvider router={router} />
  </React.StrictMode>
);
