import { defineConfig } from "vitest/config";

// The test files resolve workspace packages to their TypeScript source. The eve servers they
// spawn load `better-supabase` from its build, so `turbo` builds it first (turbo.json).
const conditions = [
  "@better-supabase/source",
  "module",
  "node",
  "development|production",
];

// Without a stack (the unit lanes) there is nothing to run: the suites need the database and
// spawn eve servers, so no file is collected and the task passes.
const live = (process.env.SUPABASE_DB_URL ?? "") !== "";

export default defineConfig({
  test: {
    exclude: live ? ["**/node_modules/**"] : ["**"],
    passWithNoTests: true,
    globalSetup: ["./src/global-setup.ts"],
    // Each file starts an eve server on its own port, but all share one database.
    fileParallelism: false,
    testTimeout: 60_000,
    hookTimeout: 120_000,
  },
  resolve: { conditions },
  ssr: { resolve: { conditions } },
});
