import { defineConfig } from "vitest/config";

// Editor and ad hoc runs; CI runs each workspace's `test` task through Turbo.
export default defineConfig({
  test: {
    projects: [
      "packages/better-supabase",
      "packages/ox-config",
      "apps/docs",
      "apps/marketing",
      "tests/bundle",
      "tests/validation-crm",
      "tests/validation-request-context",
    ],
  },
});
