import { defineConfig } from "vitest/config";

// Workspace packages resolve to their TypeScript source, so tests run without
// building them first. The rest is Vite's default server condition list.
const conditions = [
  "@better-supabase/source",
  "module",
  "node",
  "development|production",
];

export default defineConfig({
  resolve: { conditions },
  ssr: { resolve: { conditions } },
  // These tests connect a definition from the core entry, which holds no connection runtime; the setup file installs the full one.
  // The upgrade and single-tenant renders took over 60 seconds on a loaded release runner.
  test: { setupFiles: ["./src/connection-runtime.ts"], testTimeout: 180_000 },
});
