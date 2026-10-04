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
  test: {
    setupFiles: ["./src/setup.ts"],
    // Each file installs the kit in a transaction; parallel installs deadlock.
    fileParallelism: false,
  },
  resolve: { conditions },
  ssr: { resolve: { conditions } },
});
