import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// The React app talks only to the FastAPI proxy (which injects the API key).
// In dev, proxy /api to the backend on :8080. In prod, build and serve dist
// behind the same origin as the backend.
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      "/api": {
        target: process.env.VITE_PROXY_TARGET || "http://localhost:8080",
        changeOrigin: true,
      },
    },
  },
  build: { outDir: "dist" },
});
