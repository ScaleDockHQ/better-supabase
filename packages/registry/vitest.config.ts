import { defineConfig } from "vitest/config";

// Workspace packages resolve to their TypeScript source, so the hook tests run
// without building better-supabase first.
const conditions = [
  "@better-supabase/source",
  "module",
  "node",
  "development|production",
];

export default defineConfig({
  test: { include: ["tests/**/*.test.ts"], setupFiles: ["./tests/setup.ts"] },
  resolve: { conditions },
  ssr: { resolve: { conditions } },
});
