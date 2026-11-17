/// <reference types="vitest/config" />
import tailwindcss from "@tailwindcss/vite";
import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

// O Vite repassa a API e os webhooks para o Rails: o navegador fala com uma origem só, sem CORS.
const apiTarget = process.env.API_PROXY_TARGET ?? "http://localhost:3000";

export default defineConfig({
  plugins: [react(), tailwindcss()],
  server: {
    port: 5173,
    // No Docker Desktop do Windows, mudanças feitas no disco do Windows não geram eventos dentro do
    // container: sem polling, o Vite continua servindo o código antigo.
    watch: process.env.VITE_USE_POLLING === "true" ? { usePolling: true, interval: 300 } : undefined,
    proxy: {
      "/api": { target: apiTarget, changeOrigin: true },
      "/webhooks": { target: apiTarget, changeOrigin: true },
      // WebSocket do mapa vivo (ActionCable).
      "/cable": { target: apiTarget, ws: true, changeOrigin: true },
    },
  },
  test: {
    environment: "jsdom",
    globals: true,
    setupFiles: ["./src/test/setup.ts"],
    css: false,
  },
});
