// --- Módulo: vite.config.ts ---
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react-swc";
import path from "path";

// --- Configuração do servidor de desenvolvimento Vite ---
export default defineConfig({
  server: {
    // *host localhost e porta 8080 (compatível com Playwright e2e)*
    host: "localhost",
    port: 8080,
  },
  plugins: [react()],
  resolve: {
    alias: {
      // *alias @ aponta para src/*
      "@": path.resolve(__dirname, "./src"),
    },
  },
});
