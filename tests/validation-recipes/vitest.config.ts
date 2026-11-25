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
    // Each file installs its recipe in a transaction; parallel installs deadlock.
    fileParallelism: false,
    // A recipe renders every module it names from source; a cold CI runner took
    // over 5 s for the CRM recipe and failed a release run.
    testTimeout: 30_000,
  },
  resolve: { conditions },
  ssr: { resolve: { conditions } },
});
