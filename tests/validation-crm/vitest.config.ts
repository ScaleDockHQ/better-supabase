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
  // These tests connect a definition from the core entry, which holds no connection runtime.
  test: { setupFiles: ["./src/connection-runtime.ts"] },
});
