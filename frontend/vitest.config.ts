import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react-swc";
import path from "path";

export default defineConfig({
  plugins: [react()],
  test: {
    environment: "jsdom",
    globals: true,
    setupFiles: ["./src/test/setup.ts"],
    include: ["src/**/*.{test,spec}.{ts,tsx}"],
    // Evita flakiness no Windows/CI (arranque lento do jsdom com paralelismo)
    fileParallelism: false,
    testTimeout: 15_000,
    hookTimeout: 15_000,
  },
  resolve: {
    alias: { "@": path.resolve(__dirname, "./src") },
  },
});
